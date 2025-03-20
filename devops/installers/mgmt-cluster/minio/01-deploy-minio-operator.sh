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

m "\nDeploying Minio Operator..."

# Deploy Minio Operator
MINIO_VERSION="${MINIO_VERSION:-v5.0.11}"
TIMEOUT=120 # By default is 27. Since sometimes connection may be slow, here we allow more time
kustomize build "github.com/minio/operator/resources/?timeout=${TIMEOUT}&ref=${MINIO_VERSION}" | \
    # (optional) To allow deployments over single-node clusters
    yq 'del(.spec.template.spec.affinity)' | \
    # Deploy
    kubectl apply -f -

# Wait until completion
kubectl rollout status deploy/minio-operator --namespace=minio-operator --watch --timeout=1h
