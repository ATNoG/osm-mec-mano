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

HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
. "$HERE/../library/functions.sh"
. "$HERE/../library/trap.sh"

SERVER_URL=$1
USERNAME=$2
PASSWORD=$3
TOKEN_NAME=$4

# Unfortunately this inconsistently spits out logs stdout, making it challenging to parse
# "$HERE/gitea" admin user generate-access-token --username "$USERNAME" --raw | tail -1 > "$HERE/tokens/$USERNAME"

# See: https://docs.gitea.io/en-us/api-usage/#generating-and-listing-api-tokens

# Delete old "${TOKEN_NAME}" token (if existed)
kubectl exec statefulset/gitea --container=gitea --namespace=gitea --quiet -- \
curl --silent --fail \
	"${SERVER_URL}/api/v1/users/$USERNAME/tokens/${TOKEN_NAME}" \
	--user "$USERNAME:$PASSWORD" \
	--request DELETE \
	--header 'Accept: application/json' || true > /dev/null

# Create new "${TOKEN_NAME}" token
# (this is our only chance to retrieve the sha1)
kubectl exec statefulset/gitea --container=gitea --namespace=gitea --quiet -- \
curl --silent --fail \
	"${SERVER_URL}/api/v1/users/$USERNAME/tokens" \
	--user "$USERNAME:$PASSWORD" \
	--request POST \
	--header 'Accept: application/json' \
	--header 'Content-Type: application/json' \
	--data "{\"name\": \"${TOKEN_NAME}\"}" | jq --raw-output .sha1
