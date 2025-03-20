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
TOKEN=$3
REPO=$4
COLLABORATOR=$5
PERMISSION=${6:-"write"}

"$HERE/api.sh" "${SERVER_URL}" "${TOKEN}" \
	PUT \
	"repos/${USERNAME}/${REPO}/collaborators/${COLLABORATOR}" \
    "{\"permission\": \"${PERMISSION}\"}"
