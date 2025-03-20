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

# Complete environment variables with sensible defaults, if needed
source 00-base-config.rc

# Install Minio operator
./01-deploy-minio-operator.sh

# Create Minio tenant
./02-create-minio-tenant.sh

# If applicable, deploy Ingress to provide external access
./03-deploy-ingress-for-minio.sh

# Retrieve URLs and credentials
source 04-get-minio-connection-info.rc

# Save credentials
./05-export-connection-info.sh
