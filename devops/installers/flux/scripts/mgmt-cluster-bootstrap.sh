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

set -e -o pipefail

export HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
source "${HERE}/library/functions.sh"
source "${HERE}/library/trap.sh"


# Preparation for Openshift
if [ -n "${OPENSHIFT_MGMT_CLUSTER}" ]; then
  m "Detected OpenShift management cluster, initilializing flux with SCC..." "${GREEN}"
  # Preparation for Openshift
  pushd "${FLEET_REPO_DIR}" > /dev/null
  FLUX_SYSTEM_DIR="clusters/_management/flux-system"
  FLUX_SYSTEM_SW_CATALOG_DIR="${HERE}/../templates/sw-catalogs/cloud-resources/flux-remote-bootstrap/cluster-base-openshift/templates/flux-system"
  mkdir -p "${FLUX_SYSTEM_DIR}"
  touch "${FLUX_SYSTEM_DIR}/gotk-components.yaml"
  touch "${FLUX_SYSTEM_DIR}/gotk-sync.yaml"
  cp "${FLUX_SYSTEM_SW_CATALOG_DIR}/scc.yaml" "${FLUX_SYSTEM_DIR}"
  cp "${FLUX_SYSTEM_SW_CATALOG_DIR}/kustomization.yaml" "${FLUX_SYSTEM_DIR}"
  # git status
  git add -A
  git commit -m "init flux"
  git pull origin main
  git push -u origin main
  popd > /dev/null
fi

# Bootstrap
GIT_PATH=./clusters/_management
GIT_BRANCH=main
if [ -n "${MGMT_CLUSTER_CA_FILE}" ]; then
    flux bootstrap git \
        --url=${FLEET_REPO_HTTP_URL} \
        --allow-insecure-http=true \
        --username=${FLEET_REPO_GIT_USERNAME} \
        --password="${FLEET_REPO_GIT_USER_PASS}" \
        --token-auth=true \
        --branch=${GIT_BRANCH} \
        --ca-file=${MGMT_CLUSTER_CA_FILE} \
        --path=${GIT_PATH}
else
    flux bootstrap git \
        --url=${FLEET_REPO_HTTP_URL} \
        --allow-insecure-http=true \
        --username=${FLEET_REPO_GIT_USERNAME} \
        --password="${FLEET_REPO_GIT_USER_PASS}" \
        --token-auth=true \
        --branch=${GIT_BRANCH} \
        --path=${GIT_PATH}
fi

# Check if successful
flux check
