#!/bin/bash
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

APT_PROXY=""
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
HTTPDDIR="${HOME}/.osm/httpd"
HTTPPORT=8000
KUBECFG="~/.osm/microk8s-config.yaml"
NO_CACHE=""
OPENSTACKRC="/var/snap/microstack/common/etc/microstack.rc"
REGISTRY="localhost:32000"
ROOTDIR="$( cd "${DIR}/../../" &> /dev/null && pwd)"
OSM_TESTS_IMAGE_TAG="devel"

function check_arguments(){
    while [ $# -gt 0 ] ; do
        case $1 in
            --debug) set -x ;;
            --apt-proxy) APT_PROXY="$2" && shift ;;
            --help | -h) show_help && exit 0 ;;
            --httpddir) HTTPDDIR="$2" && shift;;
            --install-local-registry) 'install_local_registry' ;;
            --install-microstack) 'install_microstack' ;;
            --install-qhttpd) INSTALL_HTTPD='install_qhttpd' ;;
            --run-httpserver) INSTALL_HTTPD='run_httpserver' ;;
            --kubecfg) KUBECFG="$2" && shift ;;
            --module) TARGET_MODULE="$2" && shift;;
            --no-cache) NO_CACHE="--no-cache" ;;
            --openstackrc) OPENSTACKRC="$2" && shift ;;
            --registry) REGISTRY="$2" && shift;;
            --robot-local-mounts) ROBOT_LOCAL=YES ;;
            --run-tests) TESTS=YES ;;
            --vim-vca) VIM_VCA="$2" && shift;;
            --osm-tests-image-tag) OSM_TESTS_IMAGE_TAG="$2" && shift;;
            stage-2) STAGE_2='stage_2 ${TARGET_MODULE}' ;;
            stage-3) STAGE_3='stage_3 ${TARGET_MODULE}' ;;
            registry-push) REGISTRY_PUSH='local_registry_push ${TARGET_MODULE}' ;;
            install-osm) INSTALL_OSM='install_osm' ;;
            start-robot) START_ROBOT='start_robot' ;;
            update-install) UPDATE_INSTALL='update_osm_module ${TARGET_MODULE}'
                 REGISTRY_PUSH='local_registry_push ${TARGET_MODULE}' ;;
            *)  echo "Unknown option $1"
                show_help
                exit 1;;
        esac
        shift
    done
}

function show_help() {
    cat << EOF
Usage: $0 [OPTIONS]
Perform a local build and potential installation of OSM from sources, using the
same process as Jenkins.

OPTIONS:
  --help                        display this help message
  --apt-proxy                   provide an apt proxy to docker build steps
  --debug                       enable set -x for this script
  --install-local-registry      install and enable Microk8s local registry on port 32000
  --install-microstack          install Microstack and configure to run robot tests
  --install-qhttpd              (deprecated, use --run-httpserver instead) install QHTTPD as an HTTP server on port ${HTTPPORT}
  --run-httpserver              run HTTP server on port ${HTTPPORT}
  --kubecfg                     path to kubecfg.yaml (uses Charmed OSM by default)
  --no-cache                    do not use any cache when building docker images
  --module                      only build this comma delimited list of modules
  --openstackrc                 path to Openstack RC file (uses Microstack by default)
  --registry                    use this alternate docker registry
  --run-tests                   run stage 2 tests
  --vim-vca                     name of the a vca registered in OSM to use in the VIM account
  --osm-tests-image-tag         tag to be used in the osm/tests docker image
  stage-2                       run the stage 2 build
  stage-3                       run the stage 3 build
  registry-push                 push to the local registry
  install-osm                   perform full installation of Charmed OSM from registry
  start-robot                   start the Robot test container and leave you at prompt
  update-install                update Charmed OSM with new module container

A typical use could be the following:

Let's assume that we have different repos cloned in the folder workspace:

  cd workspace
  git clone https://osm.etsi.org/gerrit/osm/devops
  git clone https://osm.etsi.org/gerrit/osm/NBI
  git clone https://osm.etsi.org/gerrit/osm/LCM
  git clone "https://osm.etsi.org/gerrit/osm/RO
  git clone "https://osm.etsi.org/gerrit/osm/common
  git clone "https://osm.etsi.org/gerrit/osm/IM
  git clone "https://osm.etsi.org/gerrit/osm/N2VC

First we run a light HTTP server to serve the artifacts:

  devops/tools/local-build.sh --run-httpserver

Then we generate the artifacts (debian packages) for the different repos: common, IM, N2VC, RO, LCM, NBI

  devops/tools/local-build.sh --module common,IM,N2VC,RO,LCM,NBI stage-2

Then new docker images are generated locally with the tag "devel" (e.g.: opensourcemano/lcm:devel):

  devops/tools/local-build.sh --module RO,LCM,NBI stage-3

Finally, the deployment of OSM will have to be updated to use the new docker images.

EOF
}

function print_section() {
        echo "$@"
}

function install_local_registry() {
    sudo snap install microk8s --classic
    microk8s status --wait-ready
    microk8s.enable registry
}

function install_microstack() {
    sudo snap install microstack --devmode --edge
    sudo snap set microstack config.network.ports.dashboard=8080
    sudo microstack.init --auto --control

    sudo snap alias microstack.openstack openstack
    . /var/snap/microstack/common/etc/microstack.rc

    for i in $(microstack.openstack security group list | awk '/default/{ print $2 }'); do
        microstack.openstack security group rule create $i --protocol icmp --remote-ip 0.0.0.0/0
        microstack.openstack security group rule create $i --protocol tcp --remote-ip 0.0.0.0/0
    done

    microstack.openstack network create --enable --no-share osm-ext
    microstack.openstack subnet create osm-ext-subnet --network osm-ext --dns-nameserver 8.8.8.8 \
              --subnet-range 172.30.0.0/24
    microstack.openstack router create external-router
    microstack.openstack router add subnet external-router osm-ext-subnet
    microstack.openstack router set --external-gateway external external-router

    curl -L https://github.com/cirros-dev/cirros/releases/download/0.3.5/cirros-0.3.5-x86_64-disk.img \
        | microstack.openstack image create --public --container-format=bare \
         --disk-format=qcow2 cirros-0.3.5-x86_64-disk.img
    curl https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img \
        | microstack.openstack image create --public --container-format=bare \
         --disk-format=qcow2 ubuntu16.04
    curl https://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img \
        | microstack.openstack image create --public --container-format=bare \
         --disk-format=qcow2 US1604
    curl https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img \
        | microstack.openstack image create --public --container-format=bare \
         --disk-format=qcow2 ubuntu18.04
    curl https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img \
        | microstack.openstack image create --public --container-format=bare \
         --disk-format=qcow2 ubuntu20.04
}

function create_httpddir() {
    mkdir -p ${HTTPDDIR}
}

function install_qhttpd() {
    sudo snap install qhttp
    EXISTING_PID=$(ps auxw | grep "http.server $HTTPPORT" | grep -v grep | awk '{print $2}')
    if [ ! -z $EXISTING_PID ] ; then
        kill $EXISTING_PID
    fi
    qhttp -p ${HTTPPORT} &
}

function run_httpserver() {
    EXISTING_PID=$(ps auxw | grep "http.server $HTTPPORT" | grep -v grep | awk '{print $2}')
    if [ ! -z $EXISTING_PID ] ; then
        kill $EXISTING_PID
    fi
    nohup python3 -m http.server ${HTTPPORT} --directory "${HTTPDDIR}" &>/dev/null &
}

function stage_2() {
    print_section "Performing Stage 2"
    MODULES="common devops IM LCM MON N2VC NBI NG-UI NG-SA osmclient RO tests"
    if [ ! -z ${1} ] ; then
        POSSIBLE_MODULES=$(echo ${1} | sed "s/,/ /g")
        for MODULE in ${POSSIBLE_MODULES}; do
            if ! echo "${MODULES}" | grep -q "${MODULE}" ; then
                echo "Unknown stage 2 module ${MODULE}"
                echo "Must be one of ${MODULES}"
                exit 1
            fi
        done
        MODULES=${POSSIBLE_MODULES}
    else
        print_section "Cleaning HTTP Directory for full build"
        rm -fv ${HTTPDDIR}/*.deb
    fi

    for MODULE in ${MODULES} ; do
        cd "${ROOTDIR}"
        if [ ! -d ${MODULE} ] ; then
            echo "Directory ${ROOTDIR}/${MODULE} does not exist"
            exit 1
        fi
        print_section "Building ${MODULE}"
        cd ${MODULE}
        find . -name '*.deb' -exec rm -v {} \;

        BUILD_ARGS=""
        if [ ! -z $APT_PROXY ] ; then
            BUILD_ARGS="${BUILD_ARGS}--build-arg APT_PROXY=${APT_PROXY} "
        fi
        docker build ${NO_CACHE} ${BUILD_ARGS} -t ${MODULE,,}-stage2 .

        STAGES="stage-build.sh"
        if [ ! -z $TESTS ] ; then
            STAGES="stage-test.sh ${STAGES}"
        fi
        for STAGE in $STAGES ; do
            docker run -ti \
                -v "$(pwd):/build" \
                -w /build \
                ${MODULE,,}-stage2 \
                bash -c "groupadd -o -g $(id -g) -r $USER ;
                useradd -o -u $(id -u) -d /build -r -g $USER $USER ;
                runuser $USER -c devops-stages/${STAGE}"
            if [ $? -ne 0 ] ; then
            print_section "Failed to build ${MODULE}"
                exit 1
            fi
        done

        find . -name '*.deb' -exec mv -v {} ${HTTPDDIR}/ \;
    done
}

function _find_module_dockerfile() {
    cd "${ROOTDIR}/devops/docker"
    MODULES=`find . -name Dockerfile -printf '%h\n' |sed 's|\./||' |sort |tr '\n' ' '`
    if [ ! -z ${1} ] ; then
        POSSIBLE_MODULES=$(echo ${1} | sed "s/,/ /g")
        for MODULE in ${POSSIBLE_MODULES}; do
            if ! echo "${MODULES}" | grep -q "${MODULE}" ; then
                echo "Unknown stage 3 module ${MODULE}"
                echo "Must be one of ${MODULES}"
                exit 1
            fi
        done
        echo ${POSSIBLE_MODULES}
    else
        echo ${MODULES}
    fi
}

function stage_3() {
    print_section "Performing Stage 3"
    MODULES=$(_find_module_dockerfile $1)
    BUILD_ARGS=""
    if [ ! -z $APT_PROXY ] ; then
        BUILD_ARGS="${BUILD_ARGS}--build-arg APT_PROXY=${APT_PROXY} "
    fi

    HOSTIP=$(ip -4 addr show docker0 | grep -Po 'inet \K[\d.]+')
    [ -z "$DEFAULT_IF" ] && DEFAULT_IF=$(ip route list|awk '$1=="default" {print $5; exit}')
    [ -z "$DEFAULT_IF" ] && DEFAULT_IF=$(route -n |awk '$1~/^0.0.0.0/ {print $8; exit}')
    DEFAULT_IP=$(ip -o -4 a s ${DEFAULT_IF} |awk '{split($4,a,"/"); print a[1]; exit}')
    HOSTIP=${HOSTIP:=${DEFAULT_IP}}
    echo $HOSTIP

    for file in ${HTTPDDIR}/*.deb ; do
        file=`basename ${file}`
        name=`echo ${file} | cut -d_ -f1 | sed "s/-/_/g"`;
        name=${name^^}_URL
        BUILD_ARGS="${BUILD_ARGS}--build-arg ${name}=http://$HOSTIP:${HTTPPORT}/$file "
        echo Added ${name} as http://$HOSTIP:${HTTPPORT}/$file
    done

    for MODULE in ${MODULES} ; do
        cd "${ROOTDIR}/devops/docker"
        if [ ! -d ${MODULE} ] ; then
            echo "Directory ${ROOTDIR}/${MODULE} does not exist"
            exit 1
        fi
        print_section "Building ${MODULE}"
        cd ${MODULE}
        MODULE=${MODULE,,}
        docker build ${NO_CACHE} -t opensourcemano/${MODULE}:devel ${BUILD_ARGS} .
        if [ $? -ne 0 ] ; then
        print_section "Failed to build ${MODULE}"
            exit 1
        fi
    done
}

function local_registry_push() {
    print_section "Pushing to local registry"
    cd "${ROOTDIR}/devops/docker"
    MODULES=`find . -name Dockerfile -printf '%h\n' |sed 's|\./||' |sort |tr '\n' ' '`
    if [ ! -z ${1} ] ; then
        POSSIBLE_MODULES=$(echo ${1} | sed "s/,/ /g")
        for MODULE in ${POSSIBLE_MODULES}; do
            echo "${MODULE}"
            if ! echo "${MODULES}" | grep -q "${MODULE}" ; then
                echo "Unknown stage 3 module ${MODULE}"
                echo "Must be one of ${MODULES}"
                exit 1
            fi
        done
        MODULES=${POSSIBLE_MODULES}
    fi
    for MODULE in ${MODULES} ; do
        MODULE=${MODULE,,}
        docker tag opensourcemano/${MODULE}:devel ${REGISTRY}/opensourcemano/${MODULE}:devel
        docker push ${REGISTRY}/opensourcemano/${MODULE}:devel
    done
}

function install_osm() {
    cd "${ROOTDIR}/devops/installers"
    VCA=""
    if juju controllers 2>/dev/null| grep osm-vca ; then
        VCA="--vca osm-vca"
    fi
    ./charmed_install.sh --registry localhost:32000  --tag devel ${VCA}
}

function start_robot() {
    mkdir -p "${ROOTDIR}/tests/local"
    cd "${ROOTDIR}/tests/local"

    . ${OPENSTACKRC}

    # Workaround for microstack auth URL
    if [ ${OPENSTACKRC} == "/var/snap/microstack/common/etc/microstack.rc" ] ; then
        export OS_AUTH_URL=${OS_AUTH_URL}/v3
    fi

    export OSM_HOSTNAME=$(juju config -m osm nbi site_url | sed "s/http.*\?:\/\///"):443
    export PROMETHEUS_HOSTNAME=$(juju config -m osm prometheus site_url | sed "s/http.*\?:\/\///")
    export PROMETHEUS_PORT=80
    export JUJU_PASSWORD=`juju gui 2>&1 | grep password | awk '{print $2}'`
    export HOSTIP=$(echo $PROMETHEUS_HOSTNAME | sed "s/prometheus.//" | sed "s/.nip.io//")

    rm robot-systest.cfg
    for line in `env | grep "^OS_" | sort` ; do echo $line >> robot-systest.cfg ; done
    cat << EOF >> robot-systest.cfg
VIM_TARGET=osm
VIM_MGMT_NET=osm-ext
ENVIRONMENTS_FOLDER=environments
PACKAGES_FOLDER=/robot-systest/osm-packages
OS_CLOUD=openstack
LC_ALL=C.UTF-8
LANG=C.UTF-8
EOF

    cat << EOF > robot.etc.hosts
127.0.0.1           localhost
${HOSTIP}      prometheus.${HOSTIP}.nip.io nbi.${HOSTIP}.nip.io
EOF
    cat << EOF > clouds.yaml
clouds:
  openstack:
    auth:
      auth_url: $OS_AUTH_URL
      project_name: $OS_PROJECT_NAME
      username: $OS_USERNAME
      password: $OS_PASSWORD
      user_domain_name: $OS_USER_DOMAIN_NAME
      project_domain_name: $OS_PROJECT_DOMAIN_NAME
EOF

    VIM_AUTH_URL=$(osm vim-show osm | grep vim_url | awk '{print $4}' | tr -d \")
    if [[ ! -z ${VIM_AUTH_URL} && "$OS_AUTH_URL" != "${VIM_AUTH_URL}" ]] ; then
        echo "Deleting existing VIM osm as auth URLs have changed"
        osm vim-delete osm
    fi

    if ! osm vim-show osm &> /dev/null ; then
        echo "Creating VIM osm"
        if [ -v VIM_VCA ]; then
           VCA_OPT="--vca $VIM_VCA"
        fi
        osm vim-create --name osm $VCA_OPT --user "$OS_USERNAME" --password "$OS_PASSWORD" \
        --auth_url "$OS_AUTH_URL" --tenant "$OS_USERNAME" --account_type openstack \
        --config='{use_floating_ip: True,
                   management_network_name: osm-ext}'
    fi

    if [ ! -z $ROBOT_LOCAL ] ; then
        LOCAL_MOUNT_1="/robot-systest/lib"
        LOCAL_MOUNT_2="/robot-systest/resources"
        LOCAL_MOUNT_3="/robot-systest/testsuite"
    else
        LOCAL_MOUNT_1="/tmp/lib"
        LOCAL_MOUNT_2="/tmp/resources"
        LOCAL_MOUNT_3="/tmp/testsuite"
    fi

    mkdir -p reports

    docker run -ti --entrypoint /bin/bash \
        --env OSM_HOSTNAME=${OSM_HOSTNAME} \
        --env PROMETHEUS_HOSTNAME=${PROMETHEUS_HOSTNAME} \
        --env PROMETHEUS_PORT=${PROMETHEUS_PORT} \
        --env JUJU_PASSWORD=${JUJU_PASSWORD} \
        --env HOSTIP=${HOSTIP} \
        --env-file robot-systest.cfg \
        -v "$(pwd)/robot.etc.hosts":/etc/hosts \
        -v ~/.osm/microk8s-config.yaml:/root/.kube/config \
        -v "$(pwd)/clouds.yaml":/etc/openstack/clouds.yaml \
        -v "${HOME}/snap/qhttp/common"/robot-systest/reports \
        -v "${HOME}/snap/qhttp/common:"/robot-systest/conformance-tests/reports \
        -v "${ROOTDIR}/tests/robot-systest/lib":${LOCAL_MOUNT_1} \
        -v "${ROOTDIR}/tests/robot-systest/resources":${LOCAL_MOUNT_2} \
        -v "${ROOTDIR}/tests/robot-systest/testsuite":${LOCAL_MOUNT_3} \
        opensourcemano/tests:$OSM_TESTS_IMAGE_TAG
}

function update_osm_module() {
    MODULES=$(_find_module_dockerfile $1)
    for MODULE in ${MODULES} ; do
        MODULE=${MODULE,,}
        echo "Updating ${MODULE}"
        juju attach-resource ${MODULE} image=localhost:32000/opensourcemano/${MODULE}:devel
    done
}

if [ "$0" != "$BASH_SOURCE" ]; then

    _osm_local_build()
    {
        OPTIONS=$(show_help | sed '0,/^OPTIONS:$/d' | awk '{print $1}')
        COMPREPLY=($(compgen -W "${OPTIONS}" -- "${COMP_WORDS[-1]}"))
    }

    THIS_SCRIPT="$(basename ${BASH_SOURCE[0]})"
    echo "Setting up bash completion for ${THIS_SCRIPT}"
    complete -F _osm_local_build "${THIS_SCRIPT}"
else
    check_arguments $@

    create_httpddir
    eval "${INSTALL_HTTPD}"
    eval "${INSTALL_LOCAL_REGISTRY}"
    eval "${INSTALL_MICROSTACK}"
    eval "${STAGE_2}"
    eval "${STAGE_3}"
    eval "${REGISTRY_PUSH}"
    eval "${INSTALL_OSM}"
    eval "${UPDATE_INSTALL}"
    eval "${START_ROBOT}"
fi
