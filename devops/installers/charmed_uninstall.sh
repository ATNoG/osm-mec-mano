#! /bin/bash
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


juju destroy-model osm --destroy-storage -y
sudo snap unalias osm
sudo snap remove osmclient
CONTROLLER_NAME="osm-vca"
CONTROLLER_PRESENT=$(juju controllers 2>/dev/null| grep ${CONTROLLER_NAME} | wc -l)
if [[ $CONTROLLER_PRESENT -ge 1 ]]; then
    cat << EOF
The VCA with the name "${CONTROLLER_NAME}" has been left in place to ensure that no other
applications are using it.  If you are sure you wish to remove this controller,
please execute the following command:

   juju destroy-controller --release-storage --destroy-all-models -y ${CONTROLLER_NAME}

EOF
fi
