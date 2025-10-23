#######################################################################################
# Copyright ETSI Contributors and Others.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#######################################################################################

set -e -o pipefail

export HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
source "${HERE}/library/functions.sh"
source "${HERE}/library/trap.sh"


AGE_KEY_NAME="$1"
CLUSTER_DIR="$2"

# Load the contents of both keys
export PRIVATE_KEY=$(<"${CREDENTIALS_DIR}/${AGE_KEY_NAME}.key")
export PUBLIC_KEY=$(<"${CREDENTIALS_DIR}/${AGE_KEY_NAME}.pub")

# Add the `age` private key to the cluster as secret:
kubectl delete secret sops-age --namespace=flux-system 2> /dev/null || true
# cat "${CREDENTIALS_DIR}/${AGE_KEY_NAME}.key" |
echo "${PRIVATE_KEY}" |
    kubectl create secret generic sops-age \
    --namespace=flux-system \
    --from-file=age.agekey=/dev/stdin

# Create SOPS configuration at the root folder of the management cluster:
cat <<EOF > "${CLUSTER_DIR}/.sops.yaml"
creation_rules:
  - encrypted_regex: ^(data|stringData)$
    age: ${PUBLIC_KEY}
  # - path_regex: .*.yaml
  #   encrypted_regex: ^(data|stringData)$
  #   age: ${PUBLIC_KEY}
EOF

# Add also the public key to the repository so that others who clone the repo can encrypt new files:
cp "${CREDENTIALS_DIR}/${AGE_KEY_NAME}.pub" "${CLUSTER_DIR}/.sops.pub.asc"
