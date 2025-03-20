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
    echo -e "Install Juju for OSM"
    echo -e "  OPTIONS"
    echo -e "     -h / --help:    print this help"
    echo -e "     -D <devops path> use local devops installation path"
    echo -e "     -s <stack name> or <namespace>  user defined stack name when installed using swarm or namespace when installed using k8s, default is osm"
    echo -e "     -H <VCA host>   use specific juju host controller IP"
    echo -e "     -S <VCA secret> use VCA/juju secret key"
    echo -e "     -P <VCA pubkey> use VCA/juju public key file"
    echo -e "     -l:             LXD cloud yaml file"
    echo -e "     -L:             LXD credentials yaml file"
    echo -e "     -K:             Specifies the name of the controller to use - The controller must be already bootstrapped"
    echo -e "     --debug:        debug mode"
    echo -e "     --cachelxdimages:  cache local lxd images, create cronjob for that cache (will make installation longer)"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function update_juju_images(){
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    crontab -l | grep update-juju-lxc-images || (crontab -l 2>/dev/null; echo "0 4 * * 6 $USER ${OSM_DEVOPS}/installers/update-juju-lxc-images --xenial --bionic") | crontab -
    ${OSM_DEVOPS}/installers/update-juju-lxc-images --xenial --bionic
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function install_juju_client() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo "Installing juju client"
    sudo snap install juju --classic --channel=$JUJU_VERSION/stable
    [[ ":$PATH": != *":/snap/bin:"* ]] && PATH="/snap/bin:${PATH}"
    [ -n "$INSTALL_CACHELXDIMAGES" ] && update_juju_images
    echo "Finished installation of juju client"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
    return 0
}

function juju_createcontroller_k8s(){
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    cat $HOME/.kube/config | juju add-k8s $OSM_VCA_K8S_CLOUDNAME --client \
    || FATAL_TRACK juju "Failed to add K8s endpoint and credential for client in cloud $OSM_VCA_K8S_CLOUDNAME"

    JUJU_BOOTSTRAP_OPTS=""
    if [ -n "${OSM_BEHIND_PROXY}" ] ; then
        K8S_SVC_CLUSTER_IP=$(kubectl get svc/kubernetes -o jsonpath='{.spec.clusterIP}')
        NO_PROXY="${NO_PROXY},${K8S_SVC_CLUSTER_IP},.svc,.cluster.local"
        mkdir -p /tmp/.osm
        JUJU_MODEL_CONFIG_FILE=/tmp/.osm/model-config.yaml
        cat << EOF > $JUJU_MODEL_CONFIG_FILE
apt-http-proxy: ${HTTP_PROXY}
apt-https-proxy: ${HTTPS_PROXY}
juju-http-proxy: ${HTTP_PROXY}
juju-https-proxy: ${HTTPS_PROXY}
juju-no-proxy: ${NO_PROXY}
snap-http-proxy: ${HTTP_PROXY}
snap-https-proxy: ${HTTPS_PROXY}
EOF
        JUJU_BOOTSTRAP_OPTS="--model-default /tmp/.osm/model-config.yaml"
    fi
    juju bootstrap -v --debug $OSM_VCA_K8S_CLOUDNAME $OSM_NAMESPACE  \
            --config controller-service-type=loadbalancer \
            --agent-version=$JUJU_AGENT_VERSION \
            ${JUJU_BOOTSTRAP_OPTS} \
    || FATAL_TRACK juju "Failed to bootstrap controller $OSM_NAMESPACE in cloud $OSM_VCA_K8S_CLOUDNAME"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function juju_addlxd_cloud(){
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    mkdir -p /tmp/.osm
    OSM_VCA_CLOUDNAME="lxd-cloud"
    LXDENDPOINT=$DEFAULT_IP
    LXD_CLOUD=/tmp/.osm/lxd-cloud.yaml
    LXD_CREDENTIALS=/tmp/.osm/lxd-credentials.yaml

    cat << EOF > $LXD_CLOUD
clouds:
  $OSM_VCA_CLOUDNAME:
    type: lxd
    auth-types: [certificate]
    endpoint: "https://$LXDENDPOINT:8443"
    config:
      ssl-hostname-verification: false
EOF
    openssl req -nodes -new -x509 -keyout /tmp/.osm/client.key -out /tmp/.osm/client.crt -days 365 -subj "/C=FR/ST=Nice/L=Nice/O=ETSI/OU=OSM/CN=osm.etsi.org"
    cat << EOF > $LXD_CREDENTIALS
credentials:
  $OSM_VCA_CLOUDNAME:
    lxd-cloud:
      auth-type: certificate
      server-cert: /var/snap/lxd/common/lxd/server.crt
      client-cert: /tmp/.osm/client.crt
      client-key: /tmp/.osm/client.key
EOF
    lxc config trust add local: /tmp/.osm/client.crt
    juju add-cloud -c $OSM_NAMESPACE $OSM_VCA_CLOUDNAME $LXD_CLOUD --force
    juju add-credential -c $OSM_NAMESPACE $OSM_VCA_CLOUDNAME -f $LXD_CREDENTIALS
    sg lxd -c "lxd waitready"
    juju controller-config features=[k8s-operators]
    if [ -n "${OSM_BEHIND_PROXY}" ] ; then
        if [ -n "${HTTP_PROXY}" ]; then
            juju model-default lxd-cloud apt-http-proxy="$HTTP_PROXY"
            juju model-default lxd-cloud juju-http-proxy="$HTTP_PROXY"
            juju model-default lxd-cloud snap-http-proxy="$HTTP_PROXY"
        fi
        if [ -n "${HTTPS_PROXY}" ]; then
            juju model-default lxd-cloud apt-https-proxy="$HTTPS_PROXY"
            juju model-default lxd-cloud juju-https-proxy="$HTTPS_PROXY"
            juju model-default lxd-cloud snap-https-proxy="$HTTPS_PROXY"
        fi
        [ -n "${NO_PROXY}" ] && juju model-default lxd-cloud juju-no-proxy="$NO_PROXY"
    fi
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

#Safe unattended install of iptables-persistent
function check_install_iptables_persistent(){
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo -e "\nChecking required packages: iptables-persistent"
    if ! dpkg -l iptables-persistent &>/dev/null; then
        echo -e "    Not installed.\nInstalling iptables-persistent requires root privileges"
        echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
        echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
        sudo apt-get -yq install iptables-persistent
    fi
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function juju_createproxy() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    check_install_iptables_persistent

    if ! sudo iptables -t nat -C PREROUTING -p tcp -m tcp -d $DEFAULT_IP --dport 17070 -j DNAT --to-destination $OSM_VCA_HOST; then
        sudo iptables -t nat -A PREROUTING -p tcp -m tcp -d $DEFAULT_IP --dport 17070 -j DNAT --to-destination $OSM_VCA_HOST
        sudo netfilter-persistent save
    fi
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

DEBUG_INSTALL=""
INSTALL_CACHELXDIMAGES=""
INSTALL_NOJUJU=""
JUJU_AGENT_VERSION=2.9.43
JUJU_VERSION=2.9
OSM_BEHIND_PROXY=""
OSM_DEVOPS=
OSM_NAMESPACE=osm
OSM_VCA_HOST=
OSM_VCA_CLOUDNAME="localhost"
OSM_VCA_K8S_CLOUDNAME="k8scloud"
RE_CHECK='^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'

while getopts ":D:i:s:H:l:L:K:-: hP" o; do
    case "${o}" in
        D)
            OSM_DEVOPS="${OPTARG}"
            ;;
        i)
            DEFAULT_IP="${OPTARG}"
            ;;
        s)
            OSM_NAMESPACE="${OPTARG}" && [[ ! "${OPTARG}" =~ $RE_CHECK ]] && echo "Namespace $OPTARG is invalid. Regex used for validation is $RE_CHECK" && exit 0
            ;;
        H)
            OSM_VCA_HOST="${OPTARG}"
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
        P)
            OSM_BEHIND_PROXY="y"
            ;;
        -)
            [ "${OPTARG}" == "help" ] && usage && exit 0
            [ "${OPTARG}" == "debug" ] && DEBUG_INSTALL="--debug" && continue
            [ "${OPTARG}" == "cachelxdimages" ] && INSTALL_CACHELXDIMAGES="y" && continue
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
        *)
            usage && exit 1
            ;;
    esac
done

source $OSM_DEVOPS/common/logging
source $OSM_DEVOPS/common/track

echo "DEBUG_INSTALL=$DEBUG_INSTALL"
echo "DEFAULT_IP=$DEFAULT_IP"
echo "OSM_BEHIND_PROXY=$OSM_BEHIND_PROXY"
echo "OSM_DEVOPS=$OSM_DEVOPS"
echo "HOME=$HOME"

[ -z "$INSTALL_NOJUJU" ] && install_juju_client
track juju juju_client_ok

if [ -z "$OSM_VCA_HOST" ]; then
    if [ -z "$CONTROLLER_NAME" ]; then
        juju_createcontroller_k8s
        juju_addlxd_cloud
        if [ -n "$LXD_CLOUD_FILE" ]; then
            [ -z "$LXD_CRED_FILE" ] && FATAL_TRACK juju "The installer needs the LXD credential yaml if the LXD is external"
            OSM_VCA_CLOUDNAME="lxd-cloud"
            juju add-cloud $OSM_VCA_CLOUDNAME $LXD_CLOUD_FILE --force || juju update-cloud $OSM_VCA_CLOUDNAME --client -f $LXD_CLOUD_FILE
            juju add-credential $OSM_VCA_CLOUDNAME -f $LXD_CRED_FILE || juju update-credential $OSM_VCA_CLOUDNAME lxd-cloud-creds -f $LXD_CRED_FILE
        fi
        juju_createproxy
    else
        OSM_VCA_CLOUDNAME="lxd-cloud"
        if [ -n "$LXD_CLOUD_FILE" ]; then
            [ -z "$LXD_CRED_FILE" ] && FATAL_TRACK juju "The installer needs the LXD credential yaml if the LXD is external"
            juju add-cloud -c $CONTROLLER_NAME $OSM_VCA_CLOUDNAME $LXD_CLOUD_FILE --force || juju update-cloud lxd-cloud -c $CONTROLLER_NAME -f $LXD_CLOUD_FILE
            juju add-credential -c $CONTROLLER_NAME $OSM_VCA_CLOUDNAME -f $LXD_CRED_FILE || juju update-credential lxd-cloud -c $CONTROLLER_NAME -f $LXD_CRED_FILE
        else
            mkdir -p ~/.osm
            cat << EOF > ~/.osm/lxd-cloud.yaml
clouds:
  lxd-cloud:
    type: lxd
    auth-types: [certificate]
    endpoint: "https://$DEFAULT_IP:8443"
    config:
      ssl-hostname-verification: false
EOF
            openssl req -nodes -new -x509 -keyout ~/.osm/client.key -out ~/.osm/client.crt -days 365 -subj "/C=FR/ST=Nice/L=Nice/O=ETSI/OU=OSM/CN=osm.etsi.org"
            local server_cert=`cat /var/snap/lxd/common/lxd/server.crt | sed 's/^/        /'`
            local client_cert=`cat ~/.osm/client.crt | sed 's/^/        /'`
            local client_key=`cat ~/.osm/client.key | sed 's/^/        /'`
            cat << EOF > ~/.osm/lxd-credentials.yaml
credentials:
  lxd-cloud:
    lxd-cloud:
      auth-type: certificate
      server-cert: |
$server_cert
      client-cert: |
$client_cert
      client-key: |
$client_key
EOF
            lxc config trust add local: ~/.osm/client.crt
            juju add-cloud -c $CONTROLLER_NAME $OSM_VCA_CLOUDNAME ~/.osm/lxd-cloud.yaml --force || juju update-cloud lxd-cloud -c $CONTROLLER_NAME -f ~/.osm/lxd-cloud.yaml
            juju add-credential -c $CONTROLLER_NAME $OSM_VCA_CLOUDNAME -f ~/.osm/lxd-credentials.yaml || juju update-credential lxd-cloud -c $CONTROLLER_NAME -f ~/.osm/lxd-credentials.yaml
        fi
    fi
    [ -z "$CONTROLLER_NAME" ] && OSM_VCA_HOST=`sg lxd -c "juju show-controller $OSM_NAMESPACE"|grep api-endpoints|awk -F\' '{print $2}'|awk -F\: '{print $1}'`
    [ -n "$CONTROLLER_NAME" ] && OSM_VCA_HOST=`juju show-controller $CONTROLLER_NAME |grep api-endpoints|awk -F\' '{print $2}'|awk -F\: '{print $1}'`
    [ -z "$OSM_VCA_HOST" ] && FATAL_TRACK juju "Cannot obtain juju controller IP address"
fi
track juju juju_controller_ok
