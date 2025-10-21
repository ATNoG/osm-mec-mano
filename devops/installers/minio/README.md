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
# How to install Minio

- [How to install Minio](#how-to-install-minio)
  - [0. Pre-requirements](#0-pre-requirements)
  - [1. Installation](#1-installation)
    - [1.1 Quickstart (recommended)](#11-quickstart-recommended)
    - [1.2 Detailed procedure (useful for regenerating manifests with newer versions)](#12-detailed-procedure-useful-for-regenerating-manifests-with-newer-versions)
    - [1.2.1 Minio Operator](#121-minio-operator)
    - [2.1.2 Create a Minio Tenant](#212-create-a-minio-tenant)
  - [3. Tests](#3-tests)
    - [3.1 Access using Ingress (recommended)](#31-access-using-ingress-recommended)
    - [3.2 Access using a port forward](#32-access-using-a-port-forward)
    - [3.3 Tests from a container into the K8s cluster](#33-tests-from-a-container-into-the-k8s-cluster)
  - [ANNEX A: How to set-up the local Minio CLI tools](#annex-a-how-to-set-up-the-local-minio-cli-tools)

This procedure is based in the [Minio Operator guide](https://github.com/minio/operator/blob/master/README.md) and the [Guide to deploy a Deploy a MinIO Tenant](https://min.io/docs/minio/kubernetes/upstream/operations/install-deploy-manage/deploy-minio-tenant.html).

## 0. Pre-requirements

- Kubernetes cluster available.
- Minio's `kubectl` plugin.
- `mc` (Minio Client) tool installed.
  - We will assume that the tool is renamed as `minioc` to avoid collisions with a pre-existing installation of the popular _Midnight Commander_.
  - We will use the tool to validate that the installation has been successful.

## 1. Installation

### 1.1 Quickstart (recommended)

```bash
./ALL-IN-ONE-Minio-install.sh

# (optional) To retrieve the environment variables
source 00-base-config.rc
source "${CREDENTIALS_DIR}/minio_environment.rc"
```

### 1.2 Detailed procedure (useful for regenerating manifests with newer versions)

### 1.2.1 Minio Operator

```bash
VERSION=v5.0.11
TIMEOUT=120 # By default is 27. Since sometimes connection may be slow, here we allow more time.
kustomize build "github.com/minio/operator/resources/?timeout=${TIMEOUT}&ref=${VERSION}" > minio-operator.yaml

# (optional) To allow deployments over single-node clusters
yq -i 'del(.spec.template.spec.affinity)' minio-operator.yaml

# Deploy
kubectl apply -f minio-operator.yaml

# Wait until completion
kubectl rollout status deploy/minio-operator --namespace=minio-operator --watch --timeout=1h
```

Save SA token:

```bash
export MINIO_SA_TOKEN=$(kubectl -n minio-operator  get secret console-sa-secret -o jsonpath="{.data.token}" | base64 -d)
```

### 2.1.2 Create a Minio Tenant

Deploy a tenant for OSM:

```bash
MINIO_TENANT_NAME=minio-osm-tenant
MINIO_TENANT_CAPACITY=10Gi
kubectl create ns ${MINIO_TENANT_NAME}
kubectl minio tenant create                     \
    ${MINIO_TENANT_NAME}                        \
    --servers          4                        \
    --volumes          8                        \
    --capacity         ${MINIO_TENANT_CAPACITY} \
    --namespace        ${MINIO_TENANT_NAME}     \
    --storage-class    default                  \
    --output > ${MINIO_TENANT_NAME}.yaml

# Fix malformed manifest with wrong fields
yq -i 'del(.spec.pools[0].volumeClaimTemplate.metadata.creationTimestamp)' ${MINIO_TENANT_NAME}.yaml

kubectl apply -f ${MINIO_TENANT_NAME}.yaml
```

Save credentials:

```bash
export MINIO_OSM_USERNAME=$(kubectl get secret ${MINIO_TENANT_NAME}-user-1 -n ${MINIO_TENANT_NAME} -o jsonpath='{.data.CONSOLE_ACCESS_KEY}' | base64 -d)
export MINIO_OSM_PASSWORD=$(kubectl get secret ${MINIO_TENANT_NAME}-user-1 -n ${MINIO_TENANT_NAME} -o jsonpath='{.data.CONSOLE_SECRET_KEY}' | base64 -d)
```

## 3. Tests

### 3.1 Access using Ingress (recommended)

Get the URL and the JWT token to access the Minio Operator Console with the browser:

```bash
# Open URL in browser using the JWT as access token
echo "Console URL: ${MINIO_CONSOLE_URL}"
echo -e "JWT token:\n${MINIO_SA_TOKEN}"
```

Then we can also test the tenant:

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

Note the use of the `--insecure` when the endpoint certificate is self-signed. **This will not be an issue from a container inside the cluster (using the internal DNS name) or when the certificate is signed by a CA**.

### 3.2 Access using a port forward

Access the Minio Operator Console:

```bash
# See SA Token, so that it can be used as JWT to access the Operator Console
echo ${MINIO_SA_TOKEN}

# Port forward to access from outside K8s
kubectl port-forward svc/console -n minio-operator 9090:9090

# Open in browser: http://localhost:9090
```

The we can test the health of the Minio tenant. First, we need to forward the port:

```bash
# Port forward to access from outside K8s
kubectl port-forward svc/minio -n ${MINIO_TENANT_NAME} 4443:443
```

Then we test the tenant:

```bash
# Add alias to connect to the tenant
ALIAS=osm
MINIO_HOSTNAME=https://localhost:4443
ACCESS_KEY=${MINIO_OSM_USERNAME}
SECRET_KEY=${MINIO_OSM_PASSWORD}
minioc alias set ${ALIAS} ${MINIO_HOSTNAME} ${ACCESS_KEY} ${SECRET_KEY} --insecure

# Test
minioc admin info ${ALIAS} --insecure

# (optional) Delete the alias
minioc alias remove ${ALIAS}
```

Note the use of the `--insecure`, since the endpoint certificate is not valid for a `localhost` endpoint. **This will not be an issue from a container inside the cluster**.

### 3.3 Tests from a container into the K8s cluster

Launch the container:

```bash
kubectl run -it --rm --image=alpine --env=ACCESS_KEY=${MINIO_OSM_USERNAME} --env=SECRET_KEY=${MINIO_OSM_PASSWORD} -- sh
```

Into the container:

```bash
# Install Minio client into the container
apk add curl
curl https://dl.min.io/client/mc/release/linux-amd64/mc -o minioc
chmod +x minioc
mv minioc /usr/local/bin/

# Add alias to connect to the tenant
ALIAS=osm
MINIO_TENANT_NAME=minio-osm-tenant
MINIO_HOSTNAME=https://minio.${MINIO_TENANT_NAME}
minioc alias set ${ALIAS} ${MINIO_HOSTNAME} ${ACCESS_KEY} ${SECRET_KEY}

# Test
minioc admin info ${ALIAS}
```

## ANNEX A: How to set-up the local Minio CLI tools

```bash
# Minio kubectl plugin:
curl https://github.com/minio/operator/releases/download/v5.0.12/kubectl-minio_5.0.12_linux_amd64 -Lo kubectl-minio
chmod +x kubectl-minio
sudo mv kubectl-minio /usr/local/bin/

# Minio Client:
curl https://dl.min.io/client/mc/release/linux-amd64/mc -o minioc
chmod +x minioc
sudo mv minioc /usr/local/bin/
```
