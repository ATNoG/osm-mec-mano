#!/bin/bash
# Copyright 2021 Canonical Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
#
# For those usages not covered by the Apache License, Version 2.0 please
# contact: legal@canonical.com
#
# To get in touch with the maintainers, please contact:
# osm-charmers@lists.launchpad.net
##

MODULES="lcm pol mon ro nbi"


PRIVATE_KEY=${1:-$HOME/.ssh/id_rsa}
echo "Using $PRIVATE_KEY key."
[ -f $PRIVATE_KEY ] || (echo "$PRIVATE_KEY file does not exist" && exit 1)
PRIVATE_KEY_CONTENT=`cat $PRIVATE_KEY`

mkdir -p ~/.ssh/config.d
echo "" | tee ~/.ssh/config.d/osm


for module in $MODULES; do
    if [[ `juju config -m osm $module debug_mode` == "true" ]]; then
      pod_name=`microk8s.kubectl -n osm get pods | grep -E "^$module-" | grep -v operator | cut -d " " -f 1`
      pod_ip=`microk8s.kubectl -n osm get pods $pod_name -o yaml | yq e .status.podIP -`
      echo "Host $module
  HostName $pod_ip
  User root
  # StrictHostKeyChecking no
  IdentityFile $PRIVATE_KEY" | tee -a ~/.ssh/config.d/osm
    fi
done


import_osm_config="Include config.d/osm"
touch ~/.ssh/config
grep "$import_osm_config" ~/.ssh/config || ( echo -e "$import_osm_config\n$(cat ~/.ssh/config)" > ~/.ssh/config )