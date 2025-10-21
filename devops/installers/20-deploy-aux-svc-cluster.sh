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

# Warning!!!: Remember to select the desired kubeconfig profile before launching this script

HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
source "${HERE}/../library/functions.sh"
source "${HERE}/../library/trap.sh"

pushd $HERE > /dev/null

source "${HERE}/00-default-install-options.rc"
[ ! -f "${OSM_HOME_DIR}/user-install-options.rc" ] || source "${OSM_HOME_DIR}/user-install-options.rc"
echo "Loading env variables from 20-base-config.rc"
source "${HERE}/20-base-config.rc"

# TODO: move this to a parent script that creates the VM
mkdir -p "${OSM_HOME_DIR}/clusters"
if [ -n "${KUBECONFIG_AUX_CLUSTER}" ]; then
  cp "${KUBECONFIG_AUX_CLUSTER}" "${OSM_HOME_DIR}/clusters/kubeconfig-aux-svc.yaml"
else
  cp "${HOME}/.kube/config" "${OSM_HOME_DIR}/clusters/kubeconfig-aux-svc.yaml"
fi

export KUBECONFIG="${OSM_HOME_DIR}/clusters/kubeconfig-aux-svc.yaml"

############################ NGINX Ingress controller
m "\n#####################################################################" "${CYAN}"
m "(1/3) Installing NGINX Ingress controller..." "${CYAN}"
m "#####################################################################\n" "${CYAN}"

# Install NGINX Ingress controller (NOTE: this command is idempotent)
## Uncomment for AKS:
NGINX_VERSION="4.10.0"
ANNOTATIONS='--set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz'
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx --version ${NGINX_VERSION} \
  --namespace ingress-nginx --create-namespace ${ANNOTATIONS}

# Wait until ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

#####################################################################


############################ Gitea
m "\n#####################################################################" "${CYAN}"
m "(2/3) Installing Gitea..." "${CYAN}"
m "#####################################################################\n" "${CYAN}"

# Enter the Gitea folder
# TODO: Should we use pushd $HERE/gitea instead of pushd gitea?
pushd "${HERE}/gitea" > /dev/null

# Install Gitea and expose web with Ingress
export GITEA_CHART_VALUES_FILE=${GITEA_CHART_VALUES_FILE:-values-standalone-ingress.yaml}
./ALL-IN-ONE-Gitea-install.sh

# Setup Git user and SSH keys
m "\nSetting up Git user and SSH keys..."
./20-setup-gituser-and-sshkeygen.sh

# Provision for OSM
m "\nProvisioning Gitea for OSM use..."
source "${CREDENTIALS_DIR}/gitea_environment.rc"
./90-provision-gitea-for-osm.sh

# Return to base folder
popd > /dev/null

#####################################################################


############################ Minio
m "\n#####################################################################" "${CYAN}"
m "(3/3) Installing Minio..." "${CYAN}"
m "#####################################################################\n" "${CYAN}"

echo "INSTALL_MINIO=$INSTALL_MINIO"
if [ -n "${INSTALL_MINIO}" ]; then
    # Enter the Minio folder
    pushd minio > /dev/null
    # Install Minio and expose Console and tenant endpoint with Ingress
    ./ALL-IN-ONE-Minio-install.sh
    # Return to base folder
    popd > /dev/null
fi
#####################################################################


# Source tokens
source "${CREDENTIALS_DIR}/gitea_tokens.rc"

# Add the local Git user to Gitea as a profile, upload the public SSH key (to allow SSH operations), and add the user as "collaborator" to both repos
"${HERE}/gitea/91-provision-local-git-user.sh"

popd > /dev/null
