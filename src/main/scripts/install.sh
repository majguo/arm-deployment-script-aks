#!/bin/bash

# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

resourceGroupName=$1
aksClusterName=$2
acrName=$3
appPackageUrl=$4
appName=$5
appReplicas=$6

# Install utilities
apk update
apk add gettext
apk add docker-cli

# Install `kubectl` and connect to the AKS cluster
az aks install-cli
az aks get-credentials -g $resourceGroupName -n $aksClusterName --overwrite-existing

# Attach the ACR
az aks update -g $resourceGroupName -n $aksClusterName --attach-acr $acrName

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

# Log into the ACR
LOGIN_SERVER=$(az acr show -n $acrName --query loginServer | tr -d '"')
USER_NAME=$(az acr credential show -n $acrName --query username | tr -d '"')
PASSWORD=$(az acr credential show -n $acrName --query passwords[0].value | tr -d '"')
docker login $LOGIN_SERVER -u $USER_NAME -p $PASSWORD

# Prepare artifacts for building image
cp server.xml.template /tmp
cp Dockerfile.template /tmp
cp Dockerfile-wlp.template /tmp
cp openlibertyapplication.yaml.template /tmp
cd /tmp

export Application_Package=${appName}.war
wget -O ${Application_Package} "$appPackageUrl"

export Application_Name=$appName
envsubst < "server.xml.template" > "server.xml"
envsubst < "Dockerfile.template" > "Dockerfile"
envsubst < "Dockerfile-wlp.template" > "Dockerfile-wlp"

# Build image
# TODO: Use appropriate Dockerfile per user input
az acr build -t ${Application_Name}:1.0.0 -r $acrName .

# Deploy openliberty application
export Application_Image=${LOGIN_SERVER}/${Application_Name}:1.0.0
export Application_Replicas=$appReplicas
envsubst < openlibertyapplication.yaml.template | kubectl create -f -

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
