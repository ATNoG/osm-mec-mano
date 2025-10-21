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
    echo -e "     -R <release>:   use specified release for osm binaries (deb packages, ...)"
    echo -e "     -u <repo base>: use specified repository url for osm packages"
    echo -e "     -k <repo key>:  use specified repository public key url"
    echo -e "     -a <apt proxy url>: use this apt proxy url when downloading apt packages (air-gapped installation)"
    echo -e "     -c <kubernetes engine>: use a specific kubernetes engine (options: kubeadm, k3s), default is kubeadm"
    echo -e "     -t <docker tag> specify osm docker tag (default is latest)"
    echo -e "     -M <KUBECONFIG_FILE>: Kubeconfig of an existing cluster to be used as mgmt cluster instead of OSM cluster"
    echo -e "     -G <KUBECONFIG_FILE>: Kubeconfig of an existing cluster to be used as auxiliary cluster instead of OSM cluster"
    echo -e "     -O <KUBECONFIG_FILE>: Kubeconfig of an existing cluster to be used as OSM cluster instead of creating a new one from scratch"
    echo -e "     --no-mgmt-cluster: Do not provision a mgmt cluster for cloud-native gitops operations in OSM (NEW in Release SIXTEEN) (by default, it is installed)"
    echo -e "     --no-aux-cluster: Do not provision an auxiliary cluster for cloud-native gitops operations in OSM (NEW in Release SIXTEEN) (by default, it is installed)"
    echo -e "     -s <namespace>  namespace where OSM helm chart will be deployed (default is osm)"
    echo -e "     -d <docker registry URL> use docker registry URL instead of dockerhub"
    echo -e "     -p <docker proxy URL> set docker proxy URL as part of docker CE configuration"
    echo -e "     -T <docker tag> specify docker tag for the modules specified with option -m"
    echo -e "     -U <docker user>: specify docker user to use when pulling images from a private registry"
    echo -e "     -D <devops path>: use particular devops installation path"
    echo -e "     -e <external IP>: set the external IP address of the OSM cluster (default is empty, which means autodetect)"
    echo -e "     --debug:        debug mode"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
OSM_DEVOPS="${OSM_DEVOPS:-"${HERE}/.."}"
source $OSM_DEVOPS/library/all_funcs

echo "Load default options and export user installation options"
source $OSM_DEVOPS/installers/00-default-install-options.rc

RE_CHECK='^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'
while getopts ":a:c:e:r:k:u:R:D:s:t:U:d:p:T:M:G:O:-: hy" o; do
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
        d)
            parse_docker_registry_url "${OPTARG}"
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
        O)
            KUBECONFIG_OSM_CLUSTER="${OPTARG}"
            ;;
        -)
            [ "${OPTARG}" == "help" ] && usage && exit 0
            [ "${OPTARG}" == "debug" ] && DEBUG_INSTALL="--debug" && continue
            [ "${OPTARG}" == "no-mgmt-cluster" ] && INSTALL_MGMT_CLUSTER="" && continue
            [ "${OPTARG}" == "no-aux-cluster" ] && INSTALL_AUX_CLUSTER="" && continue
            if [[ "${OPTARG}" == "client-version" ]]; then
                OSM_CLIENT_VERSION="${!OPTIND}"; OPTIND=$((OPTIND + 1))
                continue
            fi
            if [[ "${OPTARG}" == "im-version" ]]; then
                OSM_IM_VERSION="${!OPTIND}"; OPTIND=$((OPTIND + 1))
                continue
            fi
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


[ -z "${DEBUG_INSTALL}" ] || DEBUG Debug is on
# Installation starts here

# Get README and create OSM_TRACK_INSTALLATION_ID
curl -s https://osm-download.etsi.org/ftp/osm-18.0-eighteen/README.txt > /dev/null 2>&1
export OSM_TRACK_INSTALLATION_ID="$(date +%s)-$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)"

# Get OS info to be tracked
os_distro=$(lsb_release -i 2>/dev/null | awk '{print $3}')
echo $os_distro
os_release=$(lsb_release -r 2>/dev/null | awk '{print $2}')
echo $os_release
os_info="${os_distro}_${os_release}"
os_info="${os_info// /_}"

# Initial checks: proxy, root user, proceed
check_osm_behind_proxy
track start release $RELEASE none none docker_tag $OSM_DOCKER_TAG none none installation_type Default none none os_info $os_info none none
track checks checkingroot_ok
[ "$USER" == "root" ] && FATAL "You are running the installer as root. The installer is prepared to be executed as a normal user with sudo privileges."
track checks noroot_ok
ask_proceed
track checks proceed_ok

# Setup prerequisites
echo "Setting up external IP address"
setup_external_ip
[ -n "$APT_PROXY_URL" ] && echo "Configuring APT proxy" && configure_apt_proxy $APT_PROXY_URL
track prereq prereqok_ok

# Export installation options
$OSM_DEVOPS/installers/01-export-osm-install-options.sh || FATAL_TRACK exportinstallopts "01-export-osm-install-options.sh failed"
track exportinstallopts exportinstallopts_ok

# Setup Client tools
echo "Setup CLI tools for mgmt and aux cluster"
$OSM_DEVOPS/installers/10-install-client-tools.sh || FATAL_TRACK installclitools "10-install-client-tools.sh failed"
track installclitools installclitools_ok

# Install K8s cluster where all OSM components will be deployed
echo "Installing K8s cluster ..."
source "${HERE}/../library/utils.sh"
# setup_external_ip
export OSM_DEFAULT_IP
export OSM_K8S_EXTERNAL_IP
$OSM_DEVOPS/installers/15-install-k8s-cluster.sh || FATAL_TRACK k8scluster "15-install-k8s-cluster.sh"
track k8scluster k8scluster_ok

# Deploy auxiliary services
if [ -n "${INSTALL_AUX_CLUSTER}" ]; then
    echo "Deploy auxiliary services (Gitea, S3)"
    $OSM_DEVOPS/installers/20-deploy-aux-svc-cluster.sh || FATAL_TRACK deployauxsvc "20-deploy-aux-svc-cluster.sh failed"
else
    echo "Skipping deployment of auxiliary services."
    echo "Using existing git credentials and repos defined in ${CREDENTIALS_DIR}/git_environment.rc"
#     cat << EOF > "${CREDENTIALS_DIR}/git_environment.rc"
# export GIT_BASE_HTTP_URL="${GITEA_HTTP_URL}"
# export FLEET_REPO_HTTP_URL="${FLEET_REPO_HTTP_URL}"
# export FLEET_REPO_SSH_URL="${FLEET_REPO_SSH_URL}"
# export FLEET_REPO_GIT_USERNAME="${FLEET_REPO_GIT_USERNAME}"
# export FLEET_REPO_GIT_USER_PASS='${FLEET_REPO_GIT_USER_PASS}'
# export SW_CATALOGS_REPO_HTTP_URL="${SW_CATALOGS_REPO_HTTP_URL}"
# export SW_CATALOGS_REPO_SSH_URL="${SW_CATALOGS_REPO_SSH_URL}"
# export SW_CATALOGS_REPO_GIT_USERNAME="${SW_CATALOGS_REPO_GIT_USERNAME}"
# export SW_CATALOGS_REPO_GIT_USER_PASS='${SW_CATALOGS_REPO_GIT_USER_PASS}'
# EOF
fi
track deployauxsvc deployauxsvc_ok

# Deploy mgmt services
if [ -n "${INSTALL_MGMT_CLUSTER}" ]; then
    echo "Deploy mgmt cluster (Flux, etc.)"
    $OSM_DEVOPS/installers/30-deploy-mgmt-cluster.sh || FATAL_TRACK mgmtcluster "30-deploy-mgmt-cluster.sh failed"
else
    echo "Skipping deployment of mgmt cluster"
    # TODO: write env variables to files"
fi
track mgmtcluster mgmtcluster_ok

# Deploy OSM (OSM helm chart)
echo "Deploy OSM helm chart"
export OSM_K8S_EXTERNAL_IP
$OSM_DEVOPS/installers/40-deploy-osm.sh || FATAL_TRACK deployosm "40-deploy-osm.sh failed"
track deploy_osm deploy_osm_ok

# Provision OSM
echo -e "Adding local K8s cluster _system-osm-k8s to OSM ..."
$OSM_DEVOPS/installers/50-provision-osm.sh || FATAL_TRACK provision-osm "50-provision-osm.sh failed"
track provisionosm provisionosm_ok

curl -s https://osm-download.etsi.org/ftp/osm-18.0-eighteen/README2.txt > /dev/null 2>&1
track end

echo "Credentials stored under ${CREDENTIALS_DIR}"
echo "Git repos for OSM declarative framework stored under ${WORK_REPOS_DIR}"
echo "Kubeconfigs of the aux-svc cluster, mgmt cluster and OSM cluster stored under ${OSM_HOME_DIR}/clusters"
echo -e "\nDONE"
exit 0
