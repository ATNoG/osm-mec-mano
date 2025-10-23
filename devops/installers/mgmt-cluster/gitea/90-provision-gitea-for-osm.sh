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


#####################################################################
# Step 1: Create regular user and obtain tokens
#####################################################################

# Creates an aditional regular user
# ---------------------------------
m "Creating new user \"${GITEA_STD_USERNAME}\"..."
"${HERE}/admin/create-user.sh" "${GITEA_STD_USERNAME}" "${GITEA_STD_USER_PASS}" "${GITEA_STD_USERNAME}@gitea"
# "${HERE}/admin/create-user.sh" "${GITEA_STD_USERNAME}" "${GITEA_STD_USER_PASS}" "${GITEA_STD_USERNAME}@gitea" --admin

m "New username: ${GITEA_STD_USERNAME}" "$CYAN"
#m "New user's password: ${GITEA_STD_USER_PASS}" "$CYAN"

# Creates access token for the admin
# ----------------------------------
export GITEA_ADMINISTRATOR_TOKEN=$( \
    "${HERE}/admin/create-cmd-access-token.sh" "${GITEA_ADMINISTRATOR_USERNAME}" "${GITEA_ADMINISTRATOR_TOKEN_NAME}" | \
    grep 'Access token was successfully created' | \
    cut -d ' ' -f 6 \
)
m "Admin token name: ${GITEA_ADMINISTRATOR_TOKEN_NAME}"
m "Admin token: ${GITEA_ADMINISTRATOR_TOKEN}"

# Creates access token for the user
# ---------------------------------
export GITEA_STD_TOKEN=$( \
    "${HERE}/admin/create-cmd-access-token.sh" "${GITEA_STD_USERNAME}" "${GITEA_STD_TOKEN_NAME}" | \
    grep 'Access token was successfully created' | \
    cut -d ' ' -f 6 \
)
m "Standard user token name: ${GITEA_STD_TOKEN_NAME}"
m "Standard user token: ${GITEA_STD_TOKEN}"

# # Alternative method, via API
# # ---------------------------
# export GITEA_STD_TOKEN=$( \
#     "${HERE}/admin/create-api-access-token.sh" "${GITEA_HTTP_URL}" "${GITEA_STD_USERNAME}" "${GITEA_STD_USER_PASS}" "${GITEA_STD_TOKEN_NAME}" \
# )

# Save tokens
# ---------------------------------
m "Saving tokens to credentials folder..."

cat << EOF > "${CREDENTIALS_DIR}/gitea_tokens.rc"
export GITEA_ADMINISTRATOR_TOKEN_NAME=${GITEA_ADMINISTRATOR_TOKEN_NAME}
export GITEA_ADMINISTRATOR_TOKEN=${GITEA_ADMINISTRATOR_TOKEN}
export GITEA_STD_TOKEN_NAME=${GITEA_STD_TOKEN_NAME}
export GITEA_STD_TOKEN=${GITEA_STD_TOKEN}
EOF

m "Done."

# Saves into K8s cluster as a secret
m "Saving tokens to secret into K8s cluster..."

kubectl delete secret gitea-tokens -n gitea 2> /dev/null || true
kubectl create secret generic gitea-tokens -n gitea \
    --from-literal=GITEA_ADMINISTRATOR_TOKEN_NAME=${GITEA_ADMINISTRATOR_TOKEN_NAME} \
    --from-literal=GITEA_ADMINISTRATOR_TOKEN=${GITEA_ADMINISTRATOR_TOKEN} \
    --from-literal=GITEA_STD_TOKEN_NAME=${GITEA_STD_TOKEN_NAME} \
    --from-literal=GITEA_STD_TOKEN=${GITEA_STD_TOKEN}

m "Done."
echo
m "Example: To retrieve token for standard user:"
m "kubectl get secret gitea-tokens -n gitea -o jsonpath='{.data.GITEA_STD_TOKEN}' | base64 -d" ${CYAN}
echo


#####################################################################
# Step 2: Create repositories
#####################################################################

# Loads tokens
# ---------------------------------
# m "Reloading tokens..."
# source "${CREDENTIALS_DIR}/gitea_tokens.rc"
# echo

# Creates `fleet-osm` and `sw-catalogs-osm` repos in the space of the standard user
# ----------------------------------------------------
export REPO=fleet-osm
m "Creating ${REPO} repo..."
"${HERE}/admin/create-user-repository.sh" "${GITEA_HTTP_URL}" "${GITEA_STD_USERNAME}" "${GITEA_STD_TOKEN}" "${REPO}" false
m "Done."
echo

export REPO=sw-catalogs-osm
m "Creating ${REPO} repo..."
"${HERE}/admin/create-user-repository.sh" "${GITEA_HTTP_URL}" "${GITEA_STD_USERNAME}" "${GITEA_STD_TOKEN}" "${REPO}" false
m "Done."
echo

# Deletes a repo in the space of the standard user
# ------------------------------------------------------
# export REPO=name-of-repo-to-delete
# "${HERE}/admin/delete-user-repository.sh" "${GITEA_HTTP_URL}" "${GITEA_STD_USERNAME}" "${GITEA_STD_TOKEN}" "${REPO}"



# #####################################################################
# # Other provisioning actions, for reference:
# #####################################################################

# # Creates new organization
# # ------------------------
# # "${HERE}/admin/create-org.sh" "${GITEA_HTTP_URL}" "${GITEA_ADMINISTRATOR_USERNAME}" "${GITEA_ADMINISTRATOR_TOKEN}" "${GITEA_EXTRA_ORGANIZATION}" private

# # Creates a new repo in the organization
# # --------------------------------------
# # export REPO=test-repo
# # "${HERE}/admin/create-org-repository.sh" "${GITEA_HTTP_URL}" "${GITEA_STD_USERNAME}" "${GITEA_ADMINISTRATOR_TOKEN}" "${GITEA_EXTRA_ORGANIZATION}" "${REPO}" true

# # Deletes the repo in the space of the standard user
# # --------------------------------------------------
# # "${HERE}/admin/delete-org-repository.sh" "${GITEA_HTTP_URL}" "${GITEA_STD_USERNAME}" "${GITEA_ADMINISTRATOR_TOKEN}" "${GITEA_EXTRA_ORGANIZATION}" "${REPO}"

# # Deletes organization
# # --------------------
# # "${HERE}/admin/delete-org.sh" "${GITEA_HTTP_URL}" "${GITEA_ADMINISTRATOR_USERNAME}" "${GITEA_ADMINISTRATOR_TOKEN}" "${GITEA_EXTRA_ORGANIZATION}"

# # Creates a new repo in the space of the standard user
# # ----------------------------------------------------
# # export REPO=test-user-repo
# # "${HERE}/admin/create-user-repository.sh" "${GITEA_HTTP_URL}" "${GITEA_STD_USERNAME}" "${GITEA_STD_TOKEN}" "${REPO}" false

# # Deletes the new repo in the space of the standard user
# # ------------------------------------------------------
# # "${HERE}/admin/delete-user-repository.sh" "${GITEA_HTTP_URL}" "${GITEA_STD_USERNAME}" "${GITEA_STD_TOKEN}" "${REPO}"
