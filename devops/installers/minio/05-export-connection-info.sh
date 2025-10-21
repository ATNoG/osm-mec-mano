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

# In case no argument is passed, takes the value of the environment variable
MINIO_TENANT_NAME=${1:-${MINIO_TENANT_NAME}}

m "\nSaving Minio enviroment to credentials folder..."

# Loads credentials into environment variables
export MINIO_SA_TOKEN=$(kubectl -n minio-operator get secret console-sa-secret -o jsonpath="{.data.token}" | base64 -d)
export MINIO_OSM_USERNAME=$(kubectl get secret ${MINIO_TENANT_NAME}-user-1 -n ${MINIO_TENANT_NAME} -o jsonpath='{.data.CONSOLE_ACCESS_KEY}' | base64 -d)
export MINIO_OSM_PASSWORD=$(kubectl get secret ${MINIO_TENANT_NAME}-user-1 -n ${MINIO_TENANT_NAME} -o jsonpath='{.data.CONSOLE_SECRET_KEY}' | base64 -d)

# Grants that all environment variables are defined
export MINIO_INGRESS_CONSOLE_HOST=${MINIO_INGRESS_CONSOLE_HOST:-""}
export MINIO_INGRESS_TENANT_HOST=${MINIO_INGRESS_TENANT_HOST:-""}

# Saves locally to local environment at credentials folder
cat << EOF > "${CREDENTIALS_DIR}/minio_environment.rc"
# Minio credentials
export MINIO_SA_TOKEN=${MINIO_SA_TOKEN}
export MINIO_OSM_USERNAME=${MINIO_OSM_USERNAME}
export MINIO_OSM_PASSWORD='${MINIO_OSM_PASSWORD}'

# Minio Console endpoint(s)
export MINIO_CONSOLE_URL=${MINIO_CONSOLE_URL}
export MINIO_CONSOLE_HOST=${MINIO_CONSOLE_HOST}
export MINIO_INTERNAL_CONSOLE_HOST=${MINIO_INTERNAL_CONSOLE_HOST}
export MINIO_INGRESS_CONSOLE_HOST=${MINIO_INGRESS_CONSOLE_HOST}
export MINIO_CONSOLE_HTTP_PORT=${MINIO_CONSOLE_HTTP_PORT}
export MINIO_CONSOLE_HTTPS_PORT=${MINIO_CONSOLE_HTTPS_PORT}

# Minio tenant endpoint(s)
export MINIO_TENANT_URL=${MINIO_TENANT_URL}
export MINIO_TENANT_HOST=${MINIO_TENANT_HOST}
export MINIO_INTERNAL_TENANT_HOST=${MINIO_INTERNAL_TENANT_HOST}
export MINIO_INGRESS_TENANT_HOST=${MINIO_INGRESS_TENANT_HOST}
export MINIO_TENANT_HTTPS_PORT=${MINIO_TENANT_HTTPS_PORT}

# Location of certificate and key for Minio's tenant enpoint
export MINIO_TENANT_TLS_CERT='${MINIO_TENANT_TLS_CERT}'
export MINIO_TENANT_TLS_KEY='${MINIO_TENANT_TLS_KEY}'
EOF
