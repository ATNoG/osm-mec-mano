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

set +eux

# Helm chart 1.6.0 correspondes to Airflow 2.3.0
AIRFLOW_HELM_VERSION=1.9.0

# Install Airflow helm chart
function install_airflow() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    # copy airflow-values.yaml to the destination folder
    sudo mkdir -p ${OSM_HELM_WORK_DIR}
    sudo cp ${OSM_DEVOPS}/installers/helm/values/airflow-values.yaml ${OSM_HELM_WORK_DIR}
    # update airflow-values.yaml to use the right tag
    echo "Updating Helm values file helm/values/airflow-values.yaml to use defaultAirflowTag: ${OSM_DOCKER_TAG}"
    sudo sed -i "s#defaultAirflowTag:.*#defaultAirflowTag: \"${OSM_DOCKER_TAG}\"#g" ${OSM_HELM_WORK_DIR}/airflow-values.yaml
    echo "Updating Helm values file helm/values/airflow-values.yaml to use defaultAirflowRepository: ${DOCKER_REGISTRY_URL}${DOCKER_USER}/airflow"
    sudo sed -i "s#defaultAirflowRepository:.*#defaultAirflowRepository: ${DOCKER_REGISTRY_URL}${DOCKER_USER}/airflow#g" ${OSM_HELM_WORK_DIR}/airflow-values.yaml
    echo "Updating Helm values file helm/values/airflow-values.yaml to set ingress.web.hosts with host \"airflow.${DEFAULT_IP}.nip.io\""
    sudo sed -i "s#name: \"localhost\"#name: \"airflow.${DEFAULT_IP}.nip.io\"#g" ${OSM_HELM_WORK_DIR}/airflow-values.yaml

    helm repo add apache-airflow https://airflow.apache.org
    helm repo update
    helm upgrade airflow apache-airflow/airflow -n ${OSM_NAMESPACE} --create-namespace --install -f ${OSM_HELM_WORK_DIR}/airflow-values.yaml --version ${AIRFLOW_HELM_VERSION} --timeout 10m || FATAL_TRACK ngsa "Failed installing airflow helm chart"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# main
while getopts ":D:d:i:s:t:r:U:-: " o; do
    case "${o}" in
        i)
            DEFAULT_IP="${OPTARG}"
            ;;
        D)
            OSM_DEVOPS="${OPTARG}"
            ;;
        d)
            OSM_HELM_WORK_DIR="${OPTARG}"
            ;;
        s)
            OSM_NAMESPACE="${OPTARG}"
            ;;
        t)
            OSM_DOCKER_TAG="${OPTARG}"
            ;;
        r)
            DOCKER_REGISTRY_URL="${OPTARG}"
            ;;
        U)
            DOCKER_USER="${OPTARG}"
            ;;
        -)
            [ "${OPTARG}" == "debug" ] && DEBUG_INSTALL="y" && continue
            echo -e "Invalid option: '--$OPTARG'\n" >&2
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument" >&2
            exit 1
            ;;
        \?)
            echo -e "Invalid option: '-$OPTARG'\n" >&2
            exit 1
            ;;
        *)
            exit 1
            ;;
    esac
done

DEBUG_INSTALL=${DEBUG_INSTALL:-}
DEFAULT_IP=${DEFAULT_IP:-"127.0.0.1"}
OSM_DEVOPS=${OSM_DEVOPS:-"/usr/share/osm-devops"}
OSM_DOCKER_TAG=${OSM_DOCKER_TAG:-"testing-daily"}
OSM_HELM_WORK_DIR=${OSM_HELM_WORK_DIR:-"/etc/osm/helm"}
OSM_NAMESPACE=${OSM_NAMESPACE:-"osm"}
DOCKER_REGISTRY_URL=${DOCKER_REGISTRY_URL:-}
DOCKER_USER=${DOCKER_USER:-"opensourcemano"}
echo "DEBUG_INSTALL=$DEBUG_INSTALL"
echo "DEFAULT_IP=$DEFAULT_IP"
echo "OSM_DEVOPS=$OSM_DEVOPS"
echo "OSM_DOCKER_TAG=$OSM_DOCKER_TAG"
echo "OSM_HELM_WORK_DIR=$OSM_HELM_WORK_DIR"
echo "OSM_NAMESPACE=$OSM_NAMESPACE"
echo "DOCKER_REGISTRY_URL=$DOCKER_REGISTRY_URL"
echo "DOCKER_USER=$DOCKER_USER"

source $OSM_DEVOPS/common/logging
source $OSM_DEVOPS/common/track

install_airflow
track deploy_osm airflow_ok
