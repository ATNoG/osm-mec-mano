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



# Input values
export CLUSTER_DIR="$1"
export PROJECT_DIR="$2"
export PROFILE_NAME="$3"
export TEMPLATES_DIR="$4"
export PUBLIC_KEY="$5"


# Helper functions to create the profile ConfigMaps
function safe_name() {
  echo "$1" | \
    sed '/\.\// s|./||' | \
    sed 's|\.|-|g' | \
    sed 's|/|-|g' | \
    sed 's|_|-|g' | \
    sed 's| |-|g'
}

function create_profile_configmap() {
  local CONFIGMAP_NAME=$(safe_name "$1")
  local PROFILE_REPO_URL="$2"
  local PROFILE_PATH="$3"
  kubectl create configmap ${CONFIGMAP_NAME} \
    --namespace flux-system \
    --from-literal=repo="${PROFILE_REPO_URL}" \
    --from-literal=path="${PROFILE_PATH}" \
    -o yaml \
    --dry-run=client
}

# Helper functions to clone secret from one namespace to other
function clone_secret_to_new_ns_stdout() {
  local SECRET_NAME="$1"
  local SOURCE_NS="$2"
  local DESTINATION_NS="$3"

  kubectl get secret "${SECRET_NAME}" -n "${SOURCE_NS}" -o yaml | \
  yq 'del(.metadata.uid) | del(.metadata.resourceVersion) | del(.metadata.creationTimestamp)' | \
  yq ".metadata.namespace = \"${DESTINATION_NS}\""
}

# Helper function to encrypt secrets from stdin
function encrypt_secret_from_stdin() {
  local PUBLIC_KEY="$1"

  # Save secret manifest to temporary file
  local TMPFILE=$(mktemp /tmp/secret.XXXXXXXXXX.yaml) || exit 1
  cat > "${TMPFILE}"

  # Encrypt
  sops \
    --age=${PUBLIC_KEY} \
    --encrypt \
    --encrypted-regex '^(data|stringData)$' \
    --in-place "${TMPFILE}"

  # Outputs the result and removes the temporary file
  cat "${TMPFILE}" && rm -f "${TMPFILE}"
}

# Creates all folders in the profile (as well as env var aliases)
export ADDON_CTRL_DIR="${PROJECT_DIR}/infra-controller-profiles/${PROFILE_NAME}"
export ADDON_CONFIG_DIR="${PROJECT_DIR}/infra-config-profiles/${PROFILE_NAME}"
export RESOURCES_DIR="${PROJECT_DIR}/managed-resources/${PROFILE_NAME}"
export APPS_DIR="${PROJECT_DIR}/app-profiles/${PROFILE_NAME}"
mkdir -p "${ADDON_CTRL_DIR}"
mkdir -p "${ADDON_CONFIG_DIR}"
mkdir -p "${RESOURCES_DIR}"
mkdir -p "${APPS_DIR}"

# Copies the templates for cluster setup
cp "${TEMPLATES_DIR}"/* "${CLUSTER_DIR}/"

# Repo URLs
export FLEET_REPO_URL="${FLEET_REPO_HTTP_URL}"
export SW_CATALOGS_REPO_URL="${SW_CATALOGS_REPO_HTTP_URL}"
export INFRA_CONTROLLERS_PATH="./${MGMT_PROJECT_NAME}/infra-controller-profiles/_management"
export INFRA_CONFIGS_PATH="./${MGMT_PROJECT_NAME}/infra-config-profiles/_management"
export MANAGED_RESOURCES_PATH="./${MGMT_PROJECT_NAME}/managed-resources/_management"
export APPS_PATH="./${MGMT_PROJECT_NAME}/app-profiles/_management"

# Render Flux `GitRepository` objects with proper Git URL and relative repo paths
envsubst < "${TEMPLATES_DIR}/fleet-repo.yaml" > "${CLUSTER_DIR}/fleet-repo.yaml"
envsubst < "${TEMPLATES_DIR}/sw-catalogs-repo.yaml" > "${CLUSTER_DIR}/sw-catalogs-repo.yaml"

# Secrets to access both Git repos
# (NOTE: these are the last secrets to be added imperatively)
kubectl delete secret fleet-repo --namespace flux-system 2> /dev/null || true
if [ -n "${MGMT_CLUSTER_CA_FILE}" ]; then
    kubectl create secret generic fleet-repo \
        --namespace flux-system \
        --from-literal=username="${FLEET_REPO_GIT_USERNAME}" \
        --from-literal=password="${FLEET_REPO_GIT_USER_PASS}" \
        --from-file=ca.crt="${MGMT_CLUSTER_CA_FILE}"
else
    kubectl create secret generic fleet-repo \
        --namespace flux-system \
        --from-literal=username="${FLEET_REPO_GIT_USERNAME}" \
        --from-literal=password="${FLEET_REPO_GIT_USER_PASS}"
fi
kubectl delete secret sw-catalogs --namespace flux-system 2> /dev/null || true
if [ -n "${MGMT_CLUSTER_CA_FILE}" ]; then
    kubectl create secret generic sw-catalogs \
        --namespace flux-system \
        --from-literal=username="${SW_CATALOGS_REPO_GIT_USERNAME}" \
        --from-literal=password="${SW_CATALOGS_REPO_GIT_USER_PASS}" \
        --from-file=ca.crt="${MGMT_CLUSTER_CA_FILE}"
else
    kubectl create secret generic sw-catalogs \
        --namespace flux-system \
        --from-literal=username="${SW_CATALOGS_REPO_GIT_USERNAME}" \
        --from-literal=password="${SW_CATALOGS_REPO_GIT_USER_PASS}"
fi
# Render Flux `Kustomizations` to sync with default profiles
envsubst < "${TEMPLATES_DIR}/infra-controllers.yaml" > "${CLUSTER_DIR}/infra-controllers.yaml"
envsubst < "${TEMPLATES_DIR}/infra-configs.yaml" > "${CLUSTER_DIR}/infra-configs.yaml"
envsubst < "${TEMPLATES_DIR}/managed-resources.yaml" > "${CLUSTER_DIR}/managed-resources.yaml"
envsubst < "${TEMPLATES_DIR}/apps.yaml" > "${CLUSTER_DIR}/apps.yaml"

# Create `ConfigMaps` into profiles (and `Namespace` specs when needed) to avoid sync errors
## Infra controllers ConfigMap
CONFIGMAP_NAME="infra-controllers"
PROFILE_REPO_URL="${FLEET_REPO_URL}"
PROFILE_PATH="${INFRA_CONTROLLERS_PATH}"
create_profile_configmap \
  "${CONFIGMAP_NAME}" \
  "${PROFILE_REPO_URL}" \
  "${PROFILE_PATH}" \
  > "${ADDON_CTRL_DIR}/profile-configmap.yaml"

## Infra configurations ConfigMap
CONFIGMAP_NAME="infra-configs"
PROFILE_REPO_URL="${FLEET_REPO_URL}"
PROFILE_PATH="${INFRA_CONFIGS_PATH}"
create_profile_configmap \
  "${CONFIGMAP_NAME}" \
  "${PROFILE_REPO_URL}" \
  "${PROFILE_PATH}" \
  > "${ADDON_CONFIG_DIR}/profile-configmap.yaml"

## Managed resources ConfigMap
CONFIGMAP_NAME="managed-resources"
PROFILE_REPO_URL="${FLEET_REPO_URL}"
PROFILE_PATH="${MANAGED_RESOURCES_PATH}"
create_profile_configmap \
  "${CONFIGMAP_NAME}" \
  "${PROFILE_REPO_URL}" \
  "${PROFILE_PATH}" \
  > "${RESOURCES_DIR}/profile-configmap.yaml"

## Managed resources namespace
kubectl create ns ${CONFIGMAP_NAME} \
    -o yaml \
    --dry-run=client \
    > "${RESOURCES_DIR}/namespace.yaml"

### Copy secrets for Git repos from `flux-system` to `managed-resources` namespace
clone_secret_to_new_ns_stdout \
  flux-system \
  flux-system \
  "${CONFIGMAP_NAME}" | \
encrypt_secret_from_stdin \
  "${PUBLIC_KEY}" \
> "${RESOURCES_DIR}/secret-flux-system.yaml"

clone_secret_to_new_ns_stdout \
  fleet-repo \
  flux-system \
  "${CONFIGMAP_NAME}" | \
encrypt_secret_from_stdin \
  "${PUBLIC_KEY}" \
> "${RESOURCES_DIR}/secret-fleet-repo.yaml"

clone_secret_to_new_ns_stdout \
  sw-catalogs \
  flux-system \
  "${CONFIGMAP_NAME}" | \
encrypt_secret_from_stdin \
  "${PUBLIC_KEY}" \
> "${RESOURCES_DIR}/secret-sw-catalogs.yaml"

## Apps ConfigMap
CONFIGMAP_NAME="apps"
PROFILE_REPO_URL="${FLEET_REPO_URL}"
PROFILE_PATH="${APPS_PATH}"
create_profile_configmap \
  "${CONFIGMAP_NAME}" \
  "${PROFILE_REPO_URL}" \
  "${PROFILE_PATH}" \
  > "${APPS_DIR}/profile-configmap.yaml"
