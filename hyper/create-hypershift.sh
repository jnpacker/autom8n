#!/bin/bash

hyCmd=hypershift
hyp_cluster_name=$1
ocpver=$2

# Store the kube context so that ck use will work
kubeconfig_tmp=$(mktemp)
kubeconfig=$(echo $HOME)/.kube/config
kubeconfig_context=$(mktemp --suffix=_context)
cp ${kubeconfig} ${kubeconfig_context}

# Make sure we restore the context on all types of exit
trap restore_context EXIT

instanceType="t3.xlarge"
replicaCount="3"
volSize="35"

function usage() {
  echo
  echo "Usage: create-hypershift.sh <hypershift_cluster_name> <ocp_version> [-i <instance_type>|-r <node_count>|-s <root_volume_size>]"
  echo
  echo "         * instance_type: m5.large, m5.xlarge (default), m5.2xlarge (default: m5.xlarge)"
  echo "         * node_count   : How many nodes on the worker plane (nodePool) to create (default: 3)"
  echo "         * root_volume_size: How large to make the root volume (default: 30)"

}

export KUBECONFIG=${kubeconfig_context}
curContext=$(oc config current-context)
if [ "${curContext}" != "${HYP_MANAGEMENTCLUSTER}" ]; then
  echo ">> WARNING << * ${curContext} does not match Hypershift management cluster context ${HYP_MANAGEMENTCLUSTER}"
  echo "              * Press Ctrl-c to cancel, or press <ENTER> to switch to ${HYP_MANAGEMENTCLUSTER}"
  read
  oc config use-context ${HYP_MANAGEMENTCLUSTER}
fi

function restore_context() {
  #oc config use-context ${orig_context}
  rm ${kubeconfig_context}
  rm ${kubeconfig_tmp}
}

if [ "$hyp_cluster_name" == "" ]; then
  echo "You must include a hypershift cluster name"
  usage
  exit 1
fi

echo "Hypershift cluster name: ${hyp_cluster_name}"

if [ "${ocpver}" == "" ] || [[ "${ocpver}" != "4."* ]]; then
  echo "You must include a version of OpenShift to use"
  usage
  exit 1
fi

#Check that Hypershift is installed
oc get crds | grep hostedclusters.hypershift.openshift.io > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "Install hypershift \"$hyCmd install\""
  exit 1
fi

oc -n clusters get hostedCluster ${hyp_cluster_name} > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "Hypershift hostedCluster ${hyp_cluster_name} already exists"
  exit 1
fi

shift 2

while getopts "i:r:s:" option; do
   case $option in
      i) # instance type
        instanceType=$OPTARG;;
      r) # Replica count
        replicaCount="$OPTARG";;
      s) # Root volume size
        volSize="$OPTARG";;
   esac
done

echo "           cluster size: ${replicaCount}x ${instanceType}"
echo "  Root volume size (GB): ${volSize}"
echo "          OpenShift ver: ${ocpver}"

${hyCmd} create cluster aws --aws-creds ~/.aws/credentials --base-domain dev06.red-chesterfield.com --instance-type ${instanceType} --name ${hyp_cluster_name} --node-pool-replicas ${replicaCount} --pull-secret ./pull-secret --release-image quay.io/openshift-release-dev/ocp-release:${ocpver}-x86_64 --root-volume-size ${volSize}
if [ $? -ne 0 ]; then
  echo "hypershift create returned an error"
  exit 1
fi

rc=1
while [ ${rc} -ne 0 ]; do
  printf "\n-===============================================================================================-\n\n"
  oc -n clusters-${hyp_cluster_name} get pods
  
  oc -n clusters get hostedCluster ${hyp_cluster_name} | grep True > /dev/null 2>&1 
  rc=$?

  podCount=`oc -n clusters-${hyp_cluster_name} get pods | wc -l 2> /dev/null`
  if [ ${rc} -eq 0 ] && [ ${podCount} -gt 0 ]; then
    rc=`oc -n clusters-${hyp_cluster_name} get pods | grep "0\/" | grep -v Completed | wc -l`
  else
    rc=1
  fi
  sleep 5
done

# Generate the Kubeconfig for the existing clusters
${hyCmd} create kubeconfig > ${kubeconfig_tmp}
if [ $? -ne 0 ]; then
  echo "Error creating kubeconfig"
fi

#sed -i "s/current-context: .*$//g" ${kubeconfig_tmp}

echo "Backup ${kubeconfig} to ${kubeconfig}.bak"
cp ${kubeconfig} ${kubeconfig}.bak

echo "Creating context ${hyp_cluster_name} for hypershift cluster"
KUBECONFIG="${kubeconfig_tmp}:${kubeconfig}" oc config view --flatten > ${kubeconfig_tmp}.new
if [ $? -ne 0 ]; then
  echo "Error trying create context"
  exit 1
fi

mv ${kubeconfig_tmp}.new ${kubeconfig_context}

oc config delete-context ${hyp_cluster_name} > /dev/null 2>&1
oc config rename-context clusters-${hyp_cluster_name} ${hyp_cluster_name}
if [ $? -ne 0 ]; then
  echo "Error renaming context clusters-${hyp_cluster_name} to ${hyp_cluster_name}"
  exit 1
fi


#KUBECONFIG points to kubeconfig_context
origContext=$(KUBECONFIG=${kubeconfig} oc config current-context)
oc config use-context ${origContext} > /dev/null 2>&1
cp ${kubeconfig_context} ${kubeconfig}

rc=0
echo "Waiting for NodePool"
c=0
while [ ${rc} -eq 0 ]; do
  oc config use-context ${hyp_cluster_name} > /dev/null 2>&1
  c=$((c + 1))


  printf "\n${timer}\n-===============================================================================================-\n\n"
  if [ $((c % 12)) -eq 0 ]; then
    echo "$((c / 12))min"
  fi
  oc get nodes
  nodes=`oc get nodes | wc -l 2> /dev/null`
  if [ $nodes -gt 1 ]; then
    oc -n clusters get node | grep "NotReady" > /dev/null 2>&1
    rc=$?
  fi
  
  sleep 5
  
done

printf "\n"

