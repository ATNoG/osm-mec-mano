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

function usage(){
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo -e "usage: $0 [OPTIONS]"
    echo -e "Install Juju for OSM"
    echo -e "  OPTIONS"
    echo -e "     -h / --help:    print this help"
    echo -e "     -D <devops path> use local devops installation path"
    echo -e "     -H <VCA host>   use specific juju host controller IP"
    echo -e "     -S <VCA secret> use VCA/juju secret key"
    echo -e "     -P <VCA pubkey> use VCA/juju public key file"
    echo -e "     -l:             LXD cloud yaml file"
    echo -e "     -L:             LXD credentials yaml file"
    echo -e "     -K:             Specifies the name of the controller to use - The controller must be already bootstrapped"
    echo -e "     --debug:        debug mode"
    echo -e "     --cachelxdimages:  cache local lxd images, create cronjob for that cache (will make installation longer)"
    echo -e "     --nojuju:       do not juju, assumes already installed"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function install_lxd() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    # Apply sysctl production values for optimal performance
    sudo cp ${OSM_DEVOPS}/installers/60-lxd-production.conf /etc/sysctl.d/60-lxd-production.conf
    sudo sysctl --system

    # Install LXD snap
    sudo apt-get remove --purge -y liblxc1 lxc-common lxcfs lxd lxd-client
    snap info lxd | grep installed > /dev/null
    if [ $? -eq 0 ]; then
        sudo snap refresh lxd --channel $LXD_VERSION/stable
    else
        sudo snap install lxd --channel $LXD_VERSION/stable
    fi

    # Get default iface, IP and MTU
    if [ -n "${OSM_DEFAULT_IF}" ]; then
        OSM_DEFAULT_IF=$(ip route list|awk '$1=="default" {print $5; exit}')
        [ -z "${OSM_DEFAULT_IF}" ] && OSM_DEFAULT_IF=$(route -n |awk '$1~/^0.0.0.0/ {print $8; exit}')
        [ -z "${OSM_DEFAULT_IF}" ] && FATAL_TRACK lxd "Not possible to determine the interface with the default route 0.0.0.0"
    fi
    DEFAULT_MTU=$(ip addr show ${OSM_DEFAULT_IF} | perl -ne 'if (/mtu\s(\d+)/) {print $1;}')
    OSM_DEFAULT_IP=`ip -o -4 a s ${OSM_DEFAULT_IF} |awk '{split($4,a,"/"); print a[1]; exit}'`
    [ -z "$OSM_DEFAULT_IP" ] && FATAL_TRACK lxd "Not possible to determine the IP address of the interface with the default route"

    # Configure LXD
    sudo usermod -a -G lxd `whoami`
    cat ${OSM_DEVOPS}/installers/lxd-preseed.conf | sed 's/^config: {}/config:\n  core.https_address: '$OSM_DEFAULT_IP':8443/' | sg lxd -c "lxd init --preseed"
    sg lxd -c "lxd waitready"

    # Configure LXD to work behind a proxy
    if [ -n "${OSM_BEHIND_PROXY}" ] ; then
        [ -n "${HTTP_PROXY}" ] && sg lxd -c "lxc config set core.proxy_http $HTTP_PROXY"
        [ -n "${HTTPS_PROXY}" ] && sg lxd -c "lxc config set core.proxy_https $HTTPS_PROXY"
        [ -n "${NO_PROXY}" ] && sg lxd -c "lxc config set core.proxy_ignore_hosts $NO_PROXY"
    fi

    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

DEBUG_INSTALL=""
LXD_VERSION=5.0
OSM_DEVOPS=
OSM_BEHIND_PROXY=""

# main
while getopts ":D:d:i:-: hP" o; do
    case "${o}" in
        i)
            OSM_DEFAULT_IF="${OPTARG}"
            ;;
        d)
            OSM_DOCKER_WORK_DIR="${OPTARG}"
            ;;
        D)
            OSM_DEVOPS="${OPTARG}"
            ;;
        P)
            OSM_BEHIND_PROXY="y"
            ;;
        -)
            [ "${OPTARG}" == "help" ] && usage && exit 0
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
        h)
            usage && exit 0
            ;;
        *)
            exit 1
            ;;
    esac
done

source $OSM_DEVOPS/common/logging
source $OSM_DEVOPS/common/track

echo "DEBUG_INSTALL=$DEBUG_INSTALL"
echo "OSM_BEHIND_PROXY=$OSM_BEHIND_PROXY"
echo "OSM_DEFAULT_IF=$OSM_DEFAULT_IF"
echo "OSM_DEVOPS=$OSM_DEVOPS"

[ -z "$INSTALL_NOJUJU" ] && install_lxd
track prereq lxd_install_ok

