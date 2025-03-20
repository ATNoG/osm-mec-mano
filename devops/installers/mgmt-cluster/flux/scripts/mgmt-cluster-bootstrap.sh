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


# Bootstrap
REPO=fleet-osm
GIT_PATH=./clusters/_management
GIT_BRANCH=main
GIT_HTTP_URL=${GITEA_HTTP_URL}/${GITEA_STD_USERNAME}/${REPO}.git
flux bootstrap git \
    --url=${GIT_HTTP_URL} \
    --allow-insecure-http=true \
    --username=${GITEA_STD_USERNAME} \
    --password="${GITEA_STD_USER_PASS}" \
    --token-auth=true \
    --branch=${GIT_BRANCH} \
    --path=${GIT_PATH}

# Check if successful
flux check
