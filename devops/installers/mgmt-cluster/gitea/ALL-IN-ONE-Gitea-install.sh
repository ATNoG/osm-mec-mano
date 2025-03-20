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


############################################
# Main script starts here
############################################

source "${HERE}/00-custom-config.rc"
source "${HERE}/01-base-config.rc"
"${HERE}/02-deploy-gitea.sh"
source "${HERE}/03-get-gitea-connection-info.rc"
"${HERE}/04-fix-and-use-external-gitea-urls.sh"
"${HERE}/05-export-connection-info.sh"

# Uncomment to provision for use from OSM
# "${HERE}/90-provision-gitea-for-osm.sh"
