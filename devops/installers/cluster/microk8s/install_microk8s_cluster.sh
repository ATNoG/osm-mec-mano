#!/usr/bin/env bash
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

set +eux

# MicroK8s installation
sudo snap install yq
sudo snap install microk8s --classic
sudo usermod -a -G microk8s ubuntu
newgrp microk8s
sudo microk8s.status --wait-ready
sudo microk8s.enable storage dns
# sudo microk8s.enable storage rbac
# sudo microk8s.enable storage helm
# sudo microk8s.enable storage helm3

# Enables MetalLB
PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo ${PRIVATE_IP}
sudo microk8s.enable metallb:${PRIVATE_IP}-${PRIVATE_IP}

# Updates the certificate to allow connections from outside as well (i.e. to the "public" IP).
#sudo microk8s.stop
sudo sed -i "s/\#MOREIPS/IP.3 = ${NEW_K8S_IP}/g" /var/snap/microk8s/current/certs/csr.conf.template
cat /var/snap/microk8s/current/certs/csr.conf.template
#sudo microk8s.refresh-certs -i
#sudo microk8s.start

# Retrieves and saves the credentials
sudo microk8s.config | sed  "s/server: .*/server: https:\/\/${NEW_K8S_IP}:16443/g" \
| tee ${HOME}/.kube/config
echo
echo Credentials saved at ${HOME}/.kube/config
echo

return 0

