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

function usage(){
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo -e "usage: $0 [OPTIONS]"
    echo -e "Install OSM"
    echo -e "  OPTIONS"
    echo -e "     -h / --help:    print this help"
    echo -e "     -y:             do not prompt for confirmation, assumes yes"
    echo -e "     -r <repo>:      use specified repository name for osm packages"
    echo -e "     -R <release>:   use specified release for osm binaries (deb packages, lxd images, ...)"
    echo -e "     -u <repo base>: use specified repository url for osm packages"
    echo -e "     -k <repo key>:  use specified repository public key url"
    echo -e "     -a <apt proxy url>: use this apt proxy url when downloading apt packages (air-gapped installation)"
    echo -e "     -c <kubernetes engine>: use a specific kubernetes engine (options: kubeadm, k3s), default is kubeadm"
    echo -e "     -t <docker tag> specify osm docker tag (default is latest)"
    echo -e "     -M <KUBECONFIG_FILE>: Kubeconfig of an existing cluster to be used as mgmt cluster instead of OSM cluster"
    echo -e "     -G <KUBECONFIG_FILE>: Kubeconfig of an existing cluster to be used as auxiliary cluster instead of OSM cluster"
    echo -e "     --no-mgmt-cluster: Do not provision a mgmt cluster for cloud-native gitops operations in OSM (NEW in Release SIXTEEN) (by default, it is installed)"
    echo -e "     --no-aux-cluster: Do not provision an auxiliary cluster for cloud-native gitops operations in OSM (NEW in Release SIXTEEN) (by default, it is installed)"
    echo -e "     -D <devops path>:   use local devops installation path"
    echo -e "     -s <namespace>  namespace when installed using k8s, default is osm"
    echo -e "     -H <VCA host>   use specific juju host controller IP"
    echo -e "     -S <VCA secret> use VCA/juju secret key"
    echo -e "     -P <VCA pubkey> use VCA/juju public key file"
    echo -e "     -A <VCA apiproxy> use VCA/juju API proxy"
    echo -e "     --pla:          install the PLA module for placement support"
    echo -e "     --old-sa:       install old Service Assurance framework (MON, POL); do not install Airflow and Pushgateway"
    echo -e "     --ng-sa:        install new Service Assurance framework (Airflow, AlertManager and Pushgateway) (enabled by default)"
    echo -e "     -o <COMPONENT>: ONLY installs the specified component (k8s_monitor, ng-sa, k8scluster, docker, deploy-osm)"
    echo -e "     -O <openrc file path/cloud name>: install OSM to an OpenStack infrastructure. <openrc file/cloud name> is required. If a <cloud name> is used, the clouds.yaml file should be under ~/.config/openstack/ or /etc/openstack/"
    echo -e "     -N <openstack public network name/ID>: public network name required to setup OSM to OpenStack"
    echo -e "     -f <path to SSH public key>: public SSH key to use to deploy OSM to OpenStack"
    echo -e "     -F <path to cloud-init file>: cloud-init userdata file to deploy OSM to OpenStack"
    echo -e "     -w <work dir>:   Location to store runtime installation"
    echo -e "     -l:             LXD cloud yaml file"
    echo -e "     -L:             LXD credentials yaml file"
    echo -e "     -K:             Specifies the name of the controller to use - The controller must be already bootstrapped"
    echo -e "     -d <docker registry URL> use docker registry URL instead of dockerhub"
    echo -e "     -p <docker proxy URL> set docker proxy URL as part of docker CE configuration"
    echo -e "     -T <docker tag> specify docker tag for the modules specified with option -m"
    echo -e "     --debug:        debug mode"
    echo -e "     --nocachelxdimages:  do not cache local lxd images, do not create cronjob for that cache (will save installation time, might affect instantiation time)"
    echo -e "     --cachelxdimages:  cache local lxd images, create cronjob for that cache (will make installation longer)"
    echo -e "     --nolxd:        do not install and configure LXD, allowing unattended installations (assumes LXD is already installed and confifured)"
    echo -e "     --nodocker:     do not install docker, do not initialize a swarm (assumes docker is already installed and a swarm has been initialized)"
    echo -e "     --nojuju:       do not juju, assumes already installed"
    echo -e "     --nohostports:  do not expose docker ports to host (useful for creating multiple instances of osm on the same host)"
    echo -e "     --nohostclient: do not install the osmclient"
    echo -e "     --uninstall:    uninstall OSM: remove the containers and delete NAT rules"
    echo -e "     --k8s_monitor:  install the OSM kubernetes monitoring with prometheus and grafana"
    echo -e "     --volume:       create a VM volume when installing to OpenStack"
    echo -e "     --showopts:     print chosen options and exit (only for debugging)"
    echo -e "     --charmed:                   Deploy and operate OSM with Charms on k8s"
    echo -e "     [--bundle <bundle path>]:    Specify with which bundle to deploy OSM with charms (--charmed option)"
    echo -e "     [--k8s <kubeconfig path>]:   Specify with which kubernetes to deploy OSM with charms (--charmed option)"
    echo -e "     [--vca <name>]:              Specifies the name of the controller to use - The controller must be already bootstrapped (--charmed option)"
    echo -e "     [--small-profile]:           Do not install and configure LXD which aims to use only K8s Clouds (--charmed option)"
    echo -e "     [--lxd <yaml path>]:         Takes a YAML file as a parameter with the LXD Cloud information (--charmed option)"
    echo -e "     [--lxd-cred <yaml path>]:    Takes a YAML file as a parameter with the LXD Credentials information (--charmed option)"
    echo -e "     [--microstack]:              Installs microstack as a vim. (--charmed option)"
    echo -e "     [--overlay]:                 Add an overlay to override some defaults of the default bundle (--charmed option)"
    echo -e "     [--ha]:                      Installs High Availability bundle. (--charmed option)"
    echo -e "     [--tag]:                     Docker image tag. (--charmed option)"
    echo -e "     [--registry]:                Docker registry with optional credentials as user:pass@hostname:port (--charmed option)"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# takes a juju/accounts.yaml file and returns the password specific
# for a controller. I wrote this using only bash tools to minimize
# additions of other packages
function parse_juju_password {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    password_file="${HOME}/.local/share/juju/accounts.yaml"
    local controller_name=$1
    local s='[[:space:]]*' w='[a-zA-Z0-9_-]*' fs=$(echo @|tr @ '\034')
    sed -ne "s|^\($s\):|\1|" \
         -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
         -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p" $password_file |
    awk -F$fs -v controller=$controller_name '{
        indent = length($1)/2;
        vname[indent] = $2;
        for (i in vname) {if (i > indent) {delete vname[i]}}
        if (length($3) > 0) {
            vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
            if (match(vn,controller) && match($2,"password")) {
                printf("%s",$3);
            }
        }
    }'
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function set_vca_variables() {
    OSM_VCA_CLOUDNAME="lxd-cloud"
    [ -n "$OSM_VCA_HOST" ] && OSM_VCA_CLOUDNAME="localhost"
    if [ -z "$OSM_VCA_HOST" ]; then
        [ -z "$CONTROLLER_NAME" ] && OSM_VCA_HOST=`sg lxd -c "juju show-controller $OSM_NAMESPACE"|grep api-endpoints|awk -F\' '{print $2}'|awk -F\: '{print $1}'`
        [ -n "$CONTROLLER_NAME" ] && OSM_VCA_HOST=`juju show-controller $CONTROLLER_NAME |grep api-endpoints|awk -F\' '{print $2}'|awk -F\: '{print $1}'`
        [ -z "$OSM_VCA_HOST" ] && FATAL "Cannot obtain juju controller IP address"
    fi
    if [ -z "$OSM_VCA_SECRET" ]; then
        [ -z "$CONTROLLER_NAME" ] && OSM_VCA_SECRET=$(parse_juju_password $OSM_NAMESPACE)
        [ -n "$CONTROLLER_NAME" ] && OSM_VCA_SECRET=$(parse_juju_password $CONTROLLER_NAME)
        [ -z "$OSM_VCA_SECRET" ] && FATAL "Cannot obtain juju secret"
    fi
    if [ -z "$OSM_VCA_PUBKEY" ]; then
        OSM_VCA_PUBKEY=$(cat $HOME/.local/share/juju/ssh/juju_id_rsa.pub)
        [ -z "$OSM_VCA_PUBKEY" ] && FATAL "Cannot obtain juju public key"
    fi
    if [ -z "$OSM_VCA_CACERT" ]; then
        [ -z "$CONTROLLER_NAME" ] && OSM_VCA_CACERT=$(juju controllers --format json | jq -r --arg controller $OSM_NAMESPACE '.controllers[$controller]["ca-cert"]' | base64 | tr -d \\n)
        [ -n "$CONTROLLER_NAME" ] && OSM_VCA_CACERT=$(juju controllers --format json | jq -r --arg controller $CONTROLLER_NAME '.controllers[$controller]["ca-cert"]' | base64 | tr -d \\n)
        [ -z "$OSM_VCA_CACERT" ] && FATAL "Cannot obtain juju CA certificate"
    fi
}

function generate_secret() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function check_packages() {
    NEEDED_PACKAGES="$1"
    echo -e "Checking required packages: ${NEEDED_PACKAGES}"
    for PACKAGE in ${NEEDED_PACKAGES} ; do
        dpkg -L ${PACKAGE}
        if [ $? -ne 0 ]; then
            echo -e "Package ${PACKAGE} is not installed."
            echo -e "Updating apt-cache ..."
            sudo apt-get update
            echo -e "Installing ${PACKAGE} ..."
            sudo apt-get install -y ${PACKAGE} || FATAL "failed to install ${PACKAGE}"
        fi
    done
    echo -e "Required packages are present: ${NEEDED_PACKAGES}"
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

function install_osmclient(){
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    CLIENT_RELEASE=${RELEASE#"-R "}
    CLIENT_REPOSITORY_KEY="OSM%20ETSI%20Release%20Key.gpg"
    CLIENT_REPOSITORY=${REPOSITORY#"-r "}
    CLIENT_REPOSITORY_BASE=${REPOSITORY_BASE#"-u "}
    key_location=$CLIENT_REPOSITORY_BASE/$CLIENT_RELEASE/$CLIENT_REPOSITORY_KEY
    curl $key_location | sudo APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 apt-key add -
    sudo add-apt-repository -y "deb [arch=amd64] $CLIENT_REPOSITORY_BASE/$CLIENT_RELEASE $CLIENT_REPOSITORY osmclient IM"
    sudo apt-get -y update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3-pip
    sudo -H LC_ALL=C python3 -m pip install -U pip
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3-osm-im python3-osmclient
    if [ -f /usr/lib/python3/dist-packages/osm_im/requirements.txt ]; then
        python3 -m pip install -r /usr/lib/python3/dist-packages/osm_im/requirements.txt
    fi
    if [ -f /usr/lib/python3/dist-packages/osmclient/requirements.txt ]; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libmagic1
        python3 -m pip install -r /usr/lib/python3/dist-packages/osmclient/requirements.txt
    fi
    echo -e "\nOSM client installed"
    echo "You can get the OSM NBI endpoint using the following command"
    echo '     kubectl -n osm get ingress nbi-ingress -o jsonpath="{.spec.rules[0].host}"'
    echo "You will have to configure this env variable in your .bashrc file:"
    echo "     export OSM_HOSTNAME=nbi.${OSM_K8S_EXTERNAL_IP}.nip.io"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
    return 0
}

function docker_login() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo "Docker login"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG "Docker registry user: ${DOCKER_REGISTRY_USER}"
    sg docker -c "docker login -u ${DOCKER_REGISTRY_USER} -p ${DOCKER_REGISTRY_PASSWORD} --password-stdin"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

#deploys osm pods and services
function deploy_osm_helm_chart() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    # Generate helm values to be passed with -f osm-values.yaml
    sudo mkdir -p ${OSM_HELM_WORK_DIR}
    if [ -n "${INSTALL_JUJU}" ]; then
        sudo bash -c "cat << EOF > ${OSM_HELM_WORK_DIR}/osm-values.yaml
vca:
  pubkey: \"${OSM_VCA_PUBKEY}\"
EOF"
    fi

    # Generate helm values to be passed with --set
    OSM_HELM_OPTS=""
    # OSM_HELM_OPTS="${OSM_HELM_OPTS} --set nbi.useOsmSecret=false"

    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.image.repositoryBase=${DOCKER_REGISTRY_URL}${DOCKER_USER}"
    [ ! "$OSM_DOCKER_TAG" == "17" ] && OSM_HELM_OPTS="${OSM_HELM_OPTS} --set-string global.image.tag=${OSM_DOCKER_TAG}"
    [ ! "$OSM_DOCKER_TAG" == "17" ] && OSM_HELM_OPTS="${OSM_HELM_OPTS} --set prometheus.server.sidecarContainers.prometheus-config-sidecar.image=${DOCKER_REGISTRY_URL}${DOCKER_USER}/prometheus:${OSM_DOCKER_TAG}"

    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.hostname=${OSM_K8S_EXTERNAL_IP}.nip.io"
    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set grafana.ingress.hosts={grafana.${OSM_K8S_EXTERNAL_IP}.nip.io}"
    OSM_HELM_OPTS="${OSM_HELM_OPTS} --set prometheus.server.ingress.hosts={prometheus.${OSM_K8S_EXTERNAL_IP}.nip.io}"
    # OSM_HELM_OPTS="${OSM_HELM_OPTS} --set prometheus.alertmanager.ingress.hosts={alertmanager.${OSM_K8S_EXTERNAL_IP}.nip.io}"
    if [ -z "${INSTALL_MGMT_CLUSTER}" ]; then
        OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.gitops.enabled=false"
    else
        source "${HOME}/.osm/.credentials/gitea_environment.rc"
        OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.gitops.gitBaseUrl=${GITEA_HTTP_URL}"
        OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.gitops.gitUser=${GITEA_STD_USERNAME}"
        AGE_MGMT_PUBKEY=$(tr -d '\n' < ${HOME}/.osm/.credentials/age.mgmt.pub)
        OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.gitops.pubkey=${AGE_MGMT_PUBKEY}"
    fi

    if [ -n "${INSTALL_JUJU}" ]; then
        OSM_HELM_OPTS="${OSM_HELM_OPTS} --set vca.enabled=true"
        OSM_HELM_OPTS="${OSM_HELM_OPTS} --set vca.host=${OSM_VCA_HOST}"
        OSM_HELM_OPTS="${OSM_HELM_OPTS} --set vca.secret=${OSM_VCA_SECRET}"
        OSM_HELM_OPTS="${OSM_HELM_OPTS} --set vca.cacert=${OSM_VCA_CACERT}"
    fi
    [ -n "$OSM_VCA_APIPROXY" ] && OSM_HELM_OPTS="${OSM_HELM_OPTS} --set lcm.config.OSMLCM_VCA_APIPROXY=${OSM_VCA_APIPROXY}"

    [ -n "${INSTALL_NGSA}" ] || OSM_HELM_OPTS="${OSM_HELM_OPTS} --set global.oldServiceAssurance=true"
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

    if [ -n "${INSTALL_JUJU}" ]; then
        OSM_HELM_OPTS="-f ${OSM_HELM_WORK_DIR}/osm-values.yaml ${OSM_HELM_OPTS}"
    fi
    # Dependency update before installing helm chart
    echo "helm dependency update ${OSM_DEVOPS}/installers/helm/osm"
    helm dependency update ${OSM_DEVOPS}/installers/helm/osm || FATAL_TRACK osm_helm_chart "Failed updating osm helm chart dependencies"
    # Deploy helm chart
    echo "helm upgrade --install -n $OSM_NAMESPACE --create-namespace $OSM_NAMESPACE $OSM_DEVOPS/installers/helm/osm ${OSM_HELM_OPTS}"
    helm upgrade --install -n $OSM_NAMESPACE --create-namespace $OSM_NAMESPACE $OSM_DEVOPS/installers/helm/osm ${OSM_HELM_OPTS}
    # Override existing values.yaml with the final values.yaml used to install OSM
    helm -n $OSM_NAMESPACE get values $OSM_NAMESPACE | sudo tee -a ${OSM_HELM_WORK_DIR}/osm-values.yaml
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

#deploy charmed services
function deploy_charmed_services() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    juju add-model $OSM_NAMESPACE $OSM_VCA_K8S_CLOUDNAME
    juju deploy ch:mongodb-k8s -m $OSM_NAMESPACE --channel latest/stable
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

#deploy mongodb
function deploy_mongodb() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    MONGO_OPTS="-d ${OSM_HELM_WORK_DIR} -D ${OSM_DEVOPS} -s ${OSM_NAMESPACE} -U ${DOCKER_USER} ${DEBUG_INSTALL}"
    [ -n "${DOCKER_REGISTRY_URL}" ] && MONGO_OPTS="${MONGO_OPTS} -r ${DOCKER_REGISTRY_URL}"
    $OSM_DEVOPS/installers/install_mongodb.sh ${MONGO_OPTS} || \
    FATAL_TRACK install_osm_mongodb_service "install_mongodb.sh failed"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function install_osm_ngsa_service() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    NGSA_OPTS="-i ${OSM_K8S_EXTERNAL_IP} -d ${OSM_HELM_WORK_DIR} -D ${OSM_DEVOPS} -s ${OSM_NAMESPACE} -t ${OSM_DOCKER_TAG} -U ${DOCKER_USER} ${DEBUG_INSTALL}"
    [ -n "${DOCKER_REGISTRY_URL}" ] && NGSA_OPTS="${NGSA_OPTS} -r ${DOCKER_REGISTRY_URL}"
    $OSM_DEVOPS/installers/install_ngsa.sh ${NGSA_OPTS} || \
    FATAL_TRACK install_osm_ngsa_service "install_ngsa.sh failed"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function add_local_k8scluster() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    # OSM_HOSTNAME=$(kubectl get --namespace osm -o jsonpath="{.spec.rules[0].host}" ingress nbi-ingress)
    OSM_HOSTNAME="nbi.${OSM_K8S_EXTERNAL_IP}.nip.io:443"
    /usr/bin/osm --hostname ${OSM_HOSTNAME} --all-projects vim-create \
      --name _system-osm-vim \
      --account_type dummy \
      --auth_url http://dummy \
      --user osm --password osm --tenant osm \
      --description "dummy" \
      --config '{management_network_name: mgmt}'
    /usr/bin/osm --hostname ${OSM_HOSTNAME} --all-projects k8scluster-add \
      --creds ${HOME}/.kube/config \
      --vim _system-osm-vim \
      --k8s-nets '{"net1": null}' \
      --version '1.29' \
      --description "OSM Internal Cluster" \
      _system-osm-k8s
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function configure_apt_proxy() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
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

function ask_proceed() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function

    [ -z "$ASSUME_YES" ] && ! ask_user "The installation will do the following
    1. Install and configure LXD
    2. Install juju
    3. Install docker CE
    4. Disable swap space
    5. Install and initialize Kubernetes
    as pre-requirements.
    Do you want to proceed (Y/n)? " y && echo "Cancelled!" && exit 1

    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function check_osm_behind_proxy() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function

    export OSM_BEHIND_PROXY=""
    export OSM_PROXY_ENV_VARIABLES=""
    [ -n "${http_proxy}" ] && OSM_BEHIND_PROXY="y" && echo "http_proxy=${http_proxy}" && OSM_PROXY_ENV_VARIABLES="${OSM_PROXY_ENV_VARIABLES} http_proxy"
    [ -n "${https_proxy}" ] && OSM_BEHIND_PROXY="y" && echo "https_proxy=${https_proxy}" && OSM_PROXY_ENV_VARIABLES="${OSM_PROXY_ENV_VARIABLES} https_proxy"
    [ -n "${HTTP_PROXY}" ] && OSM_BEHIND_PROXY="y" && echo "HTTP_PROXY=${HTTP_PROXY}" && OSM_PROXY_ENV_VARIABLES="${OSM_PROXY_ENV_VARIABLES} HTTP_PROXY"
    [ -n "${HTTPS_PROXY}" ] && OSM_BEHIND_PROXY="y" && echo "https_proxy=${HTTPS_PROXY}" && OSM_PROXY_ENV_VARIABLES="${OSM_PROXY_ENV_VARIABLES} HTTPS_PROXY"
    [ -n "${no_proxy}" ] && echo "no_proxy=${no_proxy}" && OSM_PROXY_ENV_VARIABLES="${OSM_PROXY_ENV_VARIABLES} no_proxy"
    [ -n "${NO_PROXY}" ] && echo "NO_PROXY=${NO_PROXY}" && OSM_PROXY_ENV_VARIABLES="${OSM_PROXY_ENV_VARIABLES} NO_PROXY"

    echo "OSM_BEHIND_PROXY=${OSM_BEHIND_PROXY}"
    echo "OSM_PROXY_ENV_VARIABLES=${OSM_PROXY_ENV_VARIABLES}"

    if [ -n "${OSM_BEHIND_PROXY}" ]; then
        [ -z "$ASSUME_YES" ] && ! ask_user "
The following env variables have been found for the current user:
${OSM_PROXY_ENV_VARIABLES}.

This suggests that this machine is behind a proxy and a special configuration is required.
The installer will install Docker CE, LXD and Juju to work behind a proxy using those
env variables.

Take into account that the installer uses apt, curl, wget, docker, lxd, juju and snap.
Depending on the program, the env variables to work behind a proxy might be different
(e.g. http_proxy vs HTTP_PROXY).

For that reason, it is strongly recommended that at least http_proxy, https_proxy, HTTP_PROXY
and HTTPS_PROXY are defined.

Finally, some of the programs (apt, snap) those programs are run as sudoer, requiring that
those env variables are also set for root user. If you are not sure whether those variables
are configured for the root user, you can stop the installation now.

Do you want to proceed with the installation (Y/n)? " y && echo "Cancelled!" && exit 1
    else
        echo "This machine is not behind a proxy"
    fi

    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function find_devops_folder() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    if [ -z "$OSM_DEVOPS" ]; then
        if [ -n "$TEST_INSTALLER" ]; then
            echo -e "\nUsing local devops repo for OSM installation"
            OSM_DEVOPS="$(dirname $(realpath $(dirname $0)))"
        else
            echo -e "\nCreating temporary dir for OSM installation"
            OSM_DEVOPS="$(mktemp -d -q --tmpdir "installosm.XXXXXX")"
            trap 'rm -rf "$OSM_DEVOPS"' EXIT
            git clone https://osm.etsi.org/gerrit/osm/devops.git $OSM_DEVOPS
        fi
    fi
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function install_lxd() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    LXD_INSTALL_OPTS="-D ${OSM_DEVOPS} -i ${OSM_DEFAULT_IF} ${DEBUG_INSTALL}"
    [ -n "${OSM_BEHIND_PROXY}" ] && LXD_INSTALL_OPTS="${LXD_INSTALL_OPTS} -P"
    $OSM_DEVOPS/installers/install_lxd.sh ${LXD_INSTALL_OPTS} || FATAL_TRACK lxd "install_lxd.sh failed"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function install_docker_ce() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    DOCKER_CE_OPTS="-D ${OSM_DEVOPS} ${DEBUG_INSTALL}"
    [ -n "${DOCKER_PROXY_URL}" ] && DOCKER_CE_OPTS="${DOCKER_CE_OPTS} -p ${DOCKER_PROXY_URL}"
    [ -n "${OSM_BEHIND_PROXY}" ] && DOCKER_CE_OPTS="${DOCKER_CE_OPTS} -P"
    $OSM_DEVOPS/installers/install_docker_ce.sh ${DOCKER_CE_OPTS} || FATAL_TRACK docker_ce "install_docker_ce.sh failed"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function install_k8s_cluster() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    if [ "${K8S_CLUSTER_ENGINE}" == "kubeadm" ]; then
        KUBEADM_INSTALL_OPTS="-d ${OSM_WORK_DIR} -D ${OSM_DEVOPS} ${DEBUG_INSTALL}"
        $OSM_DEVOPS/installers/install_kubeadm_cluster.sh ${KUBEADM_INSTALL_OPTS} || \
        FATAL_TRACK k8scluster "install_kubeadm_cluster.sh failed"
        K8SCLUSTER_ADDONS_INSTALL_OPTS="-i ${OSM_DEFAULT_IP} -d ${OSM_WORK_DIR} -D ${OSM_DEVOPS} ${DEBUG_INSTALL} --all"
        $OSM_DEVOPS/installers/install_cluster_addons.sh ${K8SCLUSTER_ADDONS_INSTALL_OPTS} || \
        FATAL_TRACK k8scluster "install_cluster_addons.sh failed for kubeadm cluster"
    elif [ "${K8S_CLUSTER_ENGINE}" == "k3s" ]; then
        K3S_INSTALL_OPTS="-i ${OSM_DEFAULT_IP} -D ${OSM_DEVOPS} ${DEBUG_INSTALL}"
        [ "${OSM_K8S_EXTERNAL_IP}" != "${OSM_DEFAULT_IP}" ] && K3S_INSTALL_OPTS="${K3S_INSTALL_OPTS} -e ${OSM_K8S_EXTERNAL_IP}"
        [ -n "${DOCKER_PROXY_URL}" ] && K3S_INSTALL_OPTS="${K3S_INSTALL_OPTS} -p ${DOCKER_PROXY_URL}"
        [ -n "${DOCKER_REGISTRY_URL}" ] && K3S_INSTALL_OPTS="${K3S_INSTALL_OPTS} -d ${DOCKER_REGISTRY_URL}"
        [ -n "${DOCKER_REGISTRY_USER}" ] && K3S_INSTALL_OPTS="${K3S_INSTALL_OPTS} -u ${DOCKER_REGISTRY_USER}"
        [ -n "${DOCKER_REGISTRY_PASSWORD}" ] && K3S_INSTALL_OPTS="${K3S_INSTALL_OPTS} -P ${DOCKER_REGISTRY_PASSWORD}"
        # The K3s installation script will automatically take the HTTP_PROXY, HTTPS_PROXY and NO_PROXY,
        # as well as the CONTAINERD_HTTP_PROXY, CONTAINERD_HTTPS_PROXY and CONTAINERD_NO_PROXY variables
        # from the shell, if they are present, and write them to the environment file of k3s systemd service,
        $OSM_DEVOPS/installers/install_k3s_cluster.sh ${K3S_INSTALL_OPTS} || \
        FATAL_TRACK k8scluster "install_k3s_cluster.sh failed"
        K8SCLUSTER_ADDONS_INSTALL_OPTS="-i ${OSM_DEFAULT_IP} -d ${OSM_WORK_DIR} -D ${OSM_DEVOPS} ${DEBUG_INSTALL} --certmgr --nginx"
        $OSM_DEVOPS/installers/install_cluster_addons.sh ${K8SCLUSTER_ADDONS_INSTALL_OPTS} || \
        FATAL_TRACK k8scluster "install_cluster_addons.sh failed for k3s cluster"
    fi
    echo "Updating fsnotify settings of the system kernel"
    sudo bash -c "sysctl -w fs.inotify.max_user_watches=699050 > /etc/sysctl.d/99-custom-osm-sysctl.conf"
    sudo bash -c "sysctl -w fs.inotify.max_user_instances=10922 >> /etc/sysctl.d/99-custom-osm-sysctl.conf"
    sudo bash -c "sysctl -w fs.inotify.max_queued_events=1398101 >> /etc/sysctl.d/99-custom-osm-sysctl.conf"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function deploy_osm() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    deploy_mongodb
    track deploy_osm deploy_mongodb_ok
    deploy_osm_helm_chart
    track deploy_osm deploy_osm_services_k8s_ok
    if [ -n "$INSTALL_NGSA" ]; then
        # optional NGSA install
        install_osm_ngsa_service
        track deploy_osm install_osm_ngsa_ok
    fi
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function setup_external_ip() {
    echo "Determining IP address of the interface with the default route"
    [ -z "$OSM_DEFAULT_IF" ] && OSM_DEFAULT_IF=$(ip route list|awk '$1=="default" {print $5; exit}')
    [ -z "$OSM_DEFAULT_IF" ] && OSM_DEFAULT_IF=$(route -n |awk '$1~/^0.0.0.0/ {print $8; exit}')
    [ -z "$OSM_DEFAULT_IF" ] && FATAL "Not possible to determine the interface with the default route 0.0.0.0"
    OSM_DEFAULT_IP=`ip -o -4 a s ${OSM_DEFAULT_IF} |awk '{split($4,a,"/"); print a[1]; exit}'`
    [ -z "$OSM_DEFAULT_IP" ] && FATAL "Not possible to determine the IP address of the interface with the default route"
    OSM_K8S_EXTERNAL_IP=${OSM_K8S_EXTERNAL_IP:-${OSM_DEFAULT_IP}}
}

function install_osm() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function

    trap ctrl_c INT

    check_osm_behind_proxy
    check_packages "git wget curl tar snapd"
    if [ -n "${INSTALL_JUJU}" ]; then
        sudo snap install jq || FATAL "Could not install jq (snap package). Make sure that snap works"
    fi
    find_devops_folder

    track start release $RELEASE none none docker_tag $OSM_DOCKER_TAG none none installation_type $OSM_INSTALLATION_TYPE none none os_info $os_info none none

    track checks checkingroot_ok
    [ "$USER" == "root" ] && FATAL "You are running the installer as root. The installer is prepared to be executed as a normal user with sudo privileges."
    track checks noroot_ok
    ask_proceed
    track checks proceed_ok

    echo "Installing OSM"

    [ -n "$DOCKER_REGISTRY_URL" ] && parse_docker_registry_url

    echo "Setting up external IP address"
    setup_external_ip

    # configure apt proxy
    [ -n "$APT_PROXY_URL" ] && configure_apt_proxy $APT_PROXY_URL

    # if lxd is requested, we will install it
    [ -n "$INSTALL_LXD" ] && install_lxd

    track prereq prereqok_ok

    if [ -n "$INSTALL_DOCKER" ] || [ "${K8S_CLUSTER_ENGINE}" == "kubeadm" ]; then
        if [ "${K8S_CLUSTER_ENGINE}" == "kubeadm" ]; then
            echo "Kubeadm requires docker, so docker will be installed."
        fi
        install_docker_ce
        [ -n "${DOCKER_REGISTRY_URL}" ] && docker_login
    fi
    track docker_ce docker_ce_ok

    echo "Installing helm client ..."
    $OSM_DEVOPS/installers/install_helm_client.sh -D ${OSM_DEVOPS} ${DEBUG_INSTALL} || \
    FATAL_TRACK k8scluster "install_helm_client.sh failed"
    track helm_client install_helm_client_ok

    echo "Installing K8s cluster ..."
    install_k8s_cluster
    kubectl create namespace ${OSM_NAMESPACE}
    track k8scluster k8scluster_ok

    if [ -n "${INSTALL_JUJU}" ]; then
        echo "Installing Juju ..."
        JUJU_OPTS="-D ${OSM_DEVOPS} -s ${OSM_NAMESPACE} -i ${OSM_DEFAULT_IP} ${DEBUG_INSTALL} ${INSTALL_CACHELXDIMAGES}"
        [ -n "${OSM_VCA_HOST}" ] && JUJU_OPTS="$JUJU_OPTS -H ${OSM_VCA_HOST}"
        [ -n "${LXD_CLOUD_FILE}" ] && JUJU_OPTS="$JUJU_OPTS -l ${LXD_CLOUD_FILE}"
        [ -n "${LXD_CRED_FILE}" ] && JUJU_OPTS="$JUJU_OPTS -L ${LXD_CRED_FILE}"
        [ -n "${CONTROLLER_NAME}" ] && JUJU_OPTS="$JUJU_OPTS -K ${CONTROLLER_NAME}"
        [ -n "${OSM_BEHIND_PROXY}" ] && JUJU_OPTS="${JUJU_OPTS} -P"
        $OSM_DEVOPS/installers/install_juju.sh ${JUJU_OPTS} || FATAL_TRACK juju "install_juju.sh failed"
        set_vca_variables
    fi
    track juju juju_ok

    # This track is maintained for backwards compatibility
    track docker_images docker_images_ok

    # Install mgmt cluster
    echo "Installing mgmt cluster ..."
    MGMTCLUSTER_INSTALL_OPTS="-D ${OSM_DEVOPS} ${DEBUG_INSTALL}"
    [ -n "${INSTALL_MGMT_CLUSTER}" ] || MGMTCLUSTER_INSTALL_OPTS="${MGMTCLUSTER_INSTALL_OPTS} --no-mgmt-cluster"
    [ -n "${INSTALL_AUX_CLUSTER}" ] || MGMTCLUSTER_INSTALL_OPTS="${MGMTCLUSTER_INSTALL_OPTS} --no-aux-cluster"
    export KUBECONFIG_MGMT_CLUSTER=${KUBECONFIG_MGMT_CLUSTER:-"$HOME/.kube/config"}
    export KUBECONFIG_AUX_CLUSTER=${KUBECONFIG_AUX_CLUSTER:-"$HOME/.kube/config"}
    MGMTCLUSTER_INSTALL_OPTS="${MGMTCLUSTER_INSTALL_OPTS} -M ${KUBECONFIG_MGMT_CLUSTER}"
    MGMTCLUSTER_INSTALL_OPTS="${MGMTCLUSTER_INSTALL_OPTS} -G ${KUBECONFIG_AUX_CLUSTER}"
    echo "Options: ${MGMTCLUSTER_INSTALL_OPTS}"
    $OSM_DEVOPS/installers/mgmt-cluster/install_mgmt_cluster.sh ${MGMTCLUSTER_INSTALL_OPTS} || \
    FATAL_TRACK mgmtcluster "install_mgmt_cluster.sh failed"
    if [ -n "${INSTALL_MGMT_CLUSTER}" ]; then
        echo "Credentials stored under ${HOME}/.osm/.credentials"
        echo "Repos stored under ${HOME}/.osm/repos"
    fi
    track mgmtcluster mgmt_and_aux_cluster_ok

    # Deploy OSM (mongodb, OSM helm chart, NGSA)
    echo "Deploying OSM in the K8s cluster ..."
    deploy_osm

    if [ -n "$INSTALL_K8S_MONITOR" ]; then
        # install OSM MONITORING
        install_k8s_monitoring
        track deploy_osm install_k8s_monitoring_ok
    fi

    [ -z "$INSTALL_NOHOSTCLIENT" ] && echo "Installing osmclient ..." && install_osmclient
    track osmclient osmclient_ok

    echo -e "Checking OSM health state..."
    $OSM_DEVOPS/installers/osm_health.sh -s ${OSM_NAMESPACE} -k || \
    (echo -e "OSM is not healthy, but will probably converge to a healthy state soon." && \
    echo -e "Check OSM status with: kubectl -n ${OSM_NAMESPACE} get all" && \
    track healthchecks osm_unhealthy didnotconverge)
    track healthchecks after_healthcheck_ok

    echo -e "Adding local K8s cluster _system-osm-k8s to OSM ..."
    add_local_k8scluster
    track final_ops add_local_k8scluster_ok

    # if lxd is requested, iptables firewall is updated to work with both docker and LXD
    if [ -n "$INSTALL_LXD" ]; then
        arrange_docker_default_network_policy
    fi

    wget -q -O- https://osm-download.etsi.org/ftp/osm-17.0-seventeen/README2.txt &> /dev/null
    track end
    sudo find /etc/osm
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
    return 0
}

function install_to_openstack() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function

    if [ -z "$2" ]; then
        FATAL "OpenStack installer requires a valid external network name"
    fi

    # Install Pip for Python3
    sudo apt install -y python3-pip python3-venv
    sudo -H LC_ALL=C python3 -m pip install -U pip

    # Create a venv to avoid conflicts with the host installation
    python3 -m venv $OPENSTACK_PYTHON_VENV

    source $OPENSTACK_PYTHON_VENV/bin/activate

    # Install Ansible, OpenStack client and SDK, latest openstack version supported is Train
    python -m pip install -U wheel
    python -m pip install -U "python-openstackclient<=4.0.2" "openstacksdk>=0.12.0,<=0.36.2" "ansible>=2.10,<2.11"

    # Install the Openstack cloud module (ansible>=2.10)
    ansible-galaxy collection install openstack.cloud

    export ANSIBLE_CONFIG="$OSM_DEVOPS/installers/openstack/ansible.cfg"

    OSM_INSTALLER_ARGS="${REPO_ARGS[@]}"

    ANSIBLE_VARS="external_network_name=$2 setup_volume=$3 server_name=$OPENSTACK_VM_NAME"

    if [ -n "$OPENSTACK_SSH_KEY_FILE" ]; then
        ANSIBLE_VARS+=" key_file=$OPENSTACK_SSH_KEY_FILE"
    fi

    if [ -n "$OPENSTACK_USERDATA_FILE" ]; then
        ANSIBLE_VARS+=" userdata_file=$OPENSTACK_USERDATA_FILE"
    fi

    # Execute the Ansible playbook based on openrc or clouds.yaml
    if [ -e "$1" ]; then
        . $1
        ansible-playbook -e installer_args="\"$OSM_INSTALLER_ARGS\"" -e "$ANSIBLE_VARS" \
        $OSM_DEVOPS/installers/openstack/site.yml
    else
        ansible-playbook -e installer_args="\"$OSM_INSTALLER_ARGS\"" -e "$ANSIBLE_VARS" \
        -e cloud_name=$1 $OSM_DEVOPS/installers/openstack/site.yml
    fi

    # Exit from venv
    deactivate

    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
    return 0
}

function arrange_docker_default_network_policy() {
    echo -e "Fixing firewall so docker and LXD can share the same host without affecting each other."
    sudo iptables -I DOCKER-USER -j ACCEPT
    sudo iptables-save | sudo tee /etc/iptables/rules.v4
    sudo ip6tables-save | sudo tee /etc/iptables/rules.v6
}

function install_k8s_monitoring() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    # install OSM monitoring
    sudo $OSM_DEVOPS/installers/k8s/install_osm_k8s_monitoring.sh -o ${OSM_NAMESPACE} || FATAL_TRACK install_k8s_monitoring "k8s/install_osm_k8s_monitoring.sh failed"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function dump_vars(){
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo "APT_PROXY_URL=$APT_PROXY_URL"
    echo "K8S_CLUSTER_ENGINE=$K8S_CLUSTER_ENGINE"
    echo "DEBUG_INSTALL=$DEBUG_INSTALL"
    echo "DOCKER_PROXY_URL=$DOCKER_PROXY_URL"
    echo "DOCKER_REGISTRY_URL=$DOCKER_REGISTRY_URL"
    echo "DOCKER_USER=$DOCKER_USER"
    echo "INSTALL_CACHELXDIMAGES=$INSTALL_CACHELXDIMAGES"
    echo "INSTALL_JUJU=$INSTALL_JUJU"
    echo "INSTALL_K8S_MONITOR=$INSTALL_K8S_MONITOR"
    echo "INSTALL_LXD=$INSTALL_LXD"
    echo "INSTALL_NGSA=$INSTALL_NGSA"
    echo "INSTALL_DOCKER=$INSTALL_DOCKER"
    echo "INSTALL_ONLY=$INSTALL_ONLY"
    echo "INSTALL_ONLY_DEPLOY_OSM=$INSTALL_ONLY_DEPLOY_OSM"
    echo "INSTALL_ONLY_DOCKER_CE=$INSTALL_ONLY_DOCKER_CE"
    echo "INSTALL_ONLY_K8S_CLUSTER=$INSTALL_ONLY_K8S_CLUSTER"
    echo "INSTALL_ONLY_NGSA=$INSTALL_ONLY_NGSA"
    echo "INSTALL_PLA=$INSTALL_PLA"
    echo "INSTALL_TO_OPENSTACK=$INSTALL_TO_OPENSTACK"
    echo "INSTALL_VIMEMU=$INSTALL_VIMEMU"
    echo "OPENSTACK_PUBLIC_NET_NAME=$OPENSTACK_PUBLIC_NET_NAME"
    echo "OPENSTACK_OPENRC_FILE_OR_CLOUD=$OPENSTACK_OPENRC_FILE_OR_CLOUD"
    echo "OPENSTACK_ATTACH_VOLUME=$OPENSTACK_ATTACH_VOLUME"
    echo "OPENSTACK_SSH_KEY_FILE"="$OPENSTACK_SSH_KEY_FILE"
    echo "OPENSTACK_USERDATA_FILE"="$OPENSTACK_USERDATA_FILE"
    echo "OPENSTACK_VM_NAME"="$OPENSTACK_VM_NAME"
    echo "OSM_DEVOPS=$OSM_DEVOPS"
    echo "OSM_DOCKER_TAG=$OSM_DOCKER_TAG"
    echo "OSM_K8S_EXTERNAL_IP=$OSM_K8S_EXTERNAL_IP"
    echo "OSM_HELM_WORK_DIR=$OSM_HELM_WORK_DIR"
    echo "OSM_NAMESPACE=$OSM_NAMESPACE"
    echo "OSM_VCA_HOST=$OSM_VCA_HOST"
    echo "OSM_VCA_PUBKEY=$OSM_VCA_PUBKEY"
    echo "OSM_VCA_SECRET=$OSM_VCA_SECRET"
    echo "OSM_WORK_DIR=$OSM_WORK_DIR"
    echo "PULL_IMAGES=$PULL_IMAGES"
    echo "RECONFIGURE=$RECONFIGURE"
    echo "RELEASE=$RELEASE"
    echo "REPOSITORY=$REPOSITORY"
    echo "REPOSITORY_BASE=$REPOSITORY_BASE"
    echo "REPOSITORY_KEY=$REPOSITORY_KEY"
    echo "SHOWOPTS=$SHOWOPTS"
    echo "TEST_INSTALLER=$TEST_INSTALLER"
    echo "UNINSTALL=$UNINSTALL"
    echo "UPDATE=$UPDATE"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function parse_docker_registry_url() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    DOCKER_REGISTRY_USER=$(echo "$DOCKER_REGISTRY_URL" | awk '{split($1,a,"@"); split(a[1],b,":"); print b[1]}')
    DOCKER_REGISTRY_PASSWORD=$(echo "$DOCKER_REGISTRY_URL" | awk '{split($1,a,"@"); split(a[1],b,":"); print b[2]}')
    DOCKER_REGISTRY_URL=$(echo "$DOCKER_REGISTRY_URL" | awk '{split($1,a,"@"); print a[2]}')
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function ctrl_c() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo "** Trapped CTRL-C"
    FATAL "User stopped the installation"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

UNINSTALL=""
UPDATE=""
RECONFIGURE=""
TEST_INSTALLER=""
INSTALL_LXD=""
SHOWOPTS=""
ASSUME_YES=""
APT_PROXY_URL=""
K8S_CLUSTER_ENGINE="k3s"
DEBUG_INSTALL=""
RELEASE="ReleaseSEVENTEEN"
REPOSITORY="stable"
INSTALL_K8S_MONITOR=""
INSTALL_NGSA="y"
INSTALL_PLA=""
INSTALL_VIMEMU=""
LXD_REPOSITORY_BASE="https://osm-download.etsi.org/repository/osm/lxd"
LXD_REPOSITORY_PATH=""
INSTALL_TO_OPENSTACK=""
OPENSTACK_OPENRC_FILE_OR_CLOUD=""
OPENSTACK_PUBLIC_NET_NAME=""
OPENSTACK_ATTACH_VOLUME="false"
OPENSTACK_SSH_KEY_FILE=""
OPENSTACK_USERDATA_FILE=""
OPENSTACK_VM_NAME="server-osm"
OPENSTACK_PYTHON_VENV="$HOME/.virtual-envs/osm"
INSTALL_ONLY=""
INSTALL_ONLY_DEPLOY_OSM=""
INSTALL_ONLY_DOCKER_CE=""
INSTALL_ONLY_K8S_CLUSTER=""
INSTALL_ONLY_NGSA=""
INSTALL_DOCKER=""
INSTALL_JUJU=""
INSTALL_NOHOSTCLIENT=""
INSTALL_CACHELXDIMAGES=""
INSTALL_AUX_CLUSTER="y"
INSTALL_MGMT_CLUSTER="y"
OSM_DEVOPS=
OSM_VCA_HOST=
OSM_VCA_SECRET=
OSM_VCA_PUBKEY=
OSM_VCA_CLOUDNAME="localhost"
OSM_VCA_K8S_CLOUDNAME="k8scloud"
OSM_NAMESPACE=osm
REPOSITORY_KEY="OSM%20ETSI%20Release%20Key.gpg"
REPOSITORY_BASE="https://osm-download.etsi.org/repository/osm/debian"
OSM_WORK_DIR="/etc/osm"
OSM_HELM_WORK_DIR="${OSM_WORK_DIR}/helm"
OSM_HOST_VOL="/var/lib/osm"
OSM_NAMESPACE_VOL="${OSM_HOST_VOL}/${OSM_NAMESPACE}"
OSM_DOCKER_TAG="17"
DOCKER_USER=opensourcemano
PULL_IMAGES="y"
KAFKA_TAG=2.11-1.0.2
KIWIGRID_K8S_SIDECAR_TAG="1.15.6"
PROMETHEUS_TAG=v2.28.1
GRAFANA_TAG=8.1.1
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
OSM_INSTALLATION_TYPE="Default"

while getopts ":a:c:e:r:n:k:u:R:D:o:O:N:H:S:s:t:U:P:A:l:L:K:d:p:T:f:F:G:M:-: hy" o; do
    case "${o}" in
        a)
            APT_PROXY_URL=${OPTARG}
            ;;
        c)
            K8S_CLUSTER_ENGINE=${OPTARG}
            [ "${K8S_CLUSTER_ENGINE}" == "kubeadm" ] && continue
            [ "${K8S_CLUSTER_ENGINE}" == "k3s" ] && continue
            echo -e "Invalid argument for -c : ' ${K8S_CLUSTER_ENGINE}'\n" >&2
            usage && exit 1
            ;;
        e)
            OSM_K8S_EXTERNAL_IP="${OPTARG}"
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
            [ "${OPTARG}" == "ng-sa" ] && INSTALL_ONLY_NGSA="y" && continue
            [ "${OPTARG}" == "docker" ] && INSTALL_ONLY_DOCKER_CE="y" && continue
            [ "${OPTARG}" == "k8scluster" ] && INSTALL_ONLY_K8S_CLUSTER="y" && continue
            [ "${OPTARG}" == "deploy-osm" ] && INSTALL_ONLY_DEPLOY_OSM="y" && continue
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
        M)
            KUBECONFIG_MGMT_CLUSTER="${OPTARG}"
            ;;
        G)
            KUBECONFIG_AUX_CLUSTER="${OPTARG}"
            ;;
        -)
            [ "${OPTARG}" == "help" ] && usage && exit 0
            [ "${OPTARG}" == "debug" ] && DEBUG_INSTALL="--debug" && continue
            [ "${OPTARG}" == "uninstall" ] && UNINSTALL="y" && continue
            [ "${OPTARG}" == "no-mgmt-cluster" ] && INSTALL_MGMT_CLUSTER="" && continue
            [ "${OPTARG}" == "no-aux-cluster" ] && INSTALL_AUX_CLUSTER="" && continue
            [ "${OPTARG}" == "update" ] && UPDATE="y" && continue
            [ "${OPTARG}" == "reconfigure" ] && RECONFIGURE="y" && continue
            [ "${OPTARG}" == "test" ] && TEST_INSTALLER="y" && continue
            [ "${OPTARG}" == "lxdinstall" ] && INSTALL_LXD="y" && continue
            [ "${OPTARG}" == "lxd" ] && INSTALL_LXD="y" && continue
            [ "${OPTARG}" == "nolxd" ] && INSTALL_LXD="" && continue
            [ "${OPTARG}" == "docker" ] && INSTALL_DOCKER="y" && continue
            [ "${OPTARG}" == "nodocker" ] && INSTALL_DOCKER="" && continue
            [ "${OPTARG}" == "showopts" ] && SHOWOPTS="y" && continue
            [ "${OPTARG}" == "juju" ] && INSTALL_JUJU="y" && continue
            [ "${OPTARG}" == "nojuju" ] && INSTALL_JUJU="" && continue
            [ "${OPTARG}" == "nohostclient" ] && INSTALL_NOHOSTCLIENT="y" && continue
            [ "${OPTARG}" == "k8s_monitor" ] && INSTALL_K8S_MONITOR="y" && continue
            [ "${OPTARG}" == "charmed" ] && CHARMED="y" && OSM_INSTALLATION_TYPE="Charmed" && continue
            [ "${OPTARG}" == "bundle" ] && continue
            [ "${OPTARG}" == "k8s" ] && continue
            [ "${OPTARG}" == "lxd-cred" ] && continue
            [ "${OPTARG}" == "microstack" ] && continue
            [ "${OPTARG}" == "overlay" ] && continue
            [ "${OPTARG}" == "only-vca" ] && continue
            [ "${OPTARG}" == "small-profile" ] && continue
            [ "${OPTARG}" == "vca" ] && continue
            [ "${OPTARG}" == "ha" ] && continue
            [ "${OPTARG}" == "tag" ] && continue
            [ "${OPTARG}" == "registry" ] && continue
            [ "${OPTARG}" == "pla" ] && INSTALL_PLA="y" && continue
            [ "${OPTARG}" == "old-sa" ] && INSTALL_NGSA="" && continue
            [ "${OPTARG}" == "ng-sa" ] && INSTALL_NGSA="y" && continue
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

[ -z "${DEBUG_INSTALL}" ] || DEBUG Debug is on
[ -n "$SHOWOPTS" ] && dump_vars && exit 0

# Uninstall if "--uninstall"
if [ -n "$UNINSTALL" ]; then
    if [ -n "$CHARMED" ]; then
        ${OSM_DEVOPS}/installers/charmed_uninstall.sh -R $RELEASE -r $REPOSITORY -u $REPOSITORY_BASE -D $OSM_DEVOPS -t $DOCKER_TAG "$@" || \
        FATAL_TRACK charmed_uninstall "charmed_uninstall.sh failed"
    else
        ${OSM_DEVOPS}/installers/uninstall_osm.sh "$@" || \
        FATAL_TRACK community_uninstall "uninstall_osm.sh failed"
    fi
    echo -e "\nDONE"
    exit 0
fi

# Installation starts here

# Get README and create OSM_TRACK_INSTALLATION_ID
wget -q -O- https://osm-download.etsi.org/ftp/osm-17.0-seventeen/README.txt &> /dev/null
export OSM_TRACK_INSTALLATION_ID="$(date +%s)-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)"

# Get OS info to be tracked
os_distro=$(lsb_release -i 2>/dev/null | awk '{print $3}')
echo $os_distro
os_release=$(lsb_release -r 2>/dev/null | awk '{print $2}')
echo $os_release
os_info="${os_distro}_${os_release}"
os_info="${os_info// /_}"

if [ -n "$CHARMED" ]; then
    # Charmed installation
    sudo snap install jq || FATAL "Could not install jq (snap package). Make sure that snap works"
    ${OSM_DEVOPS}/installers/charmed_install.sh --tag $OSM_DOCKER_TAG "$@" || \
    FATAL_TRACK charmed_install "charmed_install.sh failed"
    wget -q -O- https://osm-download.etsi.org/ftp/osm-17.0-seventeen/README2.txt &> /dev/null
    echo -e "\nDONE"
    exit 0
elif [ -n "$INSTALL_TO_OPENSTACK" ]; then
    # Installation to Openstack
    install_to_openstack $OPENSTACK_OPENRC_FILE_OR_CLOUD $OPENSTACK_PUBLIC_NET_NAME $OPENSTACK_ATTACH_VOLUME
    echo -e "\nDONE"
    exit 0
else
    # Community_installer
    # Special cases go first
    if [ -n "$INSTALL_ONLY" ]; then
        setup_external_ip
        [ -n "$INSTALL_ONLY_DOCKER_CE" ] && install_docker_ce
        [ -n "$INSTALL_ONLY_K8S_CLUSTER" ] && install_k8s_cluster
        [ -n "$INSTALL_K8S_MONITOR" ] && install_k8s_monitoring
        [ -n "$INSTALL_ONLY_DEPLOY_OSM" ] && deploy_osm
        [ -n "$INSTALL_ONLY_NGSA" ] && install_osm_ngsa_service
        echo -e "\nDONE" && exit 0
    fi
    # This is where installation starts
    install_osm
    echo -e "\nDONE"
    exit 0
fi
