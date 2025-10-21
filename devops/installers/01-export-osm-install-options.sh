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

HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
source "${HERE}/../library/functions.sh"
source "${HERE}/../library/trap.sh"
source "${HERE}/../library/logging"
source "${HERE}/../library/track"

# Saves locally to local environment at OSM home dir folder
m "Saving local enviroment to OSM_HOME_DIR folder..."

OSM_HOME_DIR=${OSM_HOME_DIR:-"$HOME/.osm"}
mkdir -p "${OSM_HOME_DIR}"

cat << EOF > "${OSM_HOME_DIR}/user-install-options.rc"
export ASSUME_YES=${ASSUME_YES}
export APT_PROXY_URL=${APT_PROXY_URL}
export K8S_CLUSTER_ENGINE=${K8S_CLUSTER_ENGINE}
export DEBUG_INSTALL=${DEBUG_INSTALL}
export RELEASE=${RELEASE}
export REPOSITORY=${REPOSITORY}
export REPOSITORY_KEY=${REPOSITORY_KEY}
export REPOSITORY_BASE=${REPOSITORY_BASE}
export INSTALL_AUX_CLUSTER=${INSTALL_AUX_CLUSTER}
export INSTALL_MGMT_CLUSTER=${INSTALL_MGMT_CLUSTER}
export OSM_NAMESPACE=${OSM_NAMESPACE}
export OSM_HELM_RELEASE=${OSM_HELM_RELEASE}
export OSM_DOCKER_TAG=${OSM_DOCKER_TAG}
export DOCKER_USER=${DOCKER_USER}
export DOCKER_REGISTRY_USER=${DOCKER_REGISTRY_USER}
export DOCKER_REGISTRY_PASSWORD=${DOCKER_REGISTRY_PASSWORD}
export DOCKER_REGISTRY_URL=${DOCKER_REGISTRY_URL}
export DOCKER_PROXY_URL=${DOCKER_PROXY_URL}
export MODULE_DOCKER_TAG=${MODULE_DOCKER_TAG}
export OSM_CLIENT_VERSION=${OSM_CLIENT_VERSION}
export OSM_IM_VERSION=${OSM_IM_VERSION}
export OSM_HOME_DIR=${OSM_HOME_DIR}
export CREDENTIALS_DIR="${OSM_HOME_DIR}/.credentials"
export WORK_REPOS_DIR="${OSM_HOME_DIR}/repos"
export INSTALL_MINIO=${INSTALL_MINIO}
export KUBECONFIG_AUX_CLUSTER=${KUBECONFIG_AUX_CLUSTER}
export KUBECONFIG_MGMT_CLUSTER=${KUBECONFIG_MGMT_CLUSTER}
export KUBECONFIG_OSM_CLUSTER=${KUBECONFIG_OSM_CLUSTER}
export OSM_BEHIND_PROXY=${OSM_BEHIND_PROXY}
export OPENSHIFT_MGMT_CLUSTER=${OPENSHIFT_MGMT_CLUSTER}
export MGMT_CLUSTER_CA_FILE=${MGMT_CLUSTER_CA_FILE}
export OSM_BASE_DOMAIN=${OSM_BASE_DOMAIN}
export OSM_HELM_TIMEOUT=${OSM_HELM_TIMEOUT}
export OSM_CLUSTER_INGRESS_CLASS=${OSM_CLUSTER_INGRESS_CLASS}
export AUX_CLUSTER_INGRESS_CLASS=${AUX_CLUSTER_INGRESS_CLASS}
EOF

cat "${OSM_HOME_DIR}/user-install-options.rc"

m "Done."
echo
