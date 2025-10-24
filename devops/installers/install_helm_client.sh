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

HELM_VERSION="v3.15.1"

#Install Helm v3
#Helm releases can be found here: https://github.com/helm/helm/releases
function install_helm_client() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    if ! [[ "$(helm version --short 2>/dev/null)" =~ ^v3.* ]]; then
        # Helm is not installed. Install helm
        echo "Helm3 is not installed, installing ..."
        curl https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz --output helm-${HELM_VERSION}.tar.gz
        tar -zxvf helm-${HELM_VERSION}.tar.gz
        sudo mv linux-amd64/helm /usr/local/bin/helm
        rm -r linux-amd64
        rm helm-${HELM_VERSION}.tar.gz
    else
        echo "Helm3 is already installed. Skipping installation..."
    fi
    helm version || FATAL_TRACK k8scluster "Could not obtain helm version. Maybe helm client was not installed"
    helm repo add stable https://charts.helm.sh/stable || FATAL_TRACK k8scluster "Helm repo stable could not be added"
    helm repo update || FATAL_TRACK k8scluster "Helm repo stable could not be updated"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# main
while getopts ":D:-: " o; do
    case "${o}" in
        D)
            OSM_DEVOPS="${OPTARG}"
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
OSM_DEVOPS=${OSM_DEVOPS:-}
echo "DEBUG_INSTALL=$DEBUG_INSTALL"
echo "OSM_DEVOPS=$OSM_DEVOPS"

source $OSM_DEVOPS/common/logging
source $OSM_DEVOPS/common/track

install_helm_client
