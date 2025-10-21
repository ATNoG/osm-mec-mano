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

echo "INSTALL_MINIO=$INSTALL_MINIO"

pushd $HOME

export DEBIAN_FRONTEND=noninteractive
sudo apt-get update

# Install git, curl, tar
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl tar

# Helm
HELM_VERSION="v3.15.1"
# Helm releases can be found here: https://github.com/helm/helm/releases
if ! [[ "$(helm version --short 2>/dev/null)" =~ ^v3.* ]]; then
    # Helm is not installed. Install helm
    echo "Helm3 is not installed, installing ..."
    curl https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz -o helm-${HELM_VERSION}.tar.gz
    tar -zxvf helm-${HELM_VERSION}.tar.gz
    sudo mv linux-amd64/helm /usr/local/bin/helm
    rm -r linux-amd64
    rm helm-${HELM_VERSION}.tar.gz
else
    echo "Helm3 is already installed. Skipping installation..."
fi
helm version || FATAL_TRACK k8scluster "Could not obtain helm version. Maybe helm client was not installed"
helm repo add stable https://charts.helm.sh/stable || FATAL_TRACK k8scluster "Helm repo stable could not be added"
helm repo update || FATAL_TRACK k8scluster "Helm repo stable could not be updated"
echo "helm installed"

# Install kubectl client
K8S_CLIENT_VERSION="v1.29.3"
curl -LO "https://dl.k8s.io/release/${K8S_CLIENT_VERSION}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl
echo "kubectl installed"

# Install `gnupg` and `gpg` - Typically pre-installed in Ubuntu
sudo DEBIAN_FRONTEND=noninteractive apt-get install gnupg gpg -y
echo "gnupg and gpg installed"

# Install `sops`
curl -LO https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops
echo "sops client installed"

# Install `envsubst`
sudo DEBIAN_FRONTEND=noninteractive apt-get install gettext-base -y
echo "envsubst installed"

# Install `age`
AGE_VERSION="v1.1.0"
curl -LO https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-amd64.tar.gz
tar xvfz age-${AGE_VERSION}-linux-amd64.tar.gz
sudo mv age/age age/age-keygen /usr/local/bin/
sudo chmod +x /usr/local/bin/age*
rm -rf age age-${AGE_VERSION}-linux-amd64.tar.gz
echo "age installed"

# (Only for Gitea) Install `apg`
sudo DEBIAN_FRONTEND=noninteractive apt-get install apg -y
echo "apg installed"

# # (Only for Minio) `kubectl minio` plugin and Minio Client
MINIO_CLIENT_VERSION="5.0.12"
if [ -n "${INSTALL_MINIO}" ]; then
    curl https://github.com/minio/operator/releases/download/v${MINIO_CLIENT_VERSION}/kubectl-minio_${MINIO_CLIENT_VERSION}_linux_amd64 -Lo kubectl-minio
    curl https://dl.min.io/client/mc/release/linux-amd64/mc -o minioc
    chmod +x kubectl-minio minioc
    sudo mv kubectl-minio minioc /usr/local/bin/
    # (Only for HTTPS Ingress for Minio tenant) Install `openssl`
    sudo DEBIAN_FRONTEND=noninteractive apt-get install openssl -y
fi
echo "minio client installed"

# Flux client
FLUX_CLI_VERSION="2.4.0"
curl -s https://fluxcd.io/install.sh | sudo FLUX_VERSION=${FLUX_CLI_VERSION} bash
# Autocompletion
. <(flux completion bash)
echo "flux client installed"

# Argo client
ARGO_VERSION="v3.5.7"
curl -sLO https://github.com/argoproj/argo-workflows/releases/download/${ARGO_VERSION}/argo-linux-amd64.gz
gunzip argo-linux-amd64.gz
chmod +x argo-linux-amd64
sudo mv ./argo-linux-amd64 /usr/local/bin/argo
echo "argo client installed"

# Kustomize
KUSTOMIZE_VERSION="5.4.3"
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- ${KUSTOMIZE_VERSION}
sudo install -o root -g root -m 0755 kustomize /usr/local/bin/kustomize
rm kustomize
echo "kustomized installed"

# yq
VERSION=v4.33.3
BINARY=yq_linux_amd64
curl -L https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -o yq
sudo mv yq /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq
echo "yq installed"

# OSM client
OSM_CLIENT_VERSION=${OSM_CLIENT_VERSION:-"master"}
OSM_IM_VERSION=${OSM_IM_VERSION:-"master"}
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-setuptools python3-dev python3-pip
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libmagic1
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y make
sudo -H python3 -m pip install --break-system-packages --ignore-installed -U pip
# Install OSM IM and its dependencies via pip
python3 -m pip install --break-system-packages -r "https://osm.etsi.org/gitweb/?p=osm/IM.git;a=blob_plain;f=requirements.txt;hb=${OSM_IM_VERSION}"
# Path needs to include $HOME/.local/bin in order to use pyang
[ "$(which pyang)" = "$HOME/.local/bin/pyang" ] || export PATH=$HOME/.local/bin:${PATH}
python3 -m pip install --break-system-packages "git+https://osm.etsi.org/gerrit/osm/IM.git@${OSM_IM_VERSION}#egg=osm-im" --upgrade
python3 -m pip install --break-system-packages -r "https://osm.etsi.org/gitweb/?p=osm/osmclient.git;a=blob_plain;f=requirements.txt;hb=${OSM_CLIENT_VERSION}"
python3 -m pip install --break-system-packages git+https://osm.etsi.org/gerrit/osm/osmclient.git@${OSM_CLIENT_VERSION}#egg=osmclient
echo "OSM client installed"

popd
