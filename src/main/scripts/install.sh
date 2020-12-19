#!/bin/bash

# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

resourceGroupName=$1
aksClusterName=$2
appImage=$3
appName=$4

# Install utilities
apk update
apk add gettext

# Install `kubectl` and connect to the AKS cluster
az aks install-cli
az aks get-credentials -g $resourceGroupName -n $aksClusterName --overwrite-existing

# Install Open Liberty Operator V0.7
OPERATOR_NAMESPACE=default
WATCH_NAMESPACE='""'
kubectl apply -f https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/master/deploy/releases/0.7.0/openliberty-app-crd.yaml
curl -L https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/master/deploy/releases/0.7.0/openliberty-app-cluster-rbac.yaml \
      | sed -e "s/OPEN_LIBERTY_OPERATOR_NAMESPACE/${OPERATOR_NAMESPACE}/" \
      | kubectl apply -f -
curl -L https://raw.githubusercontent.com/OpenLiberty/open-liberty-operator/master/deploy/releases/0.7.0/openliberty-app-operator.yaml \
      | sed -e "s/OPEN_LIBERTY_WATCH_NAMESPACE/${WATCH_NAMESPACE}/" \
      | kubectl apply -n ${OPERATOR_NAMESPACE} -f -

# Deploy openliberty application
export Application_Image=$appImage
export Application_Name=$appName
envsubst < openlibertyapplication.yaml | kubectl create -f -

# Wait until the deployment completes
kubectl get deployment ${Application_Name}
while [ $? -ne 0 ]
do
      sleep 5
      kubectl get deployment ${Application_Name}
done
replicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.spec.replicas}')
readyReplicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.status.readyReplicas}')
availableReplicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.status.availableReplicas}')
updatedReplicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.status.updatedReplicas}')
while [[ $replicas != $readyReplicas || $readyReplicas != $availableReplicas || $availableReplicas != $updatedReplicas ]]
do
      sleep 5
      echo retry
      replicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.spec.replicas}')
      readyReplicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.status.readyReplicas}')
      availableReplicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.status.availableReplicas}')
      updatedReplicas=$(kubectl get deployment ${Application_Name} -o=jsonpath='{.status.updatedReplicas}')
done
kubectl get svc ${Application_Name}
while [ $? -ne 0 ]
do
      sleep 5
      kubectl get svc ${Application_Name}
done
Application_Endpoint=$(kubectl get svc ${Application_Name} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}:{.spec.ports[0].port}')
while [[ $Application_Endpoint = :* ]]
do
      sleep 5
      echo retry
      Application_Endpoint=$(kubectl get svc ${Application_Name} -o=jsonpath='{.status.loadBalancer.ingress[0].ip}:{.spec.ports[0].port}')
done

# Output application endpoint
echo "endpoint is: $Application_Endpoint"
result=$(jq -n -c --arg endpoint $Application_Endpoint '{applicationEndpoint: $endpoint}')
echo "result is: $result"
echo $result > $AZ_SCRIPTS_OUTPUT_PATH
