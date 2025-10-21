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


function setup_external_ip() {
    echo "Determining IP address of the interface with the default route"
    [ -z "$OSM_DEFAULT_IF" ] && OSM_DEFAULT_IF=$(ip route list|awk '$1=="default" {print $5; exit}')
    [ -z "$OSM_DEFAULT_IF" ] && OSM_DEFAULT_IF=$(route -n |awk '$1~/^0.0.0.0/ {print $8; exit}')
    [ -z "$OSM_DEFAULT_IF" ] && FATAL "Not possible to determine the interface with the default route 0.0.0.0"
    OSM_DEFAULT_IP=`ip -o -4 a s ${OSM_DEFAULT_IF} |awk '{split($4,a,"/"); print a[1]; exit}'`
    [ -z "$OSM_DEFAULT_IP" ] && FATAL "Not possible to determine the IP address of the interface with the default route"
    OSM_K8S_EXTERNAL_IP=${OSM_K8S_EXTERNAL_IP:-${OSM_DEFAULT_IP}}
}

function parse_docker_registry_url() {
    DOCKER_REGISTRY_USER=$(echo "$1" | awk '{split($1,a,"@"); split(a[1],b,":"); print b[1]}')
    DOCKER_REGISTRY_PASSWORD=$(echo "$1" | awk '{split($1,a,"@"); split(a[1],b,":"); print b[2]}')
    DOCKER_REGISTRY_URL=$(echo "$1" | awk '{split($1,a,"@"); print a[2]}')
}

function configure_apt_proxy() {
    OSM_APT_PROXY=$1
    OSM_APT_PROXY_FILE="/etc/apt/apt.conf.d/osm-apt"
    echo "Configuring apt proxy in file ${OSM_APT_PROXY_FILE}"
    if [ ! -f ${OSM_APT_PROXY_FILE} ]; then
        sudo bash -c "cat <<EOF > ${OSM_APT_PROXY}
Acquire::http { Proxy \"${OSM_APT_PROXY}\"; }
EOF"
    else
        sudo sed -i "s|Proxy.*|Proxy \"${OSM_APT_PROXY}\"; }|" ${OSM_APT_PROXY_FILE}
    fi
    sudo apt-get update || FATAL "Configured apt proxy, but couldn't run 'apt-get update'. Check ${OSM_APT_PROXY_FILE}"
    track prereq apt_proxy_configured_ok
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function ask_user(){
    # ask to the user and parse a response among 'y', 'yes', 'n' or 'no'. Case insensitive
    # Params: $1 text to ask;   $2 Action by default, can be 'y' for yes, 'n' for no, other or empty for not allowed
    # Return: true(0) if user type 'yes'; false (1) if user type 'no'
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
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

function docker_login() {
    echo "Docker login"
    DEBUG "Docker registry user: ${DOCKER_REGISTRY_USER}"
    sg docker -c "docker login -u ${DOCKER_REGISTRY_USER} -p ${DOCKER_REGISTRY_PASSWORD} --password-stdin"
}

function ask_proceed() {
    [ -z "$ASSUME_YES" ] && ! ask_user "The installation will do the following
    1. Install client tools (helm, kubectl, osmclient, wget, git, curl, tar, yq, flux, argo, kustomize)
    2. Deploy auxiliary services (Git, S3)
    3. Deploy mgmt cluster
    4. Deploy OSM
    5. Provision OSM
    Do you want to proceed (Y/n)? " y && echo "Cancelled!" && exit 1
}

function check_osm_behind_proxy() {
    export OSM_BEHIND_PROXY=""
    export OSM_PROXY_ENV_VARIABLES=""
    [ -n "${http_proxy}" ] && OSM_BEHIND_PROXY="y" && echo "http_proxy=${http_proxy}" && OSM_PROXY_ENV_VARIABLES="${OSM_PROXY_ENV_VARIABLES} http_proxy"
    [ -n "${https_proxy}" ] && OSM_BEHIND_PROXY="y" && echo "https_proxy=${https_proxy}" && OSM_PROXY_ENV_VARIABLES="${OSM_PROXY_ENV_VARIABLES} https_proxy"
    [ -n "${HTTP_PROXY}" ] && OSM_BEHIND_PROXY="y" && echo "HTTP_PROXY=${HTTP_PROXY}" && OSM_PROXY_ENV_VARIABLES="${OSM_PROXY_ENV_VARIABLES} HTTP_PROXY"
    [ -n "${HTTPS_PROXY}" ] && OSM_BEHIND_PROXY="y" && echo "HTTPS_PROXY=${HTTPS_PROXY}" && OSM_PROXY_ENV_VARIABLES="${OSM_PROXY_ENV_VARIABLES} HTTPS_PROXY"
    [ -n "${no_proxy}" ] && echo "no_proxy=${no_proxy}" && OSM_PROXY_ENV_VARIABLES="${OSM_PROXY_ENV_VARIABLES} no_proxy"
    [ -n "${NO_PROXY}" ] && echo "NO_PROXY=${NO_PROXY}" && OSM_PROXY_ENV_VARIABLES="${OSM_PROXY_ENV_VARIABLES} NO_PROXY"

    echo "OSM_BEHIND_PROXY=${OSM_BEHIND_PROXY}"
    echo "OSM_PROXY_ENV_VARIABLES=${OSM_PROXY_ENV_VARIABLES}"

    if [ -n "${OSM_BEHIND_PROXY}" ]; then
        [ -z "$ASSUME_YES" ] && ! ask_user "
The following env variables have been found for the current user:
${OSM_PROXY_ENV_VARIABLES}.

This suggests that this machine is behind a proxy and a special configuration is required.
The installer will install Docker CE and a Kubernetes to work behind a proxy using those
env variables.

Take into account that the installer uses apt, curl, wget and docker.
Depending on the program, the env variables to work behind a proxy might be different
(e.g. http_proxy vs HTTP_PROXY).

For that reason, it is strongly recommended that at least http_proxy, https_proxy, HTTP_PROXY
and HTTPS_PROXY are defined.

Finally, some of the programs (apt) are run as sudoer, requiring that those env variables
are also set for root user. If you are not sure whether those variables are configured for
the root user, you can stop the installation now.

Do you want to proceed with the installation (Y/n)? " y && echo "Cancelled!" && exit 1
    else
        echo "This machine is not behind a proxy"
    fi
}

