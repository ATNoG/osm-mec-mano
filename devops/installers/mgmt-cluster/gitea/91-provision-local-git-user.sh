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


# Create new user
export USER_NAME=$(git config --get user.name)
export USER_MAIL=$(git config --get user.email)
export USER_PASS="${GITEA_STD_USER_PASS}" # Same as standard user
"${HERE}/admin/create-user.sh" \
  "${USER_NAME}" \
  "${USER_PASS}" \
  "${USER_MAIL}"

# Create token
export USER_TOKEN_NAME=user_token_name
export USER_TOKEN=$( \
    "${HERE}/admin/create-cmd-access-token.sh" \
        "${USER_NAME}" \
        "${USER_TOKEN_NAME}" | \
    grep 'Access token was successfully created' | \
    cut -d ' ' -f 6 \
)

# Add user's public SSH key
"${HERE}/admin/create-user-ssh-key.sh" \
  "${GITEA_HTTP_URL}" \
  "${USER_NAME}" \
  "${USER_TOKEN}" \
  "$(<${HOME}/.ssh/id_rsa.pub)" \
  "local_user_ssh_key" \
  false

# Add user as collaborator of the relevant repos
## Fleet repo
"${HERE}/admin/add-collaborator-to-user-repo.sh" \
  "${GITEA_HTTP_URL}" \
  "${GITEA_STD_USERNAME}" \
  "${GITEA_STD_TOKEN}" \
  "fleet-osm" \
  "${USER_NAME}" \
  "write"

## SW-Catalogs repo
"${HERE}/admin/add-collaborator-to-user-repo.sh" \
  "${GITEA_HTTP_URL}" \
  "${GITEA_STD_USERNAME}" \
  "${GITEA_STD_TOKEN}" \
  "sw-catalogs-osm" \
  "${USER_NAME}" \
  "write"

# Prevents non-interactive recognition of the SSH host
ssh-keyscan -p "${GITEA_SSH_PORT}" "${GITEA_SSH_SERVER}" >> ~/.ssh/known_hosts
