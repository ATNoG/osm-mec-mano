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

# Prints URLs for HTTP access
m "HTTP URL: ${GITEA_HTTP_URL}"
m "SSH URL: ${GITEA_SSH_URL}"
m "HTTP Host Domain: ${GITEA_HTTP_HOST_DOMAIN}"
m "Internal HTTP URL: ${GITEA_INTERNAL_HTTP_URL}"
m "Internal SSH URL: ${GITEA_INTERNAL_SSH_URL}"
echo

# Saves locally to local environment at credentials folder
m "Saving local enviroment to credentials folder..."
export CREDENTIALS_DIR="${OSM_HOME_DIR}/.credentials"
mkdir -p "${CREDENTIALS_DIR}"
cat << EOF > "${CREDENTIALS_DIR}/gitea_environment.rc"
export GITEA_HTTP_URL=${GITEA_HTTP_URL}
export GITEA_SSH_URL=${GITEA_SSH_URL}
export GITEA_SSH_SERVER=${GITEA_SSH_SERVER}
export GITEA_HTTP_HOST_DOMAIN=${GITEA_HTTP_HOST_DOMAIN}
export GITEA_INTERNAL_HTTP_URL=${GITEA_INTERNAL_HTTP_URL}
export GITEA_INTERNAL_SSH_URL=${GITEA_INTERNAL_SSH_URL}
export GITEA_INTERNAL_SSH_SERVER=${GITEA_INTERNAL_SSH_SERVER}
export GITEA_INTERNAL_HTTP_IP=${GITEA_INTERNAL_HTTP_IP}
export GITEA_INTERNAL_SSH_IP=${GITEA_INTERNAL_SSH_IP}
export GITEA_HTTP_PORT=${GITEA_HTTP_PORT}
export GITEA_SSH_PORT=${GITEA_SSH_PORT}
export GITEA_ADMINISTRATOR_USERNAME=${GITEA_ADMINISTRATOR_USERNAME}
export GITEA_ADMINISTRATOR_PASSWORD='${GITEA_ADMINISTRATOR_PASSWORD}'
export GITEA_STD_USERNAME=${GITEA_STD_USERNAME}
export GITEA_STD_USER_PASS='${GITEA_STD_USER_PASS}'
EOF

cat << EOF > "${CREDENTIALS_DIR}/git_environment.rc"
export GIT_BASE_HTTP_URL="${GITEA_HTTP_URL}"
export GIT_BASE_USERNAME="${GITEA_STD_USERNAME}"
export FLEET_REPO_HTTP_URL="${GITEA_HTTP_URL}/${GITEA_STD_USERNAME}/fleet-osm.git"
export FLEET_REPO_SSH_URL="${GITEA_SSH_URL}/${GITEA_STD_USERNAME}/fleet-osm.git"
export FLEET_REPO_GIT_USERNAME="${GITEA_STD_USERNAME}"
export FLEET_REPO_GIT_USER_PASS='${GITEA_STD_USER_PASS}'
export SW_CATALOGS_REPO_HTTP_URL="${GITEA_HTTP_URL}/${GITEA_STD_USERNAME}/sw-catalogs-osm.git"
export SW_CATALOGS_REPO_SSH_URL="${GITEA_SSH_URL}/${GITEA_STD_USERNAME}/sw-catalogs-osm.git"
export SW_CATALOGS_REPO_GIT_USERNAME="${GITEA_STD_USERNAME}"
export SW_CATALOGS_REPO_GIT_USER_PASS='${GITEA_STD_USER_PASS}'
EOF

m "Done."
echo

# Saves into K8s cluster as a secret
m "Saving enviroment to secret into K8s cluster..."

kubectl delete secret gitea-environment -n gitea 2> /dev/null || true
kubectl create secret generic gitea-environment -n gitea \
    --from-literal=GITEA_HTTP_URL=${GITEA_HTTP_URL} \
    --from-literal=GITEA_SSH_URL=${GITEA_SSH_URL} \
    --from-literal=GITEA_HTTP_HOST_DOMAIN=${GITEA_HTTP_HOST_DOMAIN} \
    --from-literal=GITEA_INTERNAL_HTTP_URL=${GITEA_INTERNAL_HTTP_URL} \
    --from-literal=GITEA_INTERNAL_SSH_URL=${GITEA_INTERNAL_SSH_URL} \
    --from-literal=GITEA_INTERNAL_SSH_SERVER=${GITEA_INTERNAL_SSH_SERVER} \
    --from-literal=GITEA_INTERNAL_HTTP_IP=${GITEA_INTERNAL_HTTP_IP} \
    --from-literal=GITEA_INTERNAL_SSH_IP=${GITEA_INTERNAL_SSH_IP} \
    --from-literal=GITEA_HTTP_PORT=${GITEA_HTTP_PORT} \
    --from-literal=GITEA_SSH_PORT=${GITEA_SSH_PORT} \
    --from-literal=GITEA_ADMINISTRATOR_USERNAME=${GITEA_ADMINISTRATOR_USERNAME} \
    --from-literal=GITEA_ADMINISTRATOR_PASSWORD=${GITEA_ADMINISTRATOR_PASSWORD} \
    --from-literal=GITEA_STD_USERNAME=${GITEA_STD_USERNAME} \
    --from-literal=GITEA_STD_USER_PASS=${GITEA_STD_USER_PASS}

m "Done."
echo
m "Example: To retrieve Gitea's HTTP URL:"
m "kubectl get secret gitea-environment -n gitea -o jsonpath='{.data.GITEA_HTTP_URL}' | base64 -d" ${CYAN}
echo
