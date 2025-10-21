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
REPOSITORY_BASE=https://osm-download.etsi.org/repository/osm/debian
RELEASE=ReleaseSIXTEEN
REPOSITORY=stable
DOCKER_TAG="testing-daily"
DEVOPS_PATH=/usr/share/osm-devops

function usage(){
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
    echo -e "     -D <devops path>:   use local devops installation path"
    echo -e "     -s <namespace>  namespace when installed using k8s, default is osm"
    echo -e "     -w <work dir>:   Location to store runtime installation"
    echo -e "     -K:             Specifies the name of the controller to use - The controller must be already bootstrapped"
    echo -e "     -d <docker registry URL> use docker registry URL instead of dockerhub"
    echo -e "     -p <docker proxy URL> set docker proxy URL as part of docker CE configuration"
    echo -e "     -T <docker tag> specify docker tag for the modules specified with option -m"
    echo -e "     --debug:        debug mode"
    echo -e "     --uninstall:    uninstall OSM: remove the containers and delete NAT rules"
}

add_repo() {
  REPO_CHECK="^$1"
  grep "${REPO_CHECK/\[arch=amd64\]/\\[arch=amd64\\]}" /etc/apt/sources.list > /dev/null 2>&1
  if [ $? -ne 0 ]
  then
    need_packages_lw="software-properties-common apt-transport-https"
    echo -e "Checking required packages to add ETSI OSM debian repo: $need_packages_lw"
    dpkg -l $need_packages_lw &>/dev/null \
      || ! echo -e "One or several required packages are not installed. Updating apt cache requires root privileges." \
      || sudo apt-get -qy update \
      || ! echo "failed to run apt-get update" \
      || exit 1
    dpkg -l $need_packages_lw &>/dev/null \
      || ! echo -e "Installing $need_packages_lw requires root privileges." \
      || sudo apt-get install -y $need_packages_lw \
      || ! echo "failed to install $need_packages_lw" \
      || exit 1
    curl -s -o OSM-ETSI-Release-key.gpg "$REPOSITORY_BASE/$RELEASE/OSM%20ETSI%20Release%20Key.gpg"
    sudo APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 apt-key add OSM-ETSI-Release-key.gpg \
      || ! echo -e "Could not add GPG key $REPOSITORY_BASE/$RELEASE/OSM%20ETSI%20Release%20Key.gpg" \
      || exit 1
    sudo DEBIAN_FRONTEND=noninteractive add-apt-repository -y "$1"
    sudo DEBIAN_FRONTEND=noninteractive apt-get -y update
    return 0
  fi

  return 1
}

clean_old_repo() {
dpkg -s 'osm-devops' &> /dev/null
if [ $? -eq 0 ]; then
  # Clean the previous repos that might exist
  sudo sed -i "/osm-download.etsi.org/d" /etc/apt/sources.list
fi
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
    sudo apt-get -y update || FATAL "Configured apt proxy, but couldn't run 'apt-get update'. Check ${OSM_APT_PROXY_FILE}"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

while getopts ":a:c:e:r:k:u:R:D:s:t:U:d:p:T:M:G:O:-: hy" o; do
    case "${o}" in
        D)
            DEVOPS_PATH="${OPTARG}"
            ;;
        r)
            REPOSITORY="${OPTARG}"
            ;;
        R)
            RELEASE="${OPTARG}"
            ;;
        u)
            REPOSITORY_BASE="${OPTARG}"
            ;;
        t)
            DOCKER_TAG="${OPTARG}"
            ;;
        -)
            [ "${OPTARG}" == "help" ] && usage && exit 0
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
        *)
            ;;
    esac
done

clean_old_repo
add_repo "deb [arch=amd64] $REPOSITORY_BASE/$RELEASE $REPOSITORY devops"
sudo DEBIAN_FRONTEND=noninteractive apt-get -qy update
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install osm-devops
$DEVOPS_PATH/installers/full_install_osm.sh -R $RELEASE -r $REPOSITORY -u $REPOSITORY_BASE -D $DEVOPS_PATH -t $DOCKER_TAG "$@"
