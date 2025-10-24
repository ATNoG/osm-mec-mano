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

set -ex

export HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
source "${HERE}/library/functions.sh"
source "${HERE}/library/trap.sh"

if [[ -z "${GITEA_ENV_NAME}" ]]; then
    m "No target environment was loaded. Please source one of the .rc environment files first. $DURATION" "$RED"
    exit 1
fi

# Deploy Helm chart with required values
helm repo add gitea-charts https://dl.gitea.io/charts/
m "Deploying Gitea's Helm chart..."
helm install gitea gitea-charts/gitea \
    --version=7.0.4 \
    --namespace=gitea \
    --values "${HERE}/${GITEA_CHART_VALUES_FILE}" \
    --set=gitea.admin.username="${GITEA_ADMINISTRATOR_USERNAME}" \
    --set=gitea.admin.password="${GITEA_ADMINISTRATOR_PASSWORD@Q}" \
    --create-namespace \
    --wait

m "Waiting for Gitea to start..."
# See: https://github.com/kubernetes/kubernetes/issues/79606
kubectl rollout status statefulset/gitea --namespace=gitea --watch --timeout=1h
