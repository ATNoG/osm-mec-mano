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

# Helm chart 13.9.4 correspondes to Mongo DB 6.0.5
MONGODB_HELM_VERSION=13.9.4

# Install MongoDB  helm chart
function install_mongodb() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    # copy mongodb-values.yaml to the destination folder
    sudo mkdir -p ${OSM_HELM_WORK_DIR}
    sudo cp ${OSM_DEVOPS}/installers/helm/values/mongodb-values.yaml ${OSM_HELM_WORK_DIR}
    # update mongodb-values.yaml to use the right tag

    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo update
    helm upgrade mongodb-k8s bitnami/mongodb -n ${OSM_NAMESPACE} --create-namespace --install -f ${OSM_HELM_WORK_DIR}/mongodb-values.yaml --version ${MONGODB_HELM_VERSION} --timeout 10m || FATAL_TRACK mongodb "Failed installing mongodb helm chart"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# main
while getopts ":D:d:s:r:U:-: " o; do
    case "${o}" in
        D)
            OSM_DEVOPS="${OPTARG}"
            ;;
        d)
            OSM_HELM_WORK_DIR="${OPTARG}"
            ;;
        s)
            OSM_NAMESPACE="${OPTARG}"
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
OSM_DEVOPS=${OSM_DEVOPS:-"/usr/share/osm-devops"}
OSM_HELM_WORK_DIR=${OSM_HELM_WORK_DIR:-"/etc/osm/helm"}
OSM_NAMESPACE=${OSM_NAMESPACE:-"osm"}
DOCKER_REGISTRY_URL=${DOCKER_REGISTRY_URL:-}
DOCKER_USER=${DOCKER_USER:-"opensourcemano"}
echo "DEBUG_INSTALL=$DEBUG_INSTALL"
echo "OSM_DEVOPS=$OSM_DEVOPS"
echo "OSM_HELM_WORK_DIR=$OSM_HELM_WORK_DIR"
echo "OSM_NAMESPACE=$OSM_NAMESPACE"
echo "DOCKER_REGISTRY_URL=$DOCKER_REGISTRY_URL"
echo "DOCKER_USER=$DOCKER_USER"

source $OSM_DEVOPS/common/logging
source $OSM_DEVOPS/common/track

install_mongodb
