#!/bin/bash
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

set -e

export HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
source "${HERE}/library/functions.sh"
source "${HERE}/library/trap.sh"

############################################
# Main script starts here
############################################

# If there is no Ingress Controller, returns
if [[ -z $(kubectl get svc/ingress-nginx-controller -n ingress-nginx 2> /dev/null) ]]
then
    echo "No Ingress controller installed. Exiting"
    exit 1
fi

# Retrieve ports
export MINIO_CONSOLE_HTTP_PORT=$(kubectl get svc/console -n minio-operator -o jsonpath='{.spec.ports[?(.name=="http")].port}')
export MINIO_CONSOLE_HTTPS_PORT=$(kubectl get svc/console -n minio-operator -o jsonpath='{.spec.ports[?(.name=="https")].port}')
export MINIO_TENANT_HTTPS_PORT=$(kubectl get svc/minio -n ${MINIO_TENANT_NAME} -o jsonpath='{.spec.ports[?(.name=="https-minio")].port}')

# Determine Ingress host names
INGRESS_IP=$(kubectl get svc/ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export MINIO_INGRESS_CONSOLE_HOST="console.s3.${INGRESS_IP}.nip.io"
export MINIO_INGRESS_TENANT_HOST="${MINIO_TENANT_NAME}.s3.${INGRESS_IP}.nip.io"

# Determine locations of TLS certificates for tenant's endpoint, if applicable
export MINIO_TENANT_TLS_KEY="${CREDENTIALS_DIR}/tls.${MINIO_TENANT_NAME}.key"
export MINIO_TENANT_TLS_CERT="${CREDENTIALS_DIR}/tls.${MINIO_TENANT_NAME}.cert"

# If applicable, deploy Ingress to access Minio Console from outside
if [[ "${MINIO_EXPOSE_CONSOLE}" == "true" ]]
then
    m "\nDeploying Ingress for Console..."
    envsubst < ingress-manifests/console/ingress-console.yaml | \
        kubectl apply -f -
fi

# If applicable, deploy Ingress to access the Minio Tenant from outside
if [[ "${MINIO_EXPOSE_TENANT}" == "true" ]]
then
    m "\nDeploying Ingress for ${MINIO_TENANT_NAME} tenant..."

    # Create self-signed certificate (comment if using pre-created certificate)
    openssl req -x509 \
        -nodes \
        -days 365 \
        -newkey rsa:2048 \
        -keyout "${MINIO_TENANT_TLS_KEY}" \
        -out "${MINIO_TENANT_TLS_CERT}" \
        -subj "/CN=${MINIO_INGRESS_TENANT_HOST}/O=${MINIO_INGRESS_TENANT_HOST}" \
        -addext "subjectAltName = DNS:${MINIO_INGRESS_TENANT_HOST}"

    kubectl create secret tls nginx-tls \
        --key "${MINIO_TENANT_TLS_KEY}" \
        --cert "${MINIO_TENANT_TLS_CERT}" \
        -n ${MINIO_TENANT_NAME}

    envsubst < ingress-manifests/tenant/ingress-tenant.yaml | \
        kubectl apply -f -

    echo "${MINIO_TENANT_NAME} tenant exposed at https://${MINIO_INGRESS_TENANT_HOST}"
fi
