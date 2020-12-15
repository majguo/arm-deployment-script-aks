#!/bin/sh

# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

echo "arg1 is: $1"
echo "arg2 is: $2"

result=$(az keyvault list)
echo $result | jq -c '{Result: map({id: .id})}' > $AZ_SCRIPTS_OUTPUT_PATH
