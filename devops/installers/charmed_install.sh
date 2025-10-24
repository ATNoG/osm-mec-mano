#! /bin/bash
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

# set -eux

LXD_VERSION=5.0
JUJU_VERSION=2.9
JUJU_AGENT_VERSION=2.9.43
K8S_CLOUD_NAME="k8s-cloud"
KUBECTL="microk8s.kubectl"
MICROK8S_VERSION=1.26
OSMCLIENT_VERSION=latest
IMAGES_OVERLAY_FILE=~/.osm/images-overlay.yaml
PASSWORD_OVERLAY_FILE=~/.osm/password-overlay.yaml
PATH=/snap/bin:${PATH}
OSM_DEVOPS="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. &> /dev/null && pwd )"
INSTALL_PLA=""
PLA_OVERLAY_FILE=~/.osm/pla-overlay.yaml

if [ -f ${OSM_DEVOPS}/common/all_funcs ] ; then
    source ${OSM_DEVOPS}/common/all_funcs
else
    function track(){
        true
    }
    function FATAL_TRACK(){
        exit 1
    }
fi

MODEL_NAME=osm

OSM_BUNDLE=ch:osm
OSM_HA_BUNDLE=ch:osm-ha
CHARMHUB_CHANNEL=latest/beta
unset TAG

function check_arguments(){
    while [ $# -gt 0 ] ; do
        case $1 in
            --bundle) BUNDLE="$2" ;;
            --overlay) OVERLAY="$2" ;;
            --k8s) KUBECFG="$2" ;;
            --vca) CONTROLLER="$2" ;;
            --small-profile) INSTALL_NOLXD=y;;
            --lxd) LXD_CLOUD="$2" ;;
            --lxd-cred) LXD_CREDENTIALS="$2" ;;
            --microstack) MICROSTACK=y ;;
            --ha) BUNDLE=$OSM_HA_BUNDLE ;;
            --tag) TAG="$2" ;;
            --registry) REGISTRY_INFO="$2" ;;
            --only-vca) ONLY_VCA=y ;;
            --pla) INSTALL_PLA=y ;;
        esac
        shift
    done

    # echo $BUNDLE $KUBECONFIG $LXDENDPOINT
}

function install_snaps(){
    if [ ! -v KUBECFG ]; then
        KUBEGRP="microk8s"
        sudo snap install microk8s --classic --channel=${MICROK8S_VERSION}/stable ||
          FATAL_TRACK k8scluster "snap install microk8s ${MICROK8S_VERSION}/stable failed"
        sudo usermod -a -G microk8s `whoami`
        # Workaround bug in calico MTU detection
        if [ ${DEFAULT_IF_MTU} -ne 1500 ] ; then
            sudo mkdir -p /var/lib/calico
            sudo ln -sf /var/snap/microk8s/current/var/lib/calico/mtu /var/lib/calico/mtu
        fi
        sudo cat /var/snap/microk8s/current/args/kube-apiserver | grep advertise-address || (
                echo "--advertise-address $DEFAULT_IP" | sudo tee -a /var/snap/microk8s/current/args/kube-apiserver
                sg ${KUBEGRP} -c microk8s.stop
                sg ${KUBEGRP} -c microk8s.start
            )
        mkdir -p ~/.kube
        sudo chown -f -R `whoami` ~/.kube
        sg ${KUBEGRP} -c "microk8s status --wait-ready"
        KUBECONFIG=~/.osm/microk8s-config.yaml
        sg ${KUBEGRP} -c "microk8s config" | tee ${KUBECONFIG}
        track k8scluster k8scluster_ok
    else
        KUBECTL="kubectl"
        sudo snap install kubectl --classic
        export KUBECONFIG=${KUBECFG}
        KUBEGRP=$(id -g -n)
    fi
    sudo snap install juju --classic --channel=$JUJU_VERSION/stable ||
    FATAL_TRACK juju "snap install juju ${JUJU_VERSION}/stable failed"
    track juju juju_ok
}

function bootstrap_k8s_lxd(){
    [ -v CONTROLLER ] && ADD_K8S_OPTS="--controller ${CONTROLLER}" && CONTROLLER_NAME=$CONTROLLER
    [ ! -v CONTROLLER ] && ADD_K8S_OPTS="--client" && BOOTSTRAP_NEEDED="yes" && CONTROLLER_NAME="osm-vca"

    if [ -v BOOTSTRAP_NEEDED ]; then
        CONTROLLER_PRESENT=$(juju controllers 2>/dev/null| grep ${CONTROLLER_NAME} | wc -l)
        if [ $CONTROLLER_PRESENT -ge 1 ]; then
            cat << EOF
Threre is already a VCA present with the installer reserved name of "${CONTROLLER_NAME}".
You may either explicitly use this VCA with the "--vca ${CONTROLLER_NAME}" option, or remove it
using this command:

   juju destroy-controller --release-storage --destroy-all-models -y ${CONTROLLER_NAME}

Please retry the installation once this conflict has been resolved.
EOF
            FATAL_TRACK bootstrap_k8s "VCA already present"
        fi
    else
        CONTROLLER_PRESENT=$(juju controllers 2>/dev/null| grep ${CONTROLLER_NAME} | wc -l)
        if [ $CONTROLLER_PRESENT -le 0 ]; then
            cat << EOF
Threre is no VCA present with the name "${CONTROLLER_NAME}".  Please specify a VCA
that exists, or remove the --vca ${CONTROLLER_NAME} option.

Please retry the installation with one of the solutions applied.
EOF
            FATAL_TRACK bootstrap_k8s "Requested VCA not present"
        fi
    fi

    if [ -v KUBECFG ]; then
        cat $KUBECFG | juju add-k8s $K8S_CLOUD_NAME $ADD_K8S_OPTS
        [ -v BOOTSTRAP_NEEDED ] && juju bootstrap $K8S_CLOUD_NAME $CONTROLLER_NAME \
            --config controller-service-type=loadbalancer \
            --agent-version=$JUJU_AGENT_VERSION
    else
        sg ${KUBEGRP} -c "echo ${DEFAULT_IP}-${DEFAULT_IP} | microk8s.enable metallb"
        sg ${KUBEGRP} -c "microk8s.enable ingress"
        sg ${KUBEGRP} -c "microk8s.enable hostpath-storage dns"
        TIME_TO_WAIT=30
        start_time="$(date -u +%s)"
        while true
        do
            now="$(date -u +%s)"
            if [[ $(( now - start_time )) -gt $TIME_TO_WAIT ]];then
                echo "Microk8s storage failed to enable"
                sg ${KUBEGRP} -c "microk8s.status"
                FATAL_TRACK bootstrap_k8s "Microk8s storage failed to enable"
            fi
            storage_status=`sg ${KUBEGRP} -c "microk8s.status -a storage"`
            if [[ $storage_status == "enabled" ]]; then
                break
            fi
            sleep 1
        done

        [ ! -v BOOTSTRAP_NEEDED ] && sg ${KUBEGRP} -c "microk8s.config" | juju add-k8s $K8S_CLOUD_NAME $ADD_K8S_OPTS
        [ -v BOOTSTRAP_NEEDED ] && sg ${KUBEGRP} -c \
            "juju bootstrap microk8s $CONTROLLER_NAME --config controller-service-type=loadbalancer --agent-version=$JUJU_AGENT_VERSION" \
            && K8S_CLOUD_NAME=microk8s
    fi
    track bootstrap_k8s bootstrap_k8s_ok

    if [ ! -v INSTALL_NOLXD ]; then
          if [ -v LXD_CLOUD ]; then
              if [ ! -v LXD_CREDENTIALS ]; then
                  echo "The installer needs the LXD server certificate if the LXD is external"
                  FATAL_TRACK bootstrap_lxd "No LXD certificate supplied"
              fi
          else
              LXDENDPOINT=$DEFAULT_IP
              LXD_CLOUD=~/.osm/lxd-cloud.yaml
              LXD_CREDENTIALS=~/.osm/lxd-credentials.yaml
              # Apply sysctl production values for optimal performance
              sudo cp /usr/share/osm-devops/installers/60-lxd-production.conf /etc/sysctl.d/60-lxd-production.conf
              sudo sysctl --system
              # Install LXD snap
              sudo apt-get remove --purge -y liblxc1 lxc-common lxcfs lxd lxd-client
              snap info lxd | grep installed > /dev/null
              if [ $? -eq 0 ]; then
                sudo snap refresh lxd --channel $LXD_VERSION/stable
              else
                sudo snap install lxd --channel $LXD_VERSION/stable
              fi
              # Configure LXD
              sudo usermod -a -G lxd `whoami`
              cat /usr/share/osm-devops/installers/lxd-preseed.conf | sed 's/^config: {}/config:\n  core.https_address: '$LXDENDPOINT':8443/' | sg lxd -c "lxd init --preseed"
              sg lxd -c "lxd waitready"

              cat << EOF > $LXD_CLOUD
clouds:
  lxd-cloud:
    type: lxd
    auth-types: [certificate]
    endpoint: "https://$LXDENDPOINT:8443"
    config:
      ssl-hostname-verification: false
EOF
              openssl req -nodes -new -x509 -keyout ~/.osm/client.key -out ~/.osm/client.crt -days 365 -subj "/C=FR/ST=Nice/L=Nice/O=ETSI/OU=OSM/CN=osm.etsi.org"
              cat << EOF > $LXD_CREDENTIALS
credentials:
  lxd-cloud:
    lxd-cloud:
      auth-type: certificate
      server-cert: /var/snap/lxd/common/lxd/server.crt
      client-cert: ~/.osm/client.crt
      client-key: ~/.osm/client.key
EOF
              lxc config trust add local: ~/.osm/client.crt
          fi

          juju add-cloud -c $CONTROLLER_NAME lxd-cloud $LXD_CLOUD --force
          juju add-credential -c $CONTROLLER_NAME lxd-cloud -f $LXD_CREDENTIALS
          sg lxd -c "lxd waitready"
          juju controller-config features=[k8s-operators]
          track bootstrap_lxd bootstrap_lxd_ok
    fi
}

function deploy_charmed_osm(){
    if [ -v REGISTRY_INFO ] ; then
        registry_parts=(${REGISTRY_INFO//@/ })
        if [ ${#registry_parts[@]} -eq 1 ] ; then
            # No credentials supplied
            REGISTRY_USERNAME=""
            REGISTRY_PASSWORD=""
            REGISTRY_URL=${registry_parts[0]}
        else
            credentials=${registry_parts[0]}
            credential_parts=(${credentials//:/ })
            REGISTRY_USERNAME=${credential_parts[0]}
            REGISTRY_PASSWORD=${credential_parts[1]}
            REGISTRY_URL=${registry_parts[1]}
        fi
        # Ensure the URL ends with a /
        case $REGISTRY_URL in
            */) ;;
            *) REGISTRY_URL=${REGISTRY_URL}/
        esac
    fi

    echo "Creating OSM model"
    if [ -v KUBECFG ]; then
        juju add-model $MODEL_NAME $K8S_CLOUD_NAME
    else
        sg ${KUBEGRP} -c "juju add-model $MODEL_NAME $K8S_CLOUD_NAME"
    fi
    echo "Deploying OSM with charms"
    images_overlay=""
    if [ -v REGISTRY_URL ]; then
       [ ! -v TAG ] && TAG='latest'
    fi
    [ -v TAG ] && generate_images_overlay && images_overlay="--overlay $IMAGES_OVERLAY_FILE"

    if [ -v OVERLAY ]; then
        extra_overlay="--overlay $OVERLAY"
    fi
    echo "Creating Password Overlay"

    generate_password_overlay && secret_overlay="--overlay $PASSWORD_OVERLAY_FILE"

    [ -n "$INSTALL_PLA" ] && create_pla_overlay && pla_overlay="--overlay $PLA_OVERLAY_FILE"

    if [ -v BUNDLE ]; then
        juju deploy --trust --channel $CHARMHUB_CHANNEL -m $MODEL_NAME $BUNDLE $images_overlay $extra_overlay $secret_overlay $pla_overlay
    else
        juju deploy --trust --channel $CHARMHUB_CHANNEL -m $MODEL_NAME $OSM_BUNDLE $images_overlay $extra_overlay $secret_overlay $pla_overlay
    fi

    if [ ! -v KUBECFG ]; then
        API_SERVER=${DEFAULT_IP}
    else
        API_SERVER=$(kubectl config view --minify | grep server | cut -f 2- -d ":" | tr -d " ")
        proto="$(echo $API_SERVER | grep :// | sed -e's,^\(.*://\).*,\1,g')"
        url="$(echo ${API_SERVER/$proto/})"
        user="$(echo $url | grep @ | cut -d@ -f1)"
        hostport="$(echo ${url/$user@/} | cut -d/ -f1)"
        API_SERVER="$(echo $hostport | sed -e 's,:.*,,g')"
    fi
    # Configure VCA Integrator
    if [ ! -v INSTALL_NOLXD ]; then
        juju config vca \
          k8s-cloud=microk8s \
          lxd-cloud=lxd-cloud:lxd-cloud \
          controllers="`cat ~/.local/share/juju/controllers.yaml`" \
          accounts="`cat ~/.local/share/juju/accounts.yaml`" \
          public-key="`cat ~/.local/share/juju/ssh/juju_id_rsa.pub`"
    else
        juju config vca \
          k8s-cloud=microk8s \
          controllers="`cat ~/.local/share/juju/controllers.yaml`" \
          accounts="`cat ~/.local/share/juju/accounts.yaml`" \
          public-key="`cat ~/.local/share/juju/ssh/juju_id_rsa.pub`"
    fi
    # Expose OSM services
    juju config -m $MODEL_NAME nbi external-hostname=nbi.${API_SERVER}.nip.io
    juju config -m $MODEL_NAME ng-ui external-hostname=ui.${API_SERVER}.nip.io
    juju config -m $MODEL_NAME grafana site_url=https://grafana.${API_SERVER}.nip.io
    juju config -m $MODEL_NAME prometheus site_url=https://prometheus.${API_SERVER}.nip.io

    echo "Waiting for deployment to finish..."
    check_osm_deployed
    grafana_leader=`juju status -m $MODEL_NAME grafana | grep "*" | cut -d "*" -f 1`
    grafana_admin_password=`juju run -m $MODEL_NAME --unit $grafana_leader "echo \\$GF_SECURITY_ADMIN_PASSWORD"`
    juju config -m $MODEL_NAME mon grafana-password=$grafana_admin_password
    check_osm_deployed
    echo "OSM with charms deployed"
}

function check_osm_deployed() {
    TIME_TO_WAIT=600
    start_time="$(date -u +%s)"
    total_service_count=15
    [ -n "$INSTALL_PLA" ] && total_service_count=$((total_service_count + 1))
    previous_count=0
    while true
    do
        service_count=$(juju status --format json -m $MODEL_NAME | jq '.applications[]."application-status".current' | grep active | wc -l)
        echo "$service_count / $total_service_count services active"
        if [ $service_count -eq $total_service_count ]; then
            break
        fi
        if [ $service_count -ne $previous_count ]; then
            previous_count=$service_count
            start_time="$(date -u +%s)"
        fi
        now="$(date -u +%s)"
        if [[ $(( now - start_time )) -gt $TIME_TO_WAIT ]];then
            echo "Timed out waiting for OSM services to become ready"
            FATAL_TRACK deploy_osm "Timed out waiting for services to become ready"
        fi
        sleep 10
    done
}

function generate_password_overlay() {
    # prometheus
    web_config_password=`openssl rand -hex 16`
    # keystone
    keystone_db_password=`openssl rand -hex 16`
    keystone_admin_password=`openssl rand -hex 16`
    keystone_service_password=`openssl rand -hex 16`
    #  mariadb
    mariadb_password=`openssl rand -hex 16`
    mariadb_root_password=`openssl rand -hex 16`
    cat << EOF > /tmp/password-overlay.yaml
applications:
  prometheus:
    options:
      web_config_password: $web_config_password
  keystone:
    options:
      keystone-db-password: $keystone_db_password
      admin-password: $keystone_admin_password
      service-password: $keystone_service_password
  mariadb:
    options:
      password: $mariadb_password
      root_password: $mariadb_root_password
EOF
    mv /tmp/password-overlay.yaml $PASSWORD_OVERLAY_FILE
}

function create_pla_overlay(){
    echo "Creating PLA Overlay"
    [ $BUNDLE == $OSM_HA_BUNDLE ] && scale=3 || scale=1
    cat << EOF > /tmp/pla-overlay.yaml
applications:
  pla:
    charm: osm-pla
    channel: latest/stable
    scale: $scale
    series: kubernetes
    options:
      log_level: DEBUG
    resources:
      image: opensourcemano/pla:testing-daily
relations:
  - - pla:kafka
    - kafka:kafka
  - - pla:mongodb
    - mongodb:database
EOF
     mv /tmp/pla-overlay.yaml $PLA_OVERLAY_FILE
}

function generate_images_overlay(){
    echo "applications:" > /tmp/images-overlay.yaml

    charms_with_resources="nbi lcm mon pol ng-ui ro"
    [ -n "$INSTALL_PLA" ] && charms_with_resources+=" pla"
    for charm in $charms_with_resources; do
        cat << EOF > /tmp/${charm}_registry.yaml
registrypath: ${REGISTRY_URL}opensourcemano/${charm}:$TAG
EOF
        if [ ! -z "$REGISTRY_USERNAME" ] ; then
            echo username: $REGISTRY_USERNAME >> /tmp/${charm}_registry.yaml
            echo password: $REGISTRY_PASSWORD >> /tmp/${charm}_registry.yaml
        fi

        cat << EOF >> /tmp/images-overlay.yaml
  ${charm}:
    resources:
      ${charm}-image: /tmp/${charm}_registry.yaml

EOF
    done
    ch_charms_with_resources="keystone"
    for charm in $ch_charms_with_resources; do
        cat << EOF > /tmp/${charm}_registry.yaml
registrypath: ${REGISTRY_URL}opensourcemano/${charm}:$TAG
EOF
        if [ ! -z "$REGISTRY_USERNAME" ] ; then
            echo username: $REGISTRY_USERNAME >> /tmp/${charm}_registry.yaml
            echo password: $REGISTRY_PASSWORD >> /tmp/${charm}_registry.yaml
        fi

        cat << EOF >> /tmp/images-overlay.yaml
  ${charm}:
    resources:
      ${charm}-image: /tmp/${charm}_registry.yaml

EOF
    done

    mv /tmp/images-overlay.yaml $IMAGES_OVERLAY_FILE
}

function refresh_osmclient_snap() {
    osmclient_snap_install_refresh refresh
}

function install_osm_client_snap() {
    osmclient_snap_install_refresh install
}

function osmclient_snap_install_refresh() {
    channel_preference="stable candidate beta edge"
    for channel in $channel_preference; do
        echo "Trying to install osmclient from channel $OSMCLIENT_VERSION/$channel"
        sudo snap $1 osmclient --channel $OSMCLIENT_VERSION/$channel 2> /dev/null && echo osmclient snap installed && break
    done
}
function install_osmclient() {
    snap info osmclient | grep -E ^installed: && refresh_osmclient_snap || install_osm_client_snap
}

function add_local_k8scluster() {
    osm --all-projects vim-create \
      --name _system-osm-vim \
      --account_type dummy \
      --auth_url http://dummy \
      --user osm --password osm --tenant osm \
      --description "dummy" \
      --config '{management_network_name: mgmt}'
    tmpfile=$(mktemp --tmpdir=${HOME})
    cp ${KUBECONFIG} ${tmpfile}
    osm --all-projects k8scluster-add \
      --creds ${tmpfile} \
      --vim _system-osm-vim \
      --k8s-nets '{"net1": null}' \
      --version '1.19' \
      --description "OSM Internal Cluster" \
      _system-osm-k8s
    rm -f ${tmpfile}
}

function install_microstack() {
    sudo snap install microstack --beta --devmode

    CHECK=$(microstack.openstack server list)
    if [ $? -ne 0 ] ; then
        if [[ $CHECK == *"not initialized"* ]]; then
            echo "Setting MicroStack dashboard to listen to port 8080"
            sudo snap set microstack config.network.ports.dashboard=8080
            echo "Initializing MicroStack.  This can take several minutes"
            sudo microstack.init --auto --control
        fi
    fi

    sudo snap alias microstack.openstack openstack

    echo "Updating default security group in MicroStack to allow all access"

    for i in $(microstack.openstack security group list | awk '/default/{ print $2 }'); do
        for PROTO in icmp tcp udp ; do
            echo "  $PROTO ingress"
            CHECK=$(microstack.openstack security group rule create $i --protocol $PROTO --remote-ip 0.0.0.0/0 2>&1)
            if [ $? -ne 0 ] ; then
                if [[ $CHECK != *"409"* ]]; then
                    echo "Error creating ingress rule for $PROTO"
                    echo $CHECK
                fi
            fi
        done
    done

    microstack.openstack network show osm-ext &>/dev/null
    if [ $? -ne 0 ]; then
       echo "Creating osm-ext network with router to bridge to MicroStack external network"
        microstack.openstack network create --enable --no-share osm-ext
        microstack.openstack subnet create osm-ext-subnet --network osm-ext --dns-nameserver 8.8.8.8 \
              --subnet-range 172.30.0.0/24
        microstack.openstack router create external-router
        microstack.openstack router add subnet external-router osm-ext-subnet
        microstack.openstack router set --external-gateway external external-router
    fi

    microstack.openstack image list | grep ubuntu20.04 &> /dev/null
    if [ $? -ne 0 ] ; then
        echo "Fetching Ubuntu 20.04 image and upLoading to MicroStack"
        wget -q -O- https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img \
            | microstack.openstack image create --public --container-format=bare \
             --disk-format=qcow2 ubuntu20.04 | grep status
    fi

    if [ ! -f ~/.ssh/microstack ]; then
        ssh-keygen -t rsa -N "" -f ~/.ssh/microstack
        microstack.openstack keypair create --public-key ~/.ssh/microstack.pub microstack
    fi

    echo "Creating VIM microstack-site in OSM"
    . /var/snap/microstack/common/etc/microstack.rc

    osm vim-create \
        --name microstack-site \
        --user "$OS_USERNAME" \
        --password "$OS_PASSWORD" \
        --auth_url "$OS_AUTH_URL" \
        --tenant "$OS_USERNAME" \
        --account_type openstack \
        --config='{use_floating_ip: True,
                   insecure: True,
                   keypair: microstack,
                   management_network_name: osm-ext}'
}

DEFAULT_IF=`ip route list match 0.0.0.0 | awk '{print $5; exit}'`
DEFAULT_IP=`ip -o -4 a |grep ${DEFAULT_IF}|awk '{split($4,a,"/"); print a[1]; exit}'`
DEFAULT_IF_MTU=`ip a show ${DEFAULT_IF} | grep mtu | awk '{print $5}'`

check_arguments $@
mkdir -p ~/.osm
install_snaps
bootstrap_k8s_lxd
if [ -v ONLY_VCA ]; then
    HOME=/home/$USER
    k8scloud=microk8s
    lxdcloud=lxd-cloud:lxd-cloud
    controllers="`cat $HOME/.local/share/juju/controllers.yaml`"
    accounts="`cat $HOME/.local/share/juju/accounts.yaml`"
    publickey="`cat $HOME/.local/share/juju/ssh/juju_id_rsa.pub`"
    echo "Use the following command to register the installed VCA to your OSM VCA integrator charm"
    echo -e "  juju config vca \\\n    k8s-cloud=$k8scloud \\\n    lxd-cloud=$lxdcloud \\\n    controllers=$controllers \\\n    accounts=$accounts \\\n    public-key=$publickey"
    track deploy_osm deploy_vca_only_ok
else
    deploy_charmed_osm
    track deploy_osm deploy_osm_services_k8s_ok
    install_osmclient
    track osmclient osmclient_ok
    export OSM_HOSTNAME=$(juju config -m $MODEL_NAME nbi external-hostname):443
    export OSM_PASSWORD=$keystone_admin_password
    sleep 10
    add_local_k8scluster
    track final_ops add_local_k8scluster_ok
    if [ -v MICROSTACK ]; then
        install_microstack
        track final_ops install_microstack_ok
    fi

    echo "Your installation is now complete, follow these steps for configuring the osmclient:"
    echo
    echo "1. Create the OSM_HOSTNAME environment variable with the NBI IP"
    echo
    echo "export OSM_HOSTNAME=$OSM_HOSTNAME"
    echo "export OSM_PASSWORD=$OSM_PASSWORD"
    echo
    echo "2. Add the previous commands to your .bashrc for other Shell sessions"
    echo
    echo "echo \"export OSM_HOSTNAME=$OSM_HOSTNAME\" >> ~/.bashrc"
    echo "echo \"export OSM_PASSWORD=$OSM_PASSWORD\" >> ~/.bashrc"
    echo
    echo "3. Login OSM GUI by using admin password: $OSM_PASSWORD"
    echo
    echo "DONE"
    track end
fi

