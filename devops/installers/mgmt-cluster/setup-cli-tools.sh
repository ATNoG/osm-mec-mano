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

pushd $HOME

# Install `gnupg` and `gpg` - Typically pre-installed in Ubuntu
sudo apt-get install gnupg gpg

# Install `sops`
curl -LO https://github.com/getsops/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64
sudo mv sops-v3.8.1.linux.amd64 /usr/local/bin/sops
sudo chmod +x /usr/local/bin/sops

# Install `envsubst`
sudo apt-get install gettext-base

# Install `age`
curl -LO https://github.com/FiloSottile/age/releases/download/v1.1.0/age-v1.1.0-linux-amd64.tar.gz
tar xvfz age-v1.1.0-linux-amd64.tar.gz
sudo mv age/age age/age-keygen /usr/local/bin/
sudo chmod +x /usr/local/bin/age*
rm -rf age age-v1.1.0-linux-amd64.tar.gz

# (Only for Gitea) Install `apg`
sudo apt-get install apg

# # (Only for Minio) `kubectl minio` plugin and Minio Client
if [ -n "${INSTALL_MINIO}" ]; then
    curl https://github.com/minio/operator/releases/download/v5.0.12/kubectl-minio_5.0.12_linux_amd64 -Lo kubectl-minio
    curl https://dl.min.io/client/mc/release/linux-amd64/mc -o minioc
    chmod +x kubectl-minio minioc
    sudo mv kubectl-minio minioc /usr/local/bin/
    # (Only for HTTPS Ingress for Minio tenant) Install `openssl`
    sudo apt-get install openssl
fi

# Flux client
FLUX_CLI_VERSION="2.4.0"
curl -s https://fluxcd.io/install.sh | sudo FLUX_VERSION=${FLUX_CLI_VERSION} bash
# Autocompletion
. <(flux completion bash)

# Argo client
ARGO_VERSION="v3.5.7"
curl -sLO https://github.com/argoproj/argo-workflows/releases/download/${ARGO_VERSION}/argo-linux-amd64.gz
gunzip argo-linux-amd64.gz
chmod +x argo-linux-amd64
sudo mv ./argo-linux-amd64 /usr/local/bin/argo

# Kustomize
KUSTOMIZE_VERSION="5.4.3"
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash -s -- ${KUSTOMIZE_VERSION}
sudo install -o root -g root -m 0755 kustomize /usr/local/bin/kustomize
rm kustomize

# yq
VERSION=v4.33.3
BINARY=yq_linux_amd64
curl -L https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -o yq
sudo mv yq /usr/local/bin/yq
sudo chmod +x /usr/local/bin/yq

popd
