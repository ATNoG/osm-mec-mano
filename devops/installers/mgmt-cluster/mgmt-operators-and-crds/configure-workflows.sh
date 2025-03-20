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
export PROJECT_DIR="$1"
export PROFILE_NAME="$2"
export PUBLIC_KEY="$3"


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


# Reference folder for addon configs
export ADDON_CONFIG_DIR="${PROJECT_DIR}/infra-config-profiles/${PROFILE_NAME}"

# KSU folder for workflows
export RESOURCES_DIR="${ADDON_CONFIG_DIR}/osm-workflows"
mkdir -p "${RESOURCES_DIR}"

# Create namespace for OSM workflows
WORKFLOWS_NS=osm-workflows
kubectl create ns ${WORKFLOWS_NS} \
    -o yaml \
    --dry-run=client \
    > "${RESOURCES_DIR}/namespace.yaml"

# Copy secrets for Git repos from `flux-system` to `osm-workflows` namespace
clone_secret_to_new_ns_stdout \
  fleet-repo \
  flux-system \
  "${WORKFLOWS_NS}" | \
encrypt_secret_from_stdin \
  "${PUBLIC_KEY}" \
> "${RESOURCES_DIR}/secret-fleet-repo.yaml"

clone_secret_to_new_ns_stdout \
  sw-catalogs \
  flux-system \
  "${WORKFLOWS_NS}" | \
encrypt_secret_from_stdin \
  "${PUBLIC_KEY}" \
> "${RESOURCES_DIR}/secret-sw-catalogs.yaml"

# Add appropriate configurations and workflow templates for Argo WorkFlows into the namespace
PACKAGE="${SW_CATALOGS_REPO_DIR}/infra-configs/osm-workflows"
cp -r "${PACKAGE}/templates"/* "${RESOURCES_DIR}/"
