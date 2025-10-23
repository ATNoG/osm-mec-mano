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

export HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
source "${HERE}/library/functions.sh"
source "${HERE}/library/trap.sh"


############################ Clone repos
m "\n#####################################################################" "${CYAN}"
m "(1/8) Cloning relevant repos..." "${CYAN}"
m "#####################################################################\n" "${CYAN}"

# Load Gitea credentials
source "${CREDENTIALS_DIR}/gitea_environment.rc"
source "${CREDENTIALS_DIR}/gitea_tokens.rc"

# clone the relevant repos to well-known local folders
"${HERE}/flux/scripts/clone-relevant-repos.sh"

#####################################################################


############################ Flux bootstrap
m "\n#####################################################################" "${CYAN}"
m "(2/8) Running Flux bootstrap on the management cluster..." "${CYAN}"
m "#####################################################################\n" "${CYAN}"

# Bootstrap
"${HERE}/flux/scripts/mgmt-cluster-bootstrap.sh"

# Pull the latest changes from the `fleet` repo
git -C "${FLEET_REPO_DIR}" pull origin main

#####################################################################


############################ SOPS setup for the management cluster
m "\n#####################################################################" "${CYAN}"
m "(3/8) Setting up SOPS in the management cluster..." "${CYAN}"
m "#####################################################################\n" "${CYAN}"

# Create a new `age` key pair for the management cluster
"${HERE}/flux/scripts/create-age-keypair.sh" "${AGE_KEY_NAME_MGMT}"

# Add the `age` key pair to the cluster
"${HERE}/flux/scripts/add-age-key-to-cluster.sh" \
  "${AGE_KEY_NAME_MGMT}" \
  "${FLEET_REPO_DIR}/clusters/_management"

#####################################################################


############################ Base kustomizations and default cluster profiles
m "\n#####################################################################" "${CYAN}"
m "(4/8) Creating base kustomizations and default cluster profiles..." "${CYAN}"
m "#####################################################################\n" "${CYAN}"

TEMPLATES_DIR="flux/templates/fleet/clusters/_management"
TEMPLATES_DIR=$(readlink -f "${TEMPLATES_DIR}")

# ARGUMENTS:
# 1: Cluster folder
# 2: Project folder
# 3: Profile name
# 4: Templates folder
"${HERE}/flux/scripts/create-new-cluster-folder-structure.sh" \
  "${FLEET_REPO_DIR}/clusters/_management" \
  "${FLEET_REPO_DIR}/${MGMT_PROJECT_NAME}" \
  "_management" \
  "${TEMPLATES_DIR}" \
  $(<"${CREDENTIALS_DIR}/${AGE_KEY_NAME_MGMT}.pub")


#####################################################################


############################ Populate the SW-Catalogs repo folder
m "\n#####################################################################" "${CYAN}"
m "(5/8) Populating the SW-Catalogs repo folder..." "${CYAN}"
m "#####################################################################\n" "${CYAN}"

TEMPLATES_DIR="flux/templates/sw-catalogs"
TEMPLATES_DIR=$(readlink -f "${TEMPLATES_DIR}")
# rsync -varhP "${TEMPLATES_DIR}" "${SW_CATALOGS_REPO_DIR}/"
cp -r "${TEMPLATES_DIR}"/* "${SW_CATALOGS_REPO_DIR}/"

#####################################################################


############################ Add all the required operators and CRDs
m "\n#####################################################################" "${CYAN}"
m "(6/8) Add all the required operators and CRDs..." "${CYAN}"
m "#####################################################################\n" "${CYAN}"

# ARGUMENTS:
# 1: Project folder
# 2: Profile name
"${HERE}/mgmt-operators-and-crds/add-operators-and-crds.sh" \
  "${FLEET_REPO_DIR}/${MGMT_PROJECT_NAME}" \
  "_management"

#####################################################################


############################ Configure for running OSM workflows
m "\n#####################################################################" "${CYAN}"
m "(7/8) Configure for running OSM workflows..." "${CYAN}"
m "#####################################################################\n" "${CYAN}"

# ARGUMENTS:
# 1: Project folder
# 2: Profile name

"${HERE}/mgmt-operators-and-crds/configure-workflows.sh" \
  "${FLEET_REPO_DIR}/${MGMT_PROJECT_NAME}" \
  "_management" \
  $(<"${CREDENTIALS_DIR}/${AGE_KEY_NAME_MGMT}.pub")


#####################################################################


############################ Push changes to Git repos
m "\n#####################################################################" "${CYAN}"
m "(8/8) Pushing all changes to Git repos..." "${CYAN}"
m "#####################################################################\n" "${CYAN}"

# SW Catalogs
pushd "${SW_CATALOGS_REPO_DIR}" > /dev/null
# git status
git add -A
git commit -m "Sync from sw-catalogs template"
git push -u origin main
popd > /dev/null

# Fleet
pushd "${FLEET_REPO_DIR}" > /dev/null
# git status
git add -A
git commit -m "Full profile structure after bootstrap + SOPS config + operators and CRDs"
git push -u origin main
popd > /dev/null

#####################################################################
