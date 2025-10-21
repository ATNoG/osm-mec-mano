<!--
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
implied.
See the License for the specific language governing permissions and
limitations under the License
-->
# Provisioning of K8s clusters to meet pre-requirements for cloud-native OSM

[TOC]

## 0. Introduction

This folder provides all required scripts and instructions for the full provisioning of the cluster(s) required for enabling a cloud-native way of work in OSM:

- **Cluster for Auxiliary Services.** This cluster runs auxiliary services that are required for a cloud native operation, but do not need to run necessarily in a `Management Cluster`.
  - Note that the services served from this cluster might be replaced by standalone PaaS/SaaS services if needed, such as GitHub or Amazon S3, with the proper configurations.
  - At the time of this writing, this cluster provides:
    - **Git repo service** based on Gitea.
    - **Object storage service** based on Minio. This service **should not be installed by default**, although users may want to run the automatic installation at their own discretion.
  - For convenience, the web endpoints of these services are exposed via a NGINX _Ingress_.
- **Management cluster.** This cluster runs the core CRDs and Operators required for a successful cloud-native operation assisted by a Kubernetes control plane.
  - This includes a cluster successfully bootstrapped with **Flux**, where:
    - Secrets are encrypted with SOPS.
    - With Crossplane operator and desired providers installed.
    - CAPI operators installed.
  - For achieving that goal, the corresponding Git repositories are initialized with all required manifests and folder structure, so that all installations happen along the bootstrap operation. By default, the Git repositories created at the _Cluster for Auxiliary Services_ will be used.

## 1. Cluster for Auxiliary Services

First, you should load the environment variables with the key folders and configuration parameters. By default, in case some of them where still undefined, you may load sensible defaults by doing:

```bash
source 20-base-config.rc
```

Then, you should select the appropriate `kubeconfig` to point to the cluster where you want to install the auxiliary services. For instance:

```bash
export KUBECONFIG="${CREDENTIALS_DIR}/kubeconfig-aux-svc.yaml"
# Alternatively:
# kubectl config use-context osm-aux-svc-admin
```

Then run the all-in-one installer and, optionally, add the local Git user for more a more convenient setup to commit changes to the repos:

```bash
./01-provision-aux-svc.sh

# (optional)
./02-provision-local-git-user.sh
```

### 1.1 Test auxiliary services

First retrieve service's credentials and endpoints as environment variables:

```bash
# Load Gitea environment
source "${CREDENTIALS_DIR}/git_environment.rc"
source "${CREDENTIALS_DIR}/gitea_tokens.rc"

# Load Minio environment
source "${CREDENTIALS_DIR}/minio_environment.rc"
```

#### 1.1.1 Test Gitea service

```bash
# Get URL and credentials to go with browser
echo "Gitea HTTP URL: ${GITEA_HTTP_URL}"
echo "Gitea admin user:"
echo -e "- \tUser name: ${GITEA_ADMINISTRATOR_USERNAME}"
echo -e "- \tPassword: ${GITEA_ADMINISTRATOR_PASSWORD}"
echo "Gitea regular user:"
echo -e "- \tUser name: ${GITEA_STD_USERNAME}"
echo -e "- \tPassword: ${GITEA_STD_USER_PASS}"

# SSH URL
echo "Gitea SSH URL: ${GITEA_SSH_URL}"
```

#### 1.1.2 Test Minio service

Get the URL and the JWT token to access the Minio Operator Console with the browser:

```bash
# Open URL in browser using the JWT as access token
echo "Console URL: ${MINIO_CONSOLE_URL}"
echo -e "JWT token:\n${MINIO_SA_TOKEN}"
```

Then test the tenant:

```bash
# Add alias to connect to the tenant
ALIAS=osm
echo "Minio Tenant URL: ${MINIO_TENANT_URL}"
minioc alias set ${ALIAS} ${MINIO_TENANT_URL} ${MINIO_OSM_USERNAME} ${MINIO_OSM_PASSWORD} --insecure

# Test
minioc admin info ${ALIAS} --insecure

# (optional) Delete the alias
minioc alias remove ${ALIAS}
```

## 2. Management Cluster

First, you should load the environment variables with the key folders and configuration parameters (in case your had not done it before). By default, in case some of them where still undefined, you may load sensible defaults by doing:

```bash
source 00-base-config.rc
```

Then, you should select the appropriate `kubeconfig` to point to the cluster that you want to make a management cluster for OSM. For instance:

```bash
export KUBECONFIG="${CREDENTIALS_DIR}/kubeconfig-mgmt.yaml"
# Alternatively:
# kubectl config use-context osm-mgmt-admin
```

Depending on your situation, you can choose among these three procedures:

1. Quickstart (recommended).
   - Based on regular Flux bootstrap with a new `age` key pair, reusing a set of pre-created manifests so that the process is simplified.
2. Restore a prior management cluster (from Git repo and `age` key pair).
   - Flux bootstrap over the Git repo used by a pre-existing management cluster, using the previous `age` key pair.
3. Create management cluster from scratch (useful for development and evolution of reference manifests)
   - Based on regular Flux bootstrap with a new `age` key pair.
   - Manifests are created from scratch.

### 2.1 Quickstart (recommended)

**NOTE:** Before proceeding, please ensure the appropriate `kubeconfig` and make sure to source the required base configuration at `00-base-config.rc`.

```bash
./03-provision-mgmt-cluster.sh
```

(optional) Watch sync progress:

```bash
./flux/scripts/watch-mgmt-cluster.sh
```

#### 2.1.1 (optional) Test creation of secrets using SOPS encryption

```bash
# Sources helper functions
source ./flux/scripts/helper-functions.rc

# Creates a secret and encrypts it with age
SECRET_NAME="test-secret"
PROJECT_DIR="${FLEET_REPO_DIR}/${MGMT_PROJECT_NAME}"
PROFILE_NAME="_management"
RESOURCES_DIR="${PROJECT_DIR}/managed-resources/${PROFILE_NAME}"
kubectl create secret generic "${SECRET_NAME}" \
  --namespace managed-resources \
  --from-literal=foo=bar \
  -o yaml --dry-run=client | tee "${RESOURCES_DIR}/secret-${SECRET_NAME}.yaml"

# Encrypt in-place
encrypt_secret_inplace "${RESOURCES_DIR}/secret-${SECRET_NAME}.yaml"

# (Optional) View the secret manifest once encrypted
cat "${RESOURCES_DIR}/secret-${SECRET_NAME}.yaml"
```

Push the new manifest:

```bash
pushd "${FLEET_REPO_DIR}"
git status
git add -A
git commit -m "Test of encrypted secret"
git push
popd
```

Check that the secret was successfully decrypted by Flux and created properly:

```bash
kubectl get secret ${SECRET_NAME} -n managed-resources -o yaml
kubectl get secret ${SECRET_NAME} -n managed-resources -o jsonpath='{.data.foo}' | base64 -d
```

Cleanup:

```bash
rm "${RESOURCES_DIR}/secret-${SECRET_NAME}.yaml"

pushd "${FLEET_REPO_DIR}"
git status
git add -A
git commit -m "Cleanup: Remove test secret"
git push
popd
```

After a while it should be deleted:

```bash
watch kubectl get secret ${SECRET_NAME} -n managed-resources
```

#### 2.1.2 (optional) Check the readiness of management cluster add-ons

```bash
# Check the health of Crossplane providers
kubectl get providers.pkg.crossplane.io
kubectl get crd | grep upbound
# kubectl get crd | grep azure
# kubectl get crd | grep gcp

# Check the availability of Argo WorkFlows
kubectl port-forward deployment/argo-server -n argo 2746:2746
# Open <https://localhost:2746>
```

### 2.2 Restore a prior management cluster from Git repo and `age` key pair

TODO:

### 2.3 Creation from scratch

#### 2.3.1 Preparation

Load the environment:

```bash
source 00-base-config.rc
source "${CREDENTIALS_DIR}/git_environment.rc"
source "${CREDENTIALS_DIR}/gitea_tokens.rc"
```

For convenience, create in Gitea a local user's profile, add public SSH key, and add as collaborator to the repo of the standard Gitea user (NOTE: We have to force the `kubeconfig` profile for the cluster for auxiliary services):

```bash
# Create new user
export USER_NAME=$(git config --get user.name)
export USER_MAIL=$(git config --get user.email)
export USER_PASS="${GITEA_STD_USER_PASS}" # Same as standard user
KUBECONFIG="${CREDENTIALS_DIR}/kubeconfig-aux-svc.yaml" "gitea/admin/create-user.sh" \
  "${USER_NAME}" \
  "${USER_PASS}" \
  "${USER_MAIL}"

# Create token
export USER_TOKEN_NAME=user_token_name
export USER_TOKEN=$( \
    KUBECONFIG="${CREDENTIALS_DIR}/kubeconfig-aux-svc.yaml" "gitea/admin/create-cmd-access-token.sh" "${USER_NAME}" "${USER_TOKEN_NAME}" | \
    grep 'Access token was successfully created' | \
    cut -d ' ' -f 6 \
)
```

Add public SSH key:

```bash
# PARAMETERS:
# ==========
# 1) Server URL
# 2) Username
# 3) Token
# 4) SSH key content
# 5) SSH key name in Gitea's user profile
# 6) Read only?
KUBECONFIG="${CREDENTIALS_DIR}/kubeconfig-aux-svc.yaml" "gitea/admin/create-user-ssh-key.sh" \
  "${GITEA_HTTP_URL}" \
  "${USER_NAME}" \
  "${USER_TOKEN}" \
  "$(<${HOME}/.ssh/id_rsa.pub)" \
  "local_user_ssh_key" \
  false
```

Add user as collaborator of the relevant repos:

```bash
# Fleet repo
KUBECONFIG="${CREDENTIALS_DIR}/kubeconfig-aux-svc.yaml" "gitea/admin/add-collaborator-to-user-repo.sh" \
  "${GITEA_HTTP_URL}" \
  "${GITEA_STD_USERNAME}" \
  "${GITEA_STD_TOKEN}" \
  "fleet-osm" \
  "${USER_NAME}" \
  "write"

# SW-Catalogs repo
KUBECONFIG="${CREDENTIALS_DIR}/kubeconfig-aux-svc.yaml" "gitea/admin/add-collaborator-to-user-repo.sh" \
  "${GITEA_HTTP_URL}" \
  "${GITEA_STD_USERNAME}" \
  "${GITEA_STD_TOKEN}" \
  "sw-catalogs-osm" \
  "${USER_NAME}" \
  "write"
```

Finally, clone both repos in a well-known location:

```bash
mkdir -p "${WORK_REPOS_DIR}"
export FLEET_REPO_DIR="${WORK_REPOS_DIR}/fleet-osm"
export SW_CATALOGS_REPO_DIR="${WORK_REPOS_DIR}/sw-catalogs-osm"

# git@<GITEA_SSH_URL>:osm-developer/fleet-osm.git
git clone ${GITEA_SSH_URL}/${GITEA_STD_USERNAME}/fleet-osm.git "${FLEET_REPO_DIR}"

# git@<GITEA_SSH_URL>:osm-developer/sw-catalogs-osm.git
git clone ${GITEA_SSH_URL}/${GITEA_STD_USERNAME}/sw-catalogs-osm.git "${SW_CATALOGS_REPO_DIR}"

# Forces main instead of master
pushd "${SW_CATALOGS_REPO_DIR}"
# git branch -m master main
git symbolic-ref HEAD refs/heads/main
popd
```

#### 2.3.2 Bootstrap

Now we can run a regular Flux bootstrap (without encryption):

```bash
# Regular bootstrap
REPO=fleet-osm
GIT_PATH=./clusters/_management
GIT_BRANCH=main
GIT_HTTP_URL=${GITEA_HTTP_URL}/${GITEA_STD_USERNAME}/${REPO}.git
flux bootstrap git \
    --url=${GIT_HTTP_URL} \
    --allow-insecure-http=true \
    --username=${GITEA_STD_USERNAME} \
    --password="${GITEA_STD_USER_PASS}" \
    --token-auth=true \
    --branch=${GIT_BRANCH} \
    --path=${GIT_PATH}

# (optional) Check if successful
flux check
```

Once completed the bootstrap, we will pull the latest changes from the `fleet` repo so that we can work conveniently:

```bash
git -C "${FLEET_REPO_DIR}" pull
```

#### 2.3.3 SOPS setup

Create a new `age` key pair for the management cluster:

```bash
# Create private key and extract public key
export AGE_KEY_NAME_MGMT=age.mgmt
rm "${CREDENTIALS_DIR}/${AGE_KEY_NAME_MGMT}.key" "${CREDENTIALS_DIR}/${AGE_KEY_NAME_MGMT}.pub"
age-keygen -o "${CREDENTIALS_DIR}/${AGE_KEY_NAME_MGMT}.key"
age-keygen -y "${CREDENTIALS_DIR}/${AGE_KEY_NAME_MGMT}.key" > "${CREDENTIALS_DIR}/${AGE_KEY_NAME_MGMT}.pub"

# Save the contents in environment variables for easier consumption
export PRIVATE_KEY_MGMT=$(<"${CREDENTIALS_DIR}/${AGE_KEY_NAME_MGMT}.key")
export PUBLIC_KEY_MGMT=$(<"${CREDENTIALS_DIR}/${AGE_KEY_NAME_MGMT}.pub")
echo "${PRIVATE_KEY_MGMT}"
echo "${PUBLIC_KEY_MGMT}"
```

Add the `age` private key to the cluster as secret:

```bash
cat "${CREDENTIALS_DIR}/${AGE_KEY_NAME_MGMT}.key" |
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/dev/stdin
```

Create SOPS configuration at the root folder of the management cluster:

```bash
cat <<EOF > "${FLEET_REPO_DIR}/clusters/_management/.sops.yaml"
creation_rules:
  - encrypted_regex: ^(data|stringData)$
    age: ${PUBLIC_KEY_MGMT}
  # - path_regex: .*.yaml
  #   encrypted_regex: ^(data|stringData)$
  #   age: ${PUBLIC_KEY_MGMT}
EOF
```

(optional) Add also the public key to the repository so that others who clone the repo can encrypt new files:

```bash
cp "${CREDENTIALS_DIR}/${AGE_KEY_NAME_MGMT}.pub" "${FLEET_REPO_DIR}/clusters/_management/.sops.pub.asc"
```

#### 2.3.4 Base folder structure and profile kustomizations

Create the base folder structure + all profile folders for the management cluster:

```bash
# Name of the project for the OSM administrator
export MGMT_PROJECT_NAME="osm_admin"

# Creates all possible profile folders (as well as env var aliases)
export MGMT_ADDON_CTRL_DIR="${FLEET_REPO_DIR}/${MGMT_PROJECT_NAME}/infra-controller-profiles/_management"
export MGMT_ADDON_CONFIG_DIR="${FLEET_REPO_DIR}/${MGMT_PROJECT_NAME}/infra-config-profiles/_management"
export MGMT_RESOURCES_DIR="${FLEET_REPO_DIR}/${MGMT_PROJECT_NAME}/managed-resources/_management"
export MGMT_APPS_DIR="${FLEET_REPO_DIR}/${MGMT_PROJECT_NAME}/app-profiles/_management"
mkdir -p "${MGMT_ADDON_CTRL_DIR}"
mkdir -p "${MGMT_ADDON_CONFIG_DIR}"
mkdir -p "${MGMT_RESOURCES_DIR}"
mkdir -p "${MGMT_APPS_DIR}"

# Copies the templates for management cluster setup
export TEMPLATES_DIR="flux/templates"
export TEMPLATES_DIR=$(readlink -f "${TEMPLATES_DIR}")
export MGMT_CLUSTER_DIR="${FLEET_REPO_DIR}/clusters/_management"
cp "${TEMPLATES_DIR}/fleet/clusters/_management"/* "${MGMT_CLUSTER_DIR}/"
```

Overrides the Git repo references and adds their secrets as needed (**NOTE:** these are the last secrets to be added imperatively):

```bash
# Repo URLs
export FLEET_REPO_URL="${GITEA_HTTP_URL}/${GITEA_STD_USERNAME}/fleet-osm.git"
export SW_CATALOGS_REPO_URL="${GITEA_HTTP_URL}/${GITEA_STD_USERNAME}/sw-catalogs-osm.git"
export INFRA_CONTROLLERS_PATH="./${MGMT_PROJECT_NAME}/infra-controller-profiles/_management"
export INFRA_CONFIGS_PATH="./${MGMT_PROJECT_NAME}/infra-config-profiles/_management"
export MANAGED_RESOURCES_PATH="./${MGMT_PROJECT_NAME}/managed-resources/_management"
export APPS_PATH="./${MGMT_PROJECT_NAME}/app-profiles/_management"

# Fleet repo
envsubst < "${TEMPLATES_DIR}/fleet/clusters/_management/fleet-repo.yaml" > "${MGMT_CLUSTER_DIR}/fleet-repo.yaml"

# SW-Catalogs repo
envsubst < "${TEMPLATES_DIR}/fleet/clusters/_management/sw-catalogs-repo.yaml" > "${MGMT_CLUSTER_DIR}/sw-catalogs-repo.yaml"

# Secrets to access both Git repos
kubectl create secret generic fleet-repo \
    --namespace flux-system \
    --from-literal=username="${GITEA_STD_USERNAME}" \
    --from-literal=password="${GITEA_STD_USER_PASS}"

kubectl create secret generic sw-catalogs \
    --namespace flux-system \
    --from-literal=username="${GITEA_STD_USERNAME}" \
    --from-literal=password="${GITEA_STD_USER_PASS}"

# Kustomization to sync infra controllers profile
envsubst < "${TEMPLATES_DIR}/fleet/clusters/_management/infra-controllers.yaml" > "${MGMT_CLUSTER_DIR}/infra-controllers.yaml"

# Kustomization to sync infra configs profile
envsubst < "${TEMPLATES_DIR}/fleet/clusters/_management/infra-configs.yaml" > "${MGMT_CLUSTER_DIR}/infra-configs.yaml"

# Kustomization to sync managed resources profile
envsubst < "${TEMPLATES_DIR}/fleet/clusters/_management/managed-resources.yaml" > "${MGMT_CLUSTER_DIR}/managed-resources.yaml"

# Kustomization to sync apps profile
envsubst < "${TEMPLATES_DIR}/fleet/clusters/_management/apps.yaml" > "${MGMT_CLUSTER_DIR}/apps.yaml"
```

Create `ConfigMap` into profiles (and `Namespace` specs when needed) to avoid sync errors:

```bash
# Helper functions to create the profile ConfigMaps
function safe_name() {
  echo "$1" | \
    sed '/\.\// s|./||' | \
    sed 's|\.|-|g' | \
    sed 's|/|-|g' | \
    sed 's|_|-|g' | \
    sed 's| |-|g'
}

function create_profile_configmap() {
  local CONFIGMAP_NAME=$(safe_name "$1")
  local PROFILE_REPO_URL="$2"
  local PROFILE_PATH="$3"
  kubectl create configmap ${CONFIGMAP_NAME} \
    --namespace flux-system \
    --from-literal=repo="${PROFILE_REPO_URL}" \
    --from-literal=path="${PROFILE_PATH}" \
    -o yaml \
    --dry-run=client
}

# Infra controllers ConfigMap
# Same name as the corresponding kustomization name
CONFIGMAP_NAME="infra-controllers"
PROFILE_REPO_URL="${FLEET_REPO_URL}"
PROFILE_PATH="${INFRA_CONTROLLERS_PATH}"
create_profile_configmap \
  "${CONFIGMAP_NAME}" \
  "${PROFILE_REPO_URL}" \
  "${PROFILE_PATH}" \
  > "${MGMT_ADDON_CTRL_DIR}/profile-configmap.yaml"

# Infra configurations ConfigMap
CONFIGMAP_NAME="infra-configs"
PROFILE_REPO_URL="${FLEET_REPO_URL}"
PROFILE_PATH="${INFRA_CONFIGS_PATH}"
create_profile_configmap \
  "${CONFIGMAP_NAME}" \
  "${PROFILE_REPO_URL}" \
  "${PROFILE_PATH}" \
  > "${MGMT_ADDON_CONFIG_DIR}/profile-configmap.yaml"

# Managed resources ConfigMap
CONFIGMAP_NAME="managed-resources"
PROFILE_REPO_URL="${FLEET_REPO_URL}"
PROFILE_PATH="${MANAGED_RESOURCES_PATH}"
create_profile_configmap \
  "${CONFIGMAP_NAME}" \
  "${PROFILE_REPO_URL}" \
  "${PROFILE_PATH}" \
  > "${MGMT_RESOURCES_DIR}/profile-configmap.yaml"

# Managed resources namespace
kubectl create ns ${CONFIGMAP_NAME} \
    -o yaml     --dry-run=client \
    > "${MGMT_RESOURCES_DIR}/namespace.yaml"

# Apps ConfigMap
CONFIGMAP_NAME="apps"
PROFILE_REPO_URL="${FLEET_REPO_URL}"
PROFILE_PATH="${APPS_PATH}"
create_profile_configmap \
  "${CONFIGMAP_NAME}" \
  "${PROFILE_REPO_URL}" \
  "${PROFILE_PATH}" \
  > "${MGMT_APPS_DIR}/profile-configmap.yaml"
```

#### 2.3.5 Push to Git to update management cluster

Push to Git all new manifests:

```bash
pushd "${FLEET_REPO_DIR}"
git status
git add -A
git commit -m "Full profile structure after bootstrap + SOPS config"
git push
popd
```

(optional) Watch sync progress:

```bash
./flux/scripts/watch-mgmt-cluster.sh
```

#### 2.3.6 (optional) Test the creation of secrets using SOPS encryption

```bash
# Helper function to in-place encrypt secrets in manifest
function encrypt_secret_inplace() {
  local FILE="$1"

  sops \
    --age=${PUBLIC_KEY_MGMT} \
    --encrypt \
    --encrypted-regex '^(data|stringData)$' \
    --in-place "${FILE}"
}

# Creates a secret and encrypts it with age
SECRET_NAME="prueba"
kubectl create secret generic "${SECRET_NAME}" \
  --namespace managed-resources \
  --from-literal=foo=bar \
  -o yaml --dry-run=client | tee "${MGMT_RESOURCES_DIR}/secret-${SECRET_NAME}.yaml"
encrypt_secret_inplace "${MGMT_RESOURCES_DIR}/secret-${SECRET_NAME}.yaml"

# (Optional) View the secret manifest once encrypted
cat "${MGMT_RESOURCES_DIR}/secret-${SECRET_NAME}.yaml"
```

Push the new manifest:

```bash
pushd "${FLEET_REPO_DIR}"
git status
git add -A
git commit -m "Test of encrypted secret"
git push
popd
```

Check that the secret was successfully decrypted by Flux and created properly:

```bash
kubectl get secret ${SECRET_NAME} -n managed-resources -o yaml
kubectl get secret ${SECRET_NAME} -n managed-resources -o jsonpath='{.data.foo}' | base64 -d
```

Cleanup:

```bash
rm "${MGMT_RESOURCES_DIR}/secret-${SECRET_NAME}.yaml"

pushd "${FLEET_REPO_DIR}"
git status
git add -A
git commit -m "Cleanup: Remove test secret"
git push
popd
```

After a while it should be deleted:

```bash
watch kubectl get secret ${SECRET_NAME} -n managed-resources
```

#### 2.3.7 Add required operators and CRDs

First, we populate the SW-Catalogs repo:

```bash
rsync -varhP "${TEMPLATES_DIR}/sw-catalogs/" "${SW_CATALOGS_REPO_DIR}/"

pushd "${SW_CATALOGS_REPO_DIR}"
git status
git add -A
git commit -m "Sync from sw-catalogs template"
git push -u origin main
popd
```

Add the CrossPlane controller:

```bash
PACKAGE="${SW_CATALOGS_REPO_DIR}/infra-controllers/crossplane/controller"
cp "${PACKAGE}/templates"/* "${MGMT_ADDON_CTRL_DIR}/"
```

Add the CrossPlane providers:

```bash
# Azure providers
PACKAGE="${SW_CATALOGS_REPO_DIR}/infra-controllers/crossplane/providers/azure"
cp "${PACKAGE}/templates"/* "${MGMT_ADDON_CTRL_DIR}/"

# GCP providers
PACKAGE="${SW_CATALOGS_REPO_DIR}/infra-controllers/crossplane/providers/gcp"
cp "${PACKAGE}/templates"/* "${MGMT_ADDON_CTRL_DIR}/"

# TODO: AWS providers
```

Add the Argo WorkFlows controller:

```bash
PACKAGE="${SW_CATALOGS_REPO_DIR}/infra-controllers/argo-workflows"
cp "${PACKAGE}/templates"/* "${MGMT_ADDON_CTRL_DIR}/"
```

Push all changes to the fleet repo:

```bash
pushd "${FLEET_REPO_DIR}"
git status
git add -A
git commit -m "Install base controllers and CRDs into mgmt cluster"
git push -u origin main
popd
```

(optional) Checks:

```bash
# Check the health of Crossplane providers
kubectl get providers.pkg.crossplane.io
kubectl get crd | grep upbound
# kubectl get crd | grep azure
# kubectl get crd | grep gcp

# Check the availability of Argo WorkFlows
kubectl port-forward deployment/argo-server -n argo 2746:2746
# <https://localhost:2746>
```
