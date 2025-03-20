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


# Source credentials
source "${CREDENTIALS_DIR}/gitea_environment.rc"
source "${CREDENTIALS_DIR}/gitea_tokens.rc"

# Add the local Git user to Gitea as a profile, upload the public SSH key (to allow SSH operations), and add the user as "collaborator" to both repos
"${HERE}/gitea/91-provision-local-git-user.sh"
