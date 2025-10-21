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

set -x

DEBUG_INSTALL=${DEBUG_INSTALL:-}
OSM_DEVOPS=${OSM_DEVOPS:-"/usr/share/osm-devops"}
OPENSTACK_OPENRC_FILE_OR_CLOUD=${OPENSTACK_OPENRC_FILE_OR_CLOUD:-""}
OPENSTACK_PUBLIC_NET_NAME=${OPENSTACK_PUBLIC_NET_NAME:-""}
OPENSTACK_ATTACH_VOLUME=${OPENSTACK_ATTACH_VOLUME:-"false"}
OPENSTACK_SSH_KEY_FILE=${OPENSTACK_SSH_KEY_FILE:-""}
OPENSTACK_USERDATA_FILE=${OPENSTACK_USERDATA_FILE:-""}
OPENSTACK_VM_NAME=${OPENSTACK_VM_NAME:-"server-osm"}
OPENSTACK_PYTHON_VENV=${OPENSTACK_PYTHON_VENV:-"$HOME/.virtual-envs/osm"}
echo "DEBUG_INSTALL=$DEBUG_INSTALL"
echo "OSM_DEVOPS=$OSM_DEVOPS"
echo "OPENSTACK_OPENRC_FILE_OR_CLOUD=$OPENSTACK_OPENRC_FILE_OR_CLOUD"
echo "OPENSTACK_PUBLIC_NET_NAME=$OPENSTACK_PUBLIC_NET_NAME"
echo "OPENSTACK_ATTACH_VOLUME=$OPENSTACK_ATTACH_VOLUME"
echo "OPENSTACK_SSH_KEY_FILE"="$OPENSTACK_SSH_KEY_FILE"
echo "OPENSTACK_USERDATA_FILE"="$OPENSTACK_USERDATA_FILE"
echo "OPENSTACK_VM_NAME"="$OPENSTACK_VM_NAME"
echo "OPENSTACK_PYTHON_VENV"="$OPENSTACK_PYTHON_VENV"

source $OSM_DEVOPS/library/logging
source $OSM_DEVOPS/library/track

[ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function

if [ -z "${OPENSTACK_PUBLIC_NET_NAME}" ]; then
    FATAL "OpenStack installer requires a valid external network name"
fi

# Install Pip for Python3
sudo apt install -y python3-pip python3-venv
sudo -H LC_ALL=C python3 -m pip install -U pip

# Create a venv to avoid conflicts with the host installation
python3 -m venv $OPENSTACK_PYTHON_VENV

source $OPENSTACK_PYTHON_VENV/bin/activate

# Install Ansible, OpenStack client and SDK, latest openstack version supported is Train
python -m pip install -U wheel
python -m pip install -U "python-openstackclient<=4.0.2" "openstacksdk>=0.12.0,<=0.36.2" "ansible>=2.10,<2.11"

# Install the Openstack cloud module (ansible>=2.10)
ansible-galaxy collection install openstack.cloud

export ANSIBLE_CONFIG="$OSM_DEVOPS/installers/openstack/ansible.cfg"

OSM_INSTALLER_ARGS="${REPO_ARGS[@]}"

ANSIBLE_VARS="external_network_name=$OPENSTACK_PUBLIC_NET_NAME setup_volume=$OPENSTACK_ATTACH_VOLUME server_name=$OPENSTACK_VM_NAME"

if [ -n "$OPENSTACK_SSH_KEY_FILE" ]; then
    ANSIBLE_VARS+=" key_file=$OPENSTACK_SSH_KEY_FILE"
fi

if [ -n "$OPENSTACK_USERDATA_FILE" ]; then
    ANSIBLE_VARS+=" userdata_file=$OPENSTACK_USERDATA_FILE"
fi

# Execute the Ansible playbook based on openrc or clouds.yaml
if [ -e "$OPENSTACK_OPENRC_FILE_OR_CLOUD" ]; then
    . $OPENSTACK_OPENRC_FILE_OR_CLOUD
    ansible-playbook -e installer_args="\"$OSM_INSTALLER_ARGS\"" -e "$ANSIBLE_VARS" \
    $OSM_DEVOPS/installers/openstack/site.yml
else
    ansible-playbook -e installer_args="\"$OSM_INSTALLER_ARGS\"" -e "$ANSIBLE_VARS" \
    -e cloud_name=$OPENSTACK_OPENRC_FILE_OR_CLOUD $OSM_DEVOPS/installers/openstack/site.yml
fi

# Exit from venv
deactivate

[ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
exit 0
