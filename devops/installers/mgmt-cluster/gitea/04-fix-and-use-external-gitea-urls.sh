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

# If there are no external IP addresses, exits
# [[ -z $(kubectl get svc/gitea-http -n gitea -o jsonpath='{.status.loadBalancer.ingress[0].ip}') ]] && exit 0

# Update the server base URLs, based on the exposed IP address(es)
m "Updating base URLs in the server to use external IP address(es)..."
helm upgrade --install gitea gitea-charts/gitea \
    --version=7.0.4 \
    --namespace=gitea \
    --values "${HERE}/${GITEA_CHART_VALUES_FILE}" \
    --set=gitea.admin.username="${GITEA_ADMINISTRATOR_USERNAME}" \
    --set=gitea.admin.password="${GITEA_ADMINISTRATOR_PASSWORD@Q}" \
    --set=gitea.config.server.DOMAIN="${GITEA_SSH_SERVER}" \
    --set=gitea.config.server.ROOT_URL="${GITEA_HTTP_URL}" \
    --set=ingress.hosts[0].host="${GITEA_HTTP_HOST_DOMAIN}" \
    --wait
