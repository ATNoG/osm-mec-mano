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
source "${CREDENTIALS_DIR}/git_environment.rc"

OSM_HELM_WORK_DIR="/etc/osm/helm"
KUBECONFIG_AUX_CLUSTER_FILE="${OSM_HOME_DIR}/clusters/kubeconfig-aux-svc.yaml"
KUBECONFIG_MGMT_CLUSTER_FILE="${OSM_HOME_DIR}/clusters/kubeconfig-mgmt.yaml"
[ "${HERE}" == "/usr/share/osm-devops/installers" ] || OSM_HELM_UPDATE_DEPENDENCIES="y"
OSM_GITOPS_ENABLED=${INSTALL_MGMT_CLUSTER:-"y"}

# TODO: move this to a parent script that creates the VM
mkdir -p "${OSM_HOME_DIR}/clusters"
if [ -n "${KUBECONFIG_OSM_CLUSTER}" ]; then
  cp "${KUBECONFIG_OSM_CLUSTER}" "${OSM_HOME_DIR}/clusters/kubeconfig-osm.yaml"
else
  cp "${HOME}/.kube/config" "${OSM_HOME_DIR}/clusters/kubeconfig-osm.yaml"
fi

export KUBECONFIG="${OSM_HOME_DIR}/clusters/kubeconfig-osm.yaml"
if [ -z "${OSM_BASE_DOMAIN}" ]; then
    echo "OSM_BASE_DOMAIN is not set, will try to set it from the nginx ingress controller load balancer IP"
    OSM_K8S_NGINX_IPADDRESS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    OSM_BASE_DOMAIN="${OSM_BASE_DOMAIN:-"${OSM_K8S_NGINX_IPADDRESS}.nip.io"}"
fi
echo "Using OSM_BASE_DOMAIN=${OSM_BASE_DOMAIN}"

# Create folder to store helm values
sudo mkdir -p ${OSM_HELM_WORK_DIR}

# Saving secrets
echo "Creating namespace ${OSM_NAMESPACE}"
kubectl get ns "${OSM_NAMESPACE}" >/dev/null 2>&1 || kubectl create ns "${OSM_NAMESPACE}"
echo "Saving age keys in OSM cluster"
kubectl -n ${OSM_NAMESPACE} get secret mgmt-cluster-age-keys >/dev/null 2>&1 || \
kubectl -n ${OSM_NAMESPACE} create secret generic mgmt-cluster-age-keys --from-file=privkey="${CREDENTIALS_DIR}/age.mgmt.key" --from-file=pubkey="${CREDENTIALS_DIR}/age.mgmt.pub"
echo "Creating secrets with kubeconfig files"
if [ -f "${KUBECONFIG_AUX_CLUSTER_FILE}" ]; then
    kubectl -n ${OSM_NAMESPACE} get secret auxcluster-secret >/dev/null 2>&1 || \
    kubectl -n ${OSM_NAMESPACE} create secret generic auxcluster-secret --from-file=kubeconfig="${KUBECONFIG_AUX_CLUSTER_FILE}"
fi
if [ -f "${KUBECONFIG_MGMT_CLUSTER_FILE}" ]; then
    kubectl -n ${OSM_NAMESPACE} get secret mgmtcluster-secret >/dev/null 2>&1 || \
    kubectl -n ${OSM_NAMESPACE} create secret generic mgmtcluster-secret --from-file=kubeconfig="${KUBECONFIG_MGMT_CLUSTER_FILE}"
fi
# Update helm dependencies
[ -n "${OSM_HELM_UPDATE_DEPENDENCIES}" ] && \
    echo "Updating helm dependencies" && \
    helm dependency update "${HERE}/helm/osm"

# Generate helm values to be passed with --set
OSM_HELM_OPTS=""
# OSM_HELM_OPTS="${OSM_HELM_OPTS} --set nbi.useOsmSecret=false"
[ -n "${OSM_HELM_TIMEOUT}" ] && OSM_HELM_OPTS="${OSM_HELM_OPTS} --timeout ${OSM_HELM_TIMEOUT}"

# TODO: review if next line is really needed or should be conditional to DOCKER_REGISTRY_URL not empty
# [ -n "${DOCKER_REGISTRY_URL}" ] && OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.image.repository=${DOCKER_REGISTRY_URL}${DOCKER_USER}"
OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.image.repositoryBase=${DOCKER_REGISTRY_URL}${DOCKER_USER}"
OSM_HELM_OPTS="${OSM_HELM_OPTS} --set airflow.defaultAirflowRepository=${DOCKER_REGISTRY_URL}${DOCKER_USER}/airflow"
[ ! "$OSM_DOCKER_TAG" == "testing-daily" ] && OSM_HELM_OPTS="${OSM_HELM_OPTS} --set-string global.image.tag=${OSM_DOCKER_TAG}"
[ ! "$OSM_DOCKER_TAG" == "testing-daily" ] && OSM_HELM_OPTS="${OSM_HELM_OPTS} --set-string airflow.defaultAirflowTag=${OSM_DOCKER_TAG}"
[ ! "$OSM_DOCKER_TAG" == "testing-daily" ] && OSM_HELM_OPTS="${OSM_HELM_OPTS} --set prometheus.server.sidecarContainers.prometheus-config-sidecar.image=${DOCKER_REGISTRY_URL}${DOCKER_USER}/prometheus:${OSM_DOCKER_TAG}"

OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.hostname=${OSM_BASE_DOMAIN}"
if [ -n "${OSM_CLUSTER_INGRESS_CLASS}" ]; then
    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.ingressClassName=${OSM_CLUSTER_INGRESS_CLASS}"
    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set grafana.ingress.ingressClassName=${OSM_CLUSTER_INGRESS_CLASS}"
    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set prometheus.server.ingress.ingressClassName=${OSM_CLUSTER_INGRESS_CLASS}"
    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set airflow.ingress.web.ingressClassName=${OSM_CLUSTER_INGRESS_CLASS}"
    # OSM_HELM_OPTS="${OSM_HELM_OPTS} --set prometheus.alertmanager.ingress.ingressClassName=${OSM_CLUSTER_INGRESS_CLASS}"
fi
OSM_HELM_OPTS="${OSM_HELM_OPTS} --set grafana.ingress.hosts={grafana.${OSM_BASE_DOMAIN}}"
OSM_HELM_OPTS="${OSM_HELM_OPTS} --set prometheus.server.ingress.hosts={prometheus.${OSM_BASE_DOMAIN}}"
OSM_HELM_OPTS="${OSM_HELM_OPTS} --set airflow.ingress.web.hosts={airflow.${OSM_BASE_DOMAIN}}"
# OSM_HELM_OPTS="${OSM_HELM_OPTS} --set prometheus.alertmanager.ingress.hosts={alertmanager.${OSM_BASE_DOMAIN}}"
if [ -z "${OSM_GITOPS_ENABLED}" ]; then
    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.gitops.enabled=false"
else
    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.gitops.gitBaseUrl=${GIT_BASE_HTTP_URL}"
    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.gitops.fleetRepoUrl=${FLEET_REPO_HTTP_URL}"
    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.gitops.swcatalogsRepoUrl=${SW_CATALOGS_REPO_HTTP_URL}"
    # TODO: evaluate if we need to set two git user names, one for fleet and one for sw-catalogs
    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.gitops.gitUser=${GIT_BASE_USERNAME}"
    AGE_MGMT_PUBKEY=$(tr -d '\n' < ${CREDENTIALS_DIR}/age.mgmt.pub)
    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.gitops.pubkey=${AGE_MGMT_PUBKEY}"
fi

if [ -n "${OSM_BEHIND_PROXY}" ]; then
    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.behindHttpProxy=true"
    [ -n "${HTTP_PROXY}" ] && OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.httpProxy.HTTP_PROXY=\"${HTTP_PROXY}\""
    [ -n "${HTTPS_PROXY}" ] && OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.httpProxy.HTTPS_PROXY=\"${HTTPS_PROXY}\""
    if [ -n "${NO_PROXY}" ]; then
        if [[ ! "${NO_PROXY}" =~ .*".svc".* ]]; then
            NO_PROXY="${NO_PROXY},.svc"
        fi
        if [[ ! "${NO_PROXY}" =~ .*".cluster.local".* ]]; then
            NO_PROXY="${NO_PROXY},.cluster.local"
        fi
        OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.httpProxy.NO_PROXY=\"${NO_PROXY//,/\,}\""
    fi
fi

# Dependency update before installing helm chart
echo "helm dependency update ${HERE}/helm/osm"
helm dependency update ${HERE}/helm/osm
# Deploy helm chart
echo "helm upgrade --install -n $OSM_NAMESPACE --create-namespace $OSM_HELM_RELEASE ${HERE}/helm/osm ${OSM_HELM_OPTS}"
helm upgrade --install -n $OSM_NAMESPACE --create-namespace $OSM_HELM_RELEASE ${HERE}/helm/osm ${OSM_HELM_OPTS}
# Override existing values.yaml with the final values.yaml used to install OSM
helm -n $OSM_NAMESPACE get values $OSM_HELM_RELEASE | sudo tee -a ${OSM_HELM_WORK_DIR}/osm-values.yaml

# Check OSM health state
echo -e "Checking OSM health state..."
set +e
${HERE}/45-osm-health.sh || \
(echo -e "OSM is not healthy, but will probably converge to a healthy state soon." && \
echo -e "Check OSM status with: kubectl -n ${OSM_NAMESPACE} get all" && \
track healthchecks osm_unhealthy didnotconverge)
track healthchecks after_healthcheck_ok
set -e

echo -e "Saving OSM enviroment to credentials folder..."
OSM_HOSTNAME=$(kubectl get --namespace osm -o jsonpath="{.spec.rules[0].host}" ingress nbi-ingress)
# OSM_HOSTNAME="nbi.${OSM_BASE_DOMAIN}:443"
echo -e "OSM HOSTNAME: ${OSM_HOSTNAME}"

cat << EOF > "${CREDENTIALS_DIR}/osm_environment.rc"
export OSM_HOSTNAME="${OSM_HOSTNAME}"
EOF
