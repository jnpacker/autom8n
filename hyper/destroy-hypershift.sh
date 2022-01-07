#!/bin/bash

hosted_name=$1
hyCmd=hypershift

curContext=$(oc config current-context)
if [ "${curContext}" != "${HYP_MANAGEMENTCLUSTER}" ]; then
  echo ">> WARNING << * ${curContext} does not match Hypershift management cluster context ${HYP_MANAGEMENTCLUSTER}"
  echo "              * Press Ctrl-c to cancel, or press <ENTER> to switch to ${HYP_MANAGEMENTCLUSTER}"
  read
fi

if [ "${hosted_name}" == "" ]; then
  echo "You must include a hypershift cluster name"
  exit 1
fi

oc -n clusters get hostedCluster ${hosted_name}
if [ $? -ne 0 ]; then
  echo "Hosted cluster ${hosted_name} not found, current context ($(oc config current-context))"
  echo "List of hostedClusters:"
  oc -n clusters get hostedClusters
  exit 1
fi

${hyCmd} destroy cluster aws --aws-creds ~/.aws/credentials --base-domain dev06.red-chesterfield.com --name ${hosted_name}
if [ $? -ne 0 ]; then
  "Failed to destroy cluster correctly"
  exit 1
fi

oc config delete-context ${hosted_name}
oc config delete-user clusters-${hosted_name}-admin
oc config delete-cluster clusters-${hosted_name}
