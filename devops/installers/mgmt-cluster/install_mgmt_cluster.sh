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

set -x

# main
while getopts ":D:d:G:M:-: " o; do
    case "${o}" in
        d)
            OSM_HOME_DIR="${OPTARG}"
            ;;
        D)
            OSM_DEVOPS="${OPTARG}"
            ;;
        M)
            KUBECONFIG_MGMT_CLUSTER="${OPTARG}"
            ;;
        G)
            KUBECONFIG_AUX_CLUSTER="${OPTARG}"
            ;;
        -)
            [ "${OPTARG}" == "debug" ] && DEBUG_INSTALL="y" && continue
            [ "${OPTARG}" == "no-mgmt-cluster" ] && INSTALL_MGMT_CLUSTER="" && continue
            [ "${OPTARG}" == "no-aux-cluster" ] && INSTALL_AUX_CLUSTER="" && continue
            [ "${OPTARG}" == "minio" ] && INSTALL_MINIO="y" && continue
            [ "${OPTARG}" == "no-minio" ] && INSTALL_MINIO="" && continue
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
OSM_HOME_DIR=${OSM_HOME_DIR:-"$HOME/.osm"}
OSM_MGMTCLUSTER_BASE_FOLDER="${OSM_DEVOPS}/installers/mgmt-cluster"
INSTALL_MGMT_CLUSTER=${INSTALL_MGMT_CLUSTER:-"y"}
INSTALL_AUX_CLUSTER=${INSTALL_AUX_CLUSTER:-"y"}
KUBECONFIG_MGMT_CLUSTER=${KUBECONFIG_MGMT_CLUSTER:-"$HOME/.kube/config"}
KUBECONFIG_AUX_CLUSTER=${KUBECONFIG_AUX_CLUSTER:-"$HOME/.kube/config"}
KUBECONFIG_OLD=${KUBECONFIG:-"$HOME/.kube/config"}
export CREDENTIALS_DIR="${OSM_HOME_DIR}/.credentials"
export WORK_REPOS_DIR="${OSM_HOME_DIR}/repos"
export INSTALL_MINIO=${INSTALL_MINIO:-"y"}
echo "DEBUG_INSTALL=$DEBUG_INSTALL"
echo "OSM_DEVOPS=$OSM_DEVOPS"
echo "OSM_HOME_DIR=$OSM_HOME_DIR"
echo "OSM_MGMTCLUSTER_BASE_FOLDER=$OSM_MGMTCLUSTER_BASE_FOLDER"
echo "INSTALL_MGMT_CLUSTER=$INSTALL_MGMT_CLUSTER"
echo "INSTALL_AUX_CLUSTER=$INSTALL_AUX_CLUSTER"
echo "KUBECONFIG_MGMT_CLUSTER=$KUBECONFIG_MGMT_CLUSTER"
echo "KUBECONFIG_AUX_CLUSTER=$KUBECONFIG_AUX_CLUSTER"
echo "CREDENTIALS_DIR=$CREDENTIALS_DIR"
echo "WORK_REPOS_DIR=$WORK_REPOS_DIR"

source $OSM_DEVOPS/common/logging
source $OSM_DEVOPS/common/track

pushd $OSM_MGMTCLUSTER_BASE_FOLDER

if [ -n "${INSTALL_AUX_CLUSTER}" ] || [ -n "${INSTALL_MGMT_CLUSTER}" ]; then

    echo "Setup CLI tools for mgmt and aux cluster"
    ./setup-cli-tools.sh || FATAL_TRACK mgmtcluster "setup-cli-tools.sh failed"
    track mgmtcluster setupclitools_ok

    echo "Creating folders under ${OSM_HOME_DIR} for credentials and repos"
    mkdir -p "${CREDENTIALS_DIR}"
    mkdir -p "${WORK_REPOS_DIR}"
    track mgmtcluster folders_ok

    # Test if the user exists. Otherwise, create a git user
    echo "Test if there is a git user. Otherwise, create it."
    if [ ! -n "$(git config user.name)" ]; then
        git config --global user.name osm_user
        git config --global user.email osm_user@mydomain.com
    fi

    # Test if the user exists. Otherwise, create a git user
    echo "Checking if the user has an SSH key pair"
    if [ ! -f "$HOME/.ssh/id_rsa" ]; then
        echo "Generating an SSH key pair for the user"
        ssh-keygen -t rsa -f "$HOME/.ssh/id_rsa" -N "" -q
    fi

    echo "Loading env variables from 00-base-config.rc"
    source 00-base-config.rc

fi

set +x

# "aux-svc" cluster
if [ -n "${INSTALL_AUX_CLUSTER}" ]; then
    echo "Provisioning auxiliary cluster with Gitea"
    export KUBECONFIG="${KUBECONFIG_AUX_CLUSTER}"
    ./01-provision-aux-svc.sh || FATAL_TRACK mgmtcluster "provision-aux-svc.sh failed"
    track mgmtcluster aux_cluster_ok

    ./02-provision-local-git-user.sh || FATAL_TRACK mgmtcluster "provision-local-git-user.sh failed"
    track mgmtcluster local_git_user_ok
fi

# "mgmt" cluster
if [ -n "${INSTALL_MGMT_CLUSTER}" ]; then
    echo "Provisioning mgmt cluster"
    export KUBECONFIG="${KUBECONFIG_MGMT_CLUSTER}"
    ./03-provision-mgmt-cluster.sh || FATAL_TRACK mgmtcluster "provision-mgmt-cluster.sh failed"
    track mgmtcluster mgmt_cluster_ok
fi

export KUBECONFIG=${KUBECONFIG_OLD}
if [ -n "${INSTALL_MGMT_CLUSTER}" ]; then
    echo "Saving age keys in OSM cluster"
    kubectl -n osm create secret generic mgmt-cluster-age-keys --from-file=privkey="${CREDENTIALS_DIR}/age.mgmt.key" --from-file=pubkey="${CREDENTIALS_DIR}/age.mgmt.pub"
fi

echo "Creating secrets with kubeconfig files"
kubectl -n osm create secret generic auxcluster-secret --from-file=kubeconfig="${KUBECONFIG_AUX_CLUSTER}"
kubectl -n osm create secret generic mgmtcluster-secret --from-file=kubeconfig="${KUBECONFIG_MGMT_CLUSTER}"

popd

