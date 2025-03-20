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

wget https://osm-download.etsi.org/ftp/osm-7.0-seven/install_osm.sh
chmod +x install_osm.sh
#./install_osm.sh -c k8s --k8s_monitor --elk_stack 2>&1 | tee osm_install_log.txt
#./install_osm.sh -c k8s --k8s_monitor 2>&1 | tee osm_install_log.txt
./install_osm.sh 2>&1 | tee osm_install_log.txt

# Saves the IP address used during install, in case the VM needed to be reinstantiated later with a different IP address
sudo mkdir -p  ${STATE_FOLDER}
sudo chmod a+r ${STATE_FOLDER}
DEFAULT_IF=$(route -n |awk '$1~/^0.0.0.0/ {print $8}')
DEFAULT_IP=$(ip -o -4 a |grep ${DEFAULT_IF}|awk '{split($4,a,"/"); print a[1]}')
sudo su - -c "echo ${DEFAULT_IP} > ${STATE_FOLDER}/oldIPaddress.txt"
