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

# Reference folders
export ADDON_CTRL_DIR="${PROJECT_DIR}/infra-controller-profiles/${PROFILE_NAME}"
export ADDON_CONFIG_DIR="${PROJECT_DIR}/infra-config-profiles/${PROFILE_NAME}"

# Add the CrossPlane controller
PACKAGE="${SW_CATALOGS_REPO_DIR}/infra-controllers/crossplane/controller"
cp "${PACKAGE}/templates"/* "${ADDON_CTRL_DIR}/"

# Add the CrossPlane providers
## Azure providers
PACKAGE="${SW_CATALOGS_REPO_DIR}/infra-controllers/crossplane/providers/azure"
cp "${PACKAGE}/templates"/* "${ADDON_CTRL_DIR}/"

## GCP providers
PACKAGE="${SW_CATALOGS_REPO_DIR}/infra-controllers/crossplane/providers/gcp"
cp "${PACKAGE}/templates"/* "${ADDON_CTRL_DIR}/"

## AWS providers
PACKAGE="${SW_CATALOGS_REPO_DIR}/infra-controllers/crossplane/providers/aws"
cp "${PACKAGE}/templates"/* "${ADDON_CTRL_DIR}/"

# Add the Argo WorkFlows controller
PACKAGE="${SW_CATALOGS_REPO_DIR}/infra-controllers/argo-workflows"
cp "${PACKAGE}/templates"/* "${ADDON_CTRL_DIR}/"

# Add the CAPI controller and providers
PACKAGE="${SW_CATALOGS_REPO_DIR}/infra-controllers/capi"
cp "${PACKAGE}/templates"/* "${ADDON_CTRL_DIR}/"
