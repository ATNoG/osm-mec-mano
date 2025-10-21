#!/bin/bash
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#

set -e -o pipefail
set -x

HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
source "${HERE}/../library/functions.sh"
source "${HERE}/../library/trap.sh"
source "${HERE}/../library/logging"
source "${HERE}/../library/track"

source "${HERE}/00-default-install-options.rc"
[ ! -f "${OSM_HOME_DIR}/user-install-options.rc" ] || source "${OSM_HOME_DIR}/user-install-options.rc"
source "${CREDENTIALS_DIR}/osm_environment.rc"

KUBECONFIG_OSM_CLUSTER_FILE="${OSM_HOME_DIR}/clusters/kubeconfig-osm.yaml"

[ -n "${OSM_HOSTNAME}" ] || FATAL "OSM_HOSTNAME is not set" "${OSM_HOSTNAME}" \
    "Please set the OSM_HOSTNAME environment variable to the hostname of your OSM instance."
[ "$(which osm)" = "$HOME/.local/bin/osm" ] || export PATH=$HOME/.local/bin:${PATH}
osm --hostname ${OSM_HOSTNAME} --all-projects vim-create \
    --name _system-osm-vim \
    --account_type dummy \
    --auth_url http://dummy \
    --user osm --password osm --tenant osm \
    --description "dummy" \
    --config '{management_network_name: mgmt}'
osm --hostname ${OSM_HOSTNAME} --all-projects k8scluster-add \
    --creds ${KUBECONFIG_OSM_CLUSTER_FILE} \
    --vim _system-osm-vim \
    --k8s-nets '{"net1": null}' \
    --version '1.29' \
    --description "OSM Internal Cluster" \
    _system-osm-k8s
