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

set +eux

K8S_VERSION=1.30
K8S_PACKAGE_VERSION="$K8S_VERSION".1-1.1
K8S_METRICS_VERSION="v0.7.1"

# installs kubernetes packages
function install_kube() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    # Kubernetes releases can be found here: https://kubernetes.io/releases/
    # To check other available versions, run the following command
    # curl -s https://packages.cloud.google.com/apt/dists/kubernetes-xenial/main/binary-amd64/Packages | grep Version | awk '{print $2}'
    sudo apt-get -y update && sudo apt-get install -y apt-transport-https ca-certificates curl
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v"$K8S_VERSION"/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v'$K8S_VERSION'/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get -y update
    echo "Installing Kubernetes Packages ..."
    sudo apt-get install -y kubelet=${K8S_PACKAGE_VERSION} kubeadm=${K8S_PACKAGE_VERSION} kubectl=${K8S_PACKAGE_VERSION}
    sudo apt-mark hold kubelet kubeadm kubectl
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# check and track kube packages installation
function check_and_track_kube_install() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    kubelet_version=$(dpkg -s kubelet|grep Version|awk '{print $2}')
    [ -n "${kubelet_version}" ] || FATAL_TRACK k8scluster "Kubelet was not installed."
    kubeadm_version=$(dpkg -s kubeadm|grep Version|awk '{print $2}')
    [ -n "${kubeadm_version}" ] || FATAL_TRACK k8scluster "Kubeadm was not installed."
    kubectl_version=$(dpkg -s kubectl|grep Version|awk '{print $2}')
    [ -n "${kubectl_version}" ] || FATAL_TRACK k8scluster "Kubectl was not installed."
    track k8scluster install_k8s_ok none none none kubelet ${kubelet_version} none none kubeadm ${kubeadm_version} none none kubectl ${kubectl_version} none none
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# initializes kubernetes control plane
function init_kubeadm() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    sudo swapoff -a
    sudo sed -i.bak '/.*none.*swap/s/^\(.*\)$/#\1/g' /etc/fstab
    sudo kubeadm init --config $1 --dry-run || FATAL_TRACK k8scluster "kubeadm init dry-run failed"
    sudo kubeadm init --config $1
    sleep 5
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# Initializes kubeconfig file
function save_kubeconfig() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    K8S_MANIFEST_DIR="/etc/kubernetes/manifests"
    [ ! -d $K8S_MANIFEST_DIR ] && FATAL_TRACK k8scluster "Kubernetes folder $K8S_MANIFEST_DIR was not found"
    KUBEDIR="${HOME}/.kube"
    KUBEFILE="$KUBEDIR/config"
    mkdir -p "${KUBEDIR}"
    KUBEADM_KUBECONFIG="/etc/kubernetes/admin.conf"
    sudo cp "${KUBEADM_KUBECONFIG}" "${KUBEFILE}"
    sudo chown $(id -u):$(id -g) "${KUBEFILE}"
    echo
    echo "Credentials saved at ${KUBEFILE}"
    echo
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# test kubernetes installation
function check_and_track_init_k8s() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo "Reading existing namespaces"
    kubectl get ns || FATAL_TRACK k8scluster "Failed getting namespaces"
    track k8scluster init_k8s_ok
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# deploys flannel as daemonsets
function deploy_cni_provider() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    CNI_DIR="$(mktemp -d -q --tmpdir "flannel.XXXXXX")"
    trap 'rm -rf "${CNI_DIR}"' EXIT
    KUBE_FLANNEL_FILE_URL="https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
    curl -f --retry 5 --retry-delay 2 --retry-connrefused "${KUBE_FLANNEL_FILE_URL}" -o "$CNI_DIR/$(basename ${KUBE_FLANNEL_FILE_URL})"
    [ ! -f $CNI_DIR/kube-flannel.yml ] && FATAL_TRACK k8scluster "Cannot Install Flannel because $CNI_DIR/kube-flannel.yml was not found. Maybe the file ${KUBE_FLANNEL_FILE_URL} is temporarily not accessible"
    kubectl apply -f $CNI_DIR
    [ $? -ne 0 ] && FATAL_TRACK k8scluster "Cannot Install Flannel"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# taints K8s master node
function taint_master_node() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    K8S_MASTER=$(kubectl get nodes | awk '$3~/control-plane/'| awk '{print $1; exit}')
    kubectl taint node $K8S_MASTER node-role.kubernetes.io/control-plane:NoSchedule-
    sleep 5
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# check and track kube packages installation
function check_and_track_k8s_ready_before_helm() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    kubectl get events || FATAL_TRACK k8scluster "Failed getting events"
    track k8scluster k8s_ready_before_helm
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# removes osm deployments and services
function install_k8s_metrics() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo "Installing Kubernetes metrics"
    kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/${K8S_METRICS_VERSION}/components.yaml"
    kubectl -n kube-system patch deployment metrics-server --type=json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# removes osm deployments and services
function remove_k8s_namespace() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo "Deleting existing namespace $1: kubectl delete ns $1"
    kubectl delete ns $1 2>/dev/null
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# main
while getopts ":-: " o; do
    case "${o}" in
        -)
            [ "${OPTARG}" == "debug" ] && DEBUG_INSTALL="y" && continue
            echo -e "Invalid option: '--$OPTARG'\n" >&2
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument" >&2
            exit 1
            ;;
        \?)
            echo -e "Invalid option: '-$OPTARG'\n" >&2
            exit 1
            ;;
        *)
            exit 1
            ;;
    esac
done

DEBUG_INSTALL=${DEBUG_INSTALL:-}
K8SCLUSTER_CONFIG_FOLDER=${K8SCLUSTER_CONFIG_FOLDER:-"/etc/osm"}
echo "DEBUG_INSTALL=$DEBUG_INSTALL"
echo "K8SCLUSTER_CONFIG_FOLDER=$K8SCLUSTER_CONFIG_FOLDER"
echo "HOME=$HOME"

export HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
source "${HERE}/../../../library/logging"
source "${HERE}/../../../library/track"

echo "Creating folders for installation"
[ ! -d "$K8SCLUSTER_CONFIG_FOLDER" ] && sudo mkdir -p $K8SCLUSTER_CONFIG_FOLDER
echo "Copying kubeadm-config from ${HERE}/installers/kubeadm-config.yaml to $K8SCLUSTER_CONFIG_FOLDER/kubeadm-config.yaml"
sudo cp -b "${HERE}/kubeadm-config.yaml" "$K8SCLUSTER_CONFIG_FOLDER/kubeadm-config.yaml"

install_kube
check_and_track_kube_install

init_kubeadm "${K8SCLUSTER_CONFIG_FOLDER}/kubeadm-config.yaml"
save_kubeconfig
check_and_track_init_k8s

deploy_cni_provider
taint_master_node
check_and_track_k8s_ready_before_helm

install_k8s_metrics

# Clean existing namespace (idempotent installation)
remove_k8s_namespace osm

# Installation of storage class, metallb and cert-manager
# is done outside this script, by install_cluster_addons.sh
