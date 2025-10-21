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


# Creates base dir in case it did not exist
export WORK_REPOS_DIR="${OSM_HOME_DIR}/repos"
mkdir -p "${WORK_REPOS_DIR}"

# Clones `fleet-osm` repo
[[ "${REMOVE_LOCAL_DIR_BEFORE_CLONING}" == "true" ]] && rm -rf "${FLEET_REPO_DIR}"
git clone "${FLEET_REPO_SSH_URL}" "${FLEET_REPO_DIR}"

# Clones `sw-catalogs-osm` repo
[[ "${REMOVE_LOCAL_DIR_BEFORE_CLONING}" == "true" ]] && rm -rf "${SW_CATALOGS_REPO_DIR}"
git clone "${SW_CATALOGS_REPO_SSH_URL}" "${SW_CATALOGS_REPO_DIR}"

# Forces `main` instead of `master` as default branch
pushd "${FLEET_REPO_DIR}" > /dev/null
git symbolic-ref HEAD refs/heads/main
popd > /dev/null
pushd "${SW_CATALOGS_REPO_DIR}" > /dev/null
git symbolic-ref HEAD refs/heads/main
popd > /dev/null
