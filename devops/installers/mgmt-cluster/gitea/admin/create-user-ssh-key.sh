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

# PARAMETERS:
# ==========
# 1) Server URL
# 2) Username
# 3) Token
# 4) SSH key content
# 5) SSH key name in Gitea's user profile
# 6) Read only?
SERVER_URL=$1
USERNAME=$2
TOKEN=$3
SSH_KEY="${4}"
KEY_NAME=$5
READ_ONLY=${6:-false}

"$HERE/api.sh" "${SERVER_URL}" "${TOKEN}" \
	POST \
	user/keys \
	"{\"key\": \"${SSH_KEY}\", \"read_only\": ${READ_ONLY}, \"title\": \"${KEY_NAME}\"}"
