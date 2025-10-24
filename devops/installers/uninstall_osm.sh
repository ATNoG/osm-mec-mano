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

#removes osm deployments and services
function remove_k8s_namespace() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    kubectl delete ns $1
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function remove_volumes() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    k8_volume=$1
    echo "Removing ${k8_volume}"
    sudo rm -rf ${k8_volume}
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function remove_crontab_job() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    crontab -l | grep -v '${OSM_DEVOPS}/installers/update-juju-lxc-images'  | crontab -
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function uninstall_k8s_monitoring() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    # uninstall OSM monitoring
    sudo $OSM_DEVOPS/installers/k8s/uninstall_osm_k8s_monitoring.sh
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

#Uninstall osmclient
function uninstall_osmclient() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    sudo apt-get remove --purge -y python3-osmclient
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

#Uninstall OSM: remove deployments and services
function uninstall_osm() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo -e "\nUninstalling OSM"
    if [ -n "$INSTALL_K8S_MONITOR" ]; then
        # uninstall OSM MONITORING
        uninstall_k8s_monitoring
    fi
    remove_k8s_namespace $OSM_NAMESPACE
    echo "Now osm docker images and volumes will be deleted"
    # TODO: clean-up of images should take into account if other tags were used for specific modules
    newgrp docker << EONG
for module in ro lcm keystone nbi mon pol pla osmclient; do
    docker image rm ${DOCKER_REGISTRY_URL}${DOCKER_USER}/${module}:${OSM_DOCKER_TAG}
done
EONG

    sg docker -c "docker image rm ${DOCKER_REGISTRY_URL}${DOCKER_USER}/ng-ui:${OSM_DOCKER_TAG}"

    OSM_NAMESPACE_VOL="${OSM_HOST_VOL}/${OSM_NAMESPACE}"
    remove_volumes $OSM_NAMESPACE_VOL

    [ -z "$CONTROLLER_NAME" ] && sg lxd -c "juju kill-controller -t 0 -y $OSM_NAMESPACE"

    remove_crontab_job

    # Cleanup Openstack installer venv
    if [ -d "$OPENSTACK_PYTHON_VENV" ]; then
        rm -r $OPENSTACK_PYTHON_VENV
    fi

    [ -z "$INSTALL_NOHOSTCLIENT" ] && uninstall_osmclient
    echo "Some docker images will be kept in case they are used by other docker stacks"
    echo "To remove them, just run 'docker image prune' in a terminal"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
    return 0
}

function ask_user(){
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    # ask to the user and parse a response among 'y', 'yes', 'n' or 'no'. Case insensitive
    # Params: $1 text to ask;   $2 Action by default, can be 'y' for yes, 'n' for no, other or empty for not allowed
    # Return: true(0) if user type 'yes'; false (1) if user type 'no'
    read -e -p "$1" USER_CONFIRMATION
    while true ; do
        [ -z "$USER_CONFIRMATION" ] && [ "$2" == 'y' ] && return 0
        [ -z "$USER_CONFIRMATION" ] && [ "$2" == 'n' ] && return 1
        [ "${USER_CONFIRMATION,,}" == "yes" ] || [ "${USER_CONFIRMATION,,}" == "y" ] && return 0
        [ "${USER_CONFIRMATION,,}" == "no" ]  || [ "${USER_CONFIRMATION,,}" == "n" ] && return 1
        read -e -p "Please type 'yes' or 'no': " USER_CONFIRMATION
    done
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

LXD_VERSION=4.0
JUJU_VERSION=2.9
UNINSTALL=""
DEVELOP=""
UPDATE=""
RECONFIGURE=""
TEST_INSTALLER=""
INSTALL_LXD=""
SHOWOPTS=""
COMMIT_ID=""
ASSUME_YES=""
APT_PROXY_URL=""
INSTALL_FROM_SOURCE=""
DEBUG_INSTALL=""
RELEASE="ReleaseTEN"
REPOSITORY="stable"
INSTALL_VIMEMU=""
INSTALL_PLA=""
LXD_REPOSITORY_BASE="https://osm-download.etsi.org/repository/osm/lxd"
LXD_REPOSITORY_PATH=""
INSTALL_LIGHTWEIGHT="y"
INSTALL_TO_OPENSTACK=""
OPENSTACK_OPENRC_FILE_OR_CLOUD=""
OPENSTACK_PUBLIC_NET_NAME=""
OPENSTACK_ATTACH_VOLUME="false"
OPENSTACK_SSH_KEY_FILE=""
OPENSTACK_USERDATA_FILE=""
OPENSTACK_VM_NAME="server-osm"
OPENSTACK_PYTHON_VENV="$HOME/.virtual-envs/osm"
INSTALL_ONLY=""
TO_REBUILD=""
INSTALL_NOLXD=""
INSTALL_NODOCKER=""
INSTALL_NOJUJU=""
INSTALL_K8S_MONITOR=""
INSTALL_NOHOSTCLIENT=""
INSTALL_CACHELXDIMAGES=""
OSM_DEVOPS=
OSM_VCA_HOST=
OSM_VCA_SECRET=
OSM_VCA_PUBKEY=
OSM_VCA_CLOUDNAME="localhost"
OSM_VCA_K8S_CLOUDNAME="k8scloud"
OSM_NAMESPACE=osm
NO_HOST_PORTS=""
DOCKER_NOBUILD=""
REPOSITORY_KEY="OSM%20ETSI%20Release%20Key.gpg"
REPOSITORY_BASE="https://osm-download.etsi.org/repository/osm/debian"
OSM_WORK_DIR="/etc/osm"
OSM_HOST_VOL="/var/lib/osm"
OSM_NAMESPACE_VOL="${OSM_HOST_VOL}/${OSM_NAMESPACE}"
OSM_DOCKER_TAG=latest
DOCKER_USER=opensourcemano
PULL_IMAGES="y"
KAFKA_TAG=2.11-1.0.2
PROMETHEUS_TAG=v2.4.3
GRAFANA_TAG=latest
PROMETHEUS_NODE_EXPORTER_TAG=0.18.1
PROMETHEUS_CADVISOR_TAG=latest
KEYSTONEDB_TAG=10
OSM_DATABASE_COMMONKEY=
ELASTIC_VERSION=6.4.2
ELASTIC_CURATOR_VERSION=5.5.4
POD_NETWORK_CIDR=10.244.0.0/16
K8S_MANIFEST_DIR="/etc/kubernetes/manifests"
RE_CHECK='^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'
DOCKER_REGISTRY_URL=
DOCKER_PROXY_URL=
MODULE_DOCKER_TAG=

while getopts ":a:b:r:n:k:u:R:D:o:O:m:N:H:S:s:t:U:P:A:l:L:K:d:p:T:f:F:-: hy" o; do
    case "${o}" in
        a)
            APT_PROXY_URL=${OPTARG}
            ;;
        b)
            COMMIT_ID=${OPTARG}
            PULL_IMAGES=""
            ;;
        r)
            REPOSITORY="${OPTARG}"
            REPO_ARGS+=(-r "$REPOSITORY")
            ;;
        k)
            REPOSITORY_KEY="${OPTARG}"
            REPO_ARGS+=(-k "$REPOSITORY_KEY")
            ;;
        u)
            REPOSITORY_BASE="${OPTARG}"
            REPO_ARGS+=(-u "$REPOSITORY_BASE")
            ;;
        R)
            RELEASE="${OPTARG}"
            REPO_ARGS+=(-R "$RELEASE")
            ;;
        D)
            OSM_DEVOPS="${OPTARG}"
            ;;
        o)
            INSTALL_ONLY="y"
            [ "${OPTARG}" == "k8s_monitor" ] && INSTALL_K8S_MONITOR="y" && continue
            ;;
        O)
            INSTALL_TO_OPENSTACK="y"
            if [ -n "${OPTARG}" ]; then
                OPENSTACK_OPENRC_FILE_OR_CLOUD="${OPTARG}"
            else
                echo -e "Invalid argument for -O : ' $OPTARG'\n" >&2
                usage && exit 1
            fi
            ;;
        f)
            OPENSTACK_SSH_KEY_FILE="${OPTARG}"
            ;;
        F)
            OPENSTACK_USERDATA_FILE="${OPTARG}"
            ;;
        N)
            OPENSTACK_PUBLIC_NET_NAME="${OPTARG}"
            ;;
        m)
            [ "${OPTARG}" == "NG-UI" ] && TO_REBUILD="$TO_REBUILD NG-UI" && continue
            [ "${OPTARG}" == "NBI" ] && TO_REBUILD="$TO_REBUILD NBI" && continue
            [ "${OPTARG}" == "LCM" ] && TO_REBUILD="$TO_REBUILD LCM" && continue
            [ "${OPTARG}" == "RO" ] && TO_REBUILD="$TO_REBUILD RO" && continue
            [ "${OPTARG}" == "MON" ] && TO_REBUILD="$TO_REBUILD MON" && continue
            [ "${OPTARG}" == "POL" ] && TO_REBUILD="$TO_REBUILD POL" && continue
            [ "${OPTARG}" == "PLA" ] && TO_REBUILD="$TO_REBUILD PLA" && continue
            [ "${OPTARG}" == "osmclient" ] && TO_REBUILD="$TO_REBUILD osmclient" && continue
            [ "${OPTARG}" == "KAFKA" ] && TO_REBUILD="$TO_REBUILD KAFKA" && continue
            [ "${OPTARG}" == "MONGO" ] && TO_REBUILD="$TO_REBUILD MONGO" && continue
            [ "${OPTARG}" == "PROMETHEUS" ] && TO_REBUILD="$TO_REBUILD PROMETHEUS" && continue
            [ "${OPTARG}" == "PROMETHEUS-CADVISOR" ] && TO_REBUILD="$TO_REBUILD PROMETHEUS-CADVISOR" && continue
            [ "${OPTARG}" == "KEYSTONE-DB" ] && TO_REBUILD="$TO_REBUILD KEYSTONE-DB" && continue
            [ "${OPTARG}" == "GRAFANA" ] && TO_REBUILD="$TO_REBUILD GRAFANA" && continue
            [ "${OPTARG}" == "NONE" ] && TO_REBUILD="$TO_REBUILD NONE" && continue
            ;;
        H)
            OSM_VCA_HOST="${OPTARG}"
            ;;
        S)
            OSM_VCA_SECRET="${OPTARG}"
            ;;
        s)
            OSM_NAMESPACE="${OPTARG}" && [[ ! "${OPTARG}" =~ $RE_CHECK ]] && echo "Namespace $OPTARG is invalid. Regex used for validation is $RE_CHECK" && exit 0
            ;;
        t)
            OSM_DOCKER_TAG="${OPTARG}"
            REPO_ARGS+=(-t "$OSM_DOCKER_TAG")
            ;;
        U)
            DOCKER_USER="${OPTARG}"
            ;;
        P)
            OSM_VCA_PUBKEY=$(cat ${OPTARG})
            ;;
        A)
            OSM_VCA_APIPROXY="${OPTARG}"
            ;;
        l)
            LXD_CLOUD_FILE="${OPTARG}"
            ;;
        L)
            LXD_CRED_FILE="${OPTARG}"
            ;;
        K)
            CONTROLLER_NAME="${OPTARG}"
            ;;
        d)
            DOCKER_REGISTRY_URL="${OPTARG}"
            ;;
        p)
            DOCKER_PROXY_URL="${OPTARG}"
            ;;
        T)
            MODULE_DOCKER_TAG="${OPTARG}"
            ;;
        -)
            [ "${OPTARG}" == "help" ] && usage && exit 0
            [ "${OPTARG}" == "source" ] && INSTALL_FROM_SOURCE="y" && PULL_IMAGES="" && continue
            [ "${OPTARG}" == "debug" ] && DEBUG_INSTALL="--debug" && continue
            [ "${OPTARG}" == "develop" ] && DEVELOP="y" && continue
            [ "${OPTARG}" == "uninstall" ] && UNINSTALL="y" && continue
            [ "${OPTARG}" == "update" ] && UPDATE="y" && continue
            [ "${OPTARG}" == "reconfigure" ] && RECONFIGURE="y" && continue
            [ "${OPTARG}" == "test" ] && TEST_INSTALLER="y" && continue
            [ "${OPTARG}" == "lxdinstall" ] && INSTALL_LXD="y" && continue
            [ "${OPTARG}" == "nolxd" ] && INSTALL_NOLXD="y" && continue
            [ "${OPTARG}" == "nodocker" ] && INSTALL_NODOCKER="y" && continue
            [ "${OPTARG}" == "showopts" ] && SHOWOPTS="y" && continue
            [ "${OPTARG}" == "nohostports" ] && NO_HOST_PORTS="y" && continue
            [ "${OPTARG}" == "nojuju" ] && INSTALL_NOJUJU="--nojuju" && continue
            [ "${OPTARG}" == "nodockerbuild" ] && DOCKER_NOBUILD="y" && continue
            [ "${OPTARG}" == "nohostclient" ] && INSTALL_NOHOSTCLIENT="y" && continue
            [ "${OPTARG}" == "pullimages" ] && continue
            [ "${OPTARG}" == "k8s_monitor" ] && INSTALL_K8S_MONITOR="y" && continue
            [ "${OPTARG}" == "charmed" ] && CHARMED="y" && continue
            [ "${OPTARG}" == "bundle" ] && continue
            [ "${OPTARG}" == "k8s" ] && continue
            [ "${OPTARG}" == "lxd" ] && continue
            [ "${OPTARG}" == "lxd-cred" ] && continue
            [ "${OPTARG}" == "microstack" ] && continue
            [ "${OPTARG}" == "overlay" ] && continue
            [ "${OPTARG}" == "only-vca" ] && continue
            [ "${OPTARG}" == "vca" ] && continue
            [ "${OPTARG}" == "ha" ] && continue
            [ "${OPTARG}" == "tag" ] && continue
            [ "${OPTARG}" == "registry" ] && continue
            [ "${OPTARG}" == "pla" ] && INSTALL_PLA="y" && continue
            [ "${OPTARG}" == "volume" ] && OPENSTACK_ATTACH_VOLUME="true" && continue
            [ "${OPTARG}" == "nocachelxdimages" ] && continue
            [ "${OPTARG}" == "cachelxdimages" ] && INSTALL_CACHELXDIMAGES="--cachelxdimages" && continue
            echo -e "Invalid option: '--$OPTARG'\n" >&2
            usage && exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument" >&2
            usage && exit 1
            ;;
        \?)
            echo -e "Invalid option: '-$OPTARG'\n" >&2
            usage && exit 1
            ;;
        h)
            usage && exit 0
            ;;
        y)
            ASSUME_YES="y"
            ;;
        *)
            usage && exit 1
            ;;
    esac
done

source $OSM_DEVOPS/common/all_funcs

uninstall_osm

