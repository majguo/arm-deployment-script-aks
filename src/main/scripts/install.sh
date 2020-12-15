#!/bin/sh

# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

echo "resourceGroupName is: $1"
echo "aksClusterName is: $2"

resourceGroupName=$1
aksClusterName=$2

# Install `kubectl`
az aks install-cli

# Merge context info of the created AKS cluster for access
az aks get-credentials -g $resourceGroupName -n $aksClusterName --overwrite-existing

# Get cluster info
kubectl cluster-info

# Test for scripts output
result=$(az keyvault list)
echo $result | jq -c '{Result: map({id: .id})}' > $AZ_SCRIPTS_OUTPUT_PATH
