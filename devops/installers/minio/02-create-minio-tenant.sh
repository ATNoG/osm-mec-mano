#!/bin/bash
#######################################################################################
# Copyright ETSI Contributors and Others.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#######################################################################################

set -e

export HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
source "${HERE}/library/functions.sh"
source "${HERE}/library/trap.sh"

############################################
# Main script starts here
############################################

# In case no arguments are passed, takes the value of the corresponding environment variables
MINIO_TENANT_NAME=${1:-${MINIO_TENANT_NAME}}
MINIO_TENANT_CAPACITY=${2:-${MINIO_TENANT_CAPACITY}}

# Adjusts tenant sizes
export MINIO_TENANT_SERVERS=${MINIO_TENANT_SERVERS:-4}
export MINIO_TENANT_VOLUMES=${MINIO_TENANT_VOLUMES:-8}


m "\nDeploying ${MINIO_TENANT_NAME} tenant..."

# Create Minio tenant
kubectl create ns ${MINIO_TENANT_NAME}
OPTIONS=""
# OPTIONS="--storage-class default"
kubectl minio tenant create                     \
    ${MINIO_TENANT_NAME}                        \
    --servers          ${MINIO_TENANT_SERVERS}  \
    --volumes          ${MINIO_TENANT_VOLUMES}  \
    --capacity         ${MINIO_TENANT_CAPACITY} \
    --namespace        ${MINIO_TENANT_NAME}     \
    ${OPTIONS}                                  \
    --output | \
    # Fix malformed manifest with wrong fields
    yq 'del(.spec.pools[0].volumeClaimTemplate.metadata.creationTimestamp)' | \
    kubectl apply -f -

# Wait until completion
echo "Waiting for tenant's statefulset to be ready..."
sleep 30    # To allow the statefulset object to exist
kubectl rollout status sts/minio-osm-tenant-ss-0 --namespace=${MINIO_TENANT_NAME} --watch --timeout=1h
