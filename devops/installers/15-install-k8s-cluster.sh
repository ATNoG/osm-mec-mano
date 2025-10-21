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

HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
source "${HERE}/../library/functions.sh"
source "${HERE}/../library/trap.sh"
source "${HERE}/../library/logging"
source "${HERE}/../library/track"

source "${HERE}/00-default-install-options.rc"
[ ! -f "${OSM_HOME_DIR}/user-install-options.rc" ] || source "${OSM_HOME_DIR}/user-install-options.rc"

export K8SCLUSTER_CONFIG_FOLDER=${K8SCLUSTER_CONFIG_FOLDER:-"/etc/osm"}
export DEFAULT_IP=${OSM_DEFAULT_IP:-"127.0.0.1"}

echo "K8S_CLUSTER_ENGINE=$K8S_CLUSTER_ENGINE"
if [ "${K8S_CLUSTER_ENGINE}" == "kubeadm" ]; then
    KUBEADM_INSTALL_OPTS="--debug"
    ${HERE}/cluster/kubeadm/install_kubeadm_cluster.sh ${KUBEADM_INSTALL_OPTS} || \
    FATAL_TRACK k8scluster "install_kubeadm_cluster.sh failed"
    K8SCLUSTER_ADDONS_INSTALL_OPTS="--all"
    ${HERE}/cluster/addons/install_cluster_addons.sh ${K8SCLUSTER_ADDONS_INSTALL_OPTS} || \
    FATAL_TRACK k8scluster "install_cluster_addons.sh failed for kubeadm cluster"
elif [ "${K8S_CLUSTER_ENGINE}" == "k3s" ]; then
    export K3S_PUBLIC_IP=
    [ "${OSM_K8S_EXTERNAL_IP}" != "${OSM_DEFAULT_IP}" ] && K3S_PUBLIC_IP=${OSM_K8S_EXTERNAL_IP}
    # The K3s installation script will automatically take the HTTP_PROXY, HTTPS_PROXY and NO_PROXY,
    # as well as the CONTAINERD_HTTP_PROXY, CONTAINERD_HTTPS_PROXY and CONTAINERD_NO_PROXY variables
    # from the shell, if they are present, and write them to the environment file of k3s systemd service,
    ${HERE}/cluster/k3s/install_k3s_cluster.sh || \
    FATAL_TRACK k8scluster "install_k3s_cluster.sh failed"
    K8SCLUSTER_ADDONS_INSTALL_OPTS="--certmgr --nginx"
    ${HERE}/cluster/addons/install_cluster_addons.sh ${K8SCLUSTER_ADDONS_INSTALL_OPTS} || \
    FATAL_TRACK k8scluster "install_cluster_addons.sh failed for k3s cluster"
fi
echo "Updating fsnotify settings of the system kernel"
sudo bash -c "sysctl -w fs.inotify.max_user_watches=699050 > /etc/sysctl.d/99-custom-osm-sysctl.conf"
sudo bash -c "sysctl -w fs.inotify.max_user_instances=10922 >> /etc/sysctl.d/99-custom-osm-sysctl.conf"
sudo bash -c "sysctl -w fs.inotify.max_queued_events=1398101 >> /etc/sysctl.d/99-custom-osm-sysctl.conf"

echo "K8s cluster installed"
