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

function install_k8s_storageclass() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    # Openebs versions can be found here: https://github.com/openebs/openebs/releases
    OPENEBS_VERSION="3.7.0"
    echo "Installing OpenEBS"
    helm repo add openebs https://openebs.github.io/charts
    helm repo update
    helm upgrade --install --create-namespace --namespace openebs openebs openebs/openebs --version ${OPENEBS_VERSION}
    helm ls -n openebs
    local storageclass_timeout=400
    local counter=0
    local storageclass_ready=""
    echo "Waiting for storageclass"
    while (( counter < storageclass_timeout ))
    do
        kubectl get storageclass openebs-hostpath &> /dev/null

        if [ $? -eq 0 ] ; then
            echo "Storageclass available"
            storageclass_ready="y"
            break
        else
            counter=$((counter + 15))
            sleep 15
        fi
    done
    [ -n "$storageclass_ready" ] || FATAL_TRACK k8scluster "Storageclass not ready after $storageclass_timeout seconds. Cannot install openebs"
    kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

#installs metallb from helm
function install_helm_metallb() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo "Installing MetalLB"
    METALLB_VERSION="0.13.10"
    helm repo add metallb https://metallb.github.io/metallb
    helm repo update
    # kubectl create namespace metallb-system
    # kubectl label namespaces metallb-system pod-security.kubernetes.io/enforce=privileged
    # kubectl label namespaces metallb-system pod-security.kubernetes.io/audit=privileged
    # kubectl label namespaces metallb-system pod-security.kubernetes.io/warn=privileged
    helm upgrade --install --create-namespace --namespace metallb-system metallb metallb/metallb --version ${METALLB_VERSION}
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

function configure_ipaddresspool_metallb() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo "Creating IP address pool manifest: ${K8SCLUSTER_CONFIG_FOLDER}/metallb-ipaddrpool.yaml"
    [ ! -d "$K8SCLUSTER_CONFIG_FOLDER" ] && sudo mkdir -p $K8SCLUSTER_CONFIG_FOLDER
    METALLB_IP_RANGE="$DEFAULT_IP/32"
    echo "apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - ${METALLB_IP_RANGE}" | sudo tee -a ${K8SCLUSTER_CONFIG_FOLDER}/metallb-ipaddrpool.yaml
    echo "Applying IP address pool manifest: kubectl apply -f ${K8SCLUSTER_CONFIG_FOLDER}/metallb-ipaddrpool.yaml"
    kubectl apply -f ${K8SCLUSTER_CONFIG_FOLDER}/metallb-ipaddrpool.yaml || FATAL_TRACK k8scluster "Cannot create IP address Pool in MetalLB"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

#installs cert-manager
function install_helm_certmanager() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo "Installing cert-manager"
    CERTMANAGER_VERSION="v1.9.1"
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    helm upgrade --install cert-manager --create-namespace --namespace cert-manager jetstack/cert-manager \
        --version ${CERTMANAGER_VERSION} --set installCRDs=true --set prometheus.enabled=false \
        --set extraArgs="{--enable-certificate-owner-ref=true}"
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

#installs nginx
function install_helm_nginx() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    echo "Installing nginx"
    NGINX_VERSION="4.10.0"
    ANNOTATIONS='--set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz'
    helm upgrade --install ingress-nginx ingress-nginx \
        --repo https://kubernetes.github.io/ingress-nginx --version ${NGINX_VERSION} \
        --namespace ingress-nginx --create-namespace ${ANNOTATIONS}
    # Wait until ready
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=120s
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

#checks openebs, metallb and cert-manager readiness
function check_for_readiness() {
    [ -z "${DEBUG_INSTALL}" ] || DEBUG beginning of function
    # Default input values
    sampling_period=2       # seconds
    time_for_readiness=20   # seconds ready
    time_for_failure=200    # seconds broken
    OPENEBS_NAMESPACE=openebs
    METALLB_NAMESPACE=metallb-system
    CERTMANAGER_NAMESPACE=cert-manager

    # Equivalent number of samples
    oks_threshold=$((time_for_readiness/${sampling_period}))     # No. ok samples to declare the system ready
    failures_threshold=$((time_for_failure/${sampling_period}))  # No. nok samples to declare the system broken
    failures_in_a_row=0
    oks_in_a_row=0

    ####################################################################################
    # Loop to check system readiness
    ####################################################################################
    while [[ (${failures_in_a_row} -lt ${failures_threshold}) && (${oks_in_a_row} -lt ${oks_threshold}) ]]
    do
        # State of OpenEBS
        if [ -n "${INSTALL_STORAGECLASS}" ]; then
            OPENEBS_STATE=$(kubectl get pod -n ${OPENEBS_NAMESPACE} --no-headers 2>&1)
            OPENEBS_READY=$(echo "${OPENEBS_STATE}" | awk '$2=="1/1" || $2=="2/2" {printf ("%s\t%s\t\n", $1, $2)}')
            OPENEBS_NOT_READY=$(echo "${OPENEBS_STATE}" | awk '$2!="1/1" && $2!="2/2" {printf ("%s\t%s\t\n", $1, $2)}')
            COUNT_OPENEBS_READY=$(echo "${OPENEBS_READY}"| grep -v -e '^$' | wc -l)
            COUNT_OPENEBS_NOT_READY=$(echo "${OPENEBS_NOT_READY}" | grep -v -e '^$' | wc -l)
        fi

        # State of MetalLB
        if [ -n "${INSTALL_METALLB}" ]; then
            METALLB_STATE=$(kubectl get pod -n ${METALLB_NAMESPACE} --no-headers 2>&1)
            METALLB_READY=$(echo "${METALLB_STATE}" | awk '$2=="1/1" || $2=="4/4" {printf ("%s\t%s\t\n", $1, $2)}')
            METALLB_NOT_READY=$(echo "${METALLB_STATE}" | awk '$2!="1/1" && $2!="4/4" {printf ("%s\t%s\t\n", $1, $2)}')
            COUNT_METALLB_READY=$(echo "${METALLB_READY}" | grep -v -e '^$' | wc -l)
            COUNT_METALLB_NOT_READY=$(echo "${METALLB_NOT_READY}" | grep -v -e '^$' | wc -l)
        fi

        # State of CertManager
        if [ -n "${INSTALL_CERTMANAGER}" ]; then
            CERTMANAGER_STATE=$(kubectl get pod -n ${CERTMANAGER_NAMESPACE} --no-headers 2>&1)
            CERTMANAGER_READY=$(echo "${CERTMANAGER_STATE}" | awk '$2=="1/1" || $2=="2/2" {printf ("%s\t%s\t\n", $1, $2)}')
            CERTMANAGER_NOT_READY=$(echo "${CERTMANAGER_STATE}" | awk '$2!="1/1" && $2!="2/2" {printf ("%s\t%s\t\n", $1, $2)}')
            COUNT_CERTMANAGER_READY=$(echo "${CERTMANAGER_READY}" | grep -v -e '^$' | wc -l)
            COUNT_CERTMANAGER_NOT_READY=$(echo "${CERTMANAGER_NOT_READY}" | grep -v -e '^$' | wc -l)
        fi

        # OK sample
        if [[ $((${COUNT_OPENEBS_NOT_READY:-0}+${COUNT_METALLB_NOT_READY:-0}+${COUNT_CERTMANAGER_NOT_READY:-0})) -eq 0 ]]
        then
            ((++oks_in_a_row))
            failures_in_a_row=0
            echo -ne ===\> Successful checks: "${oks_in_a_row}"/${oks_threshold}\\r
        # NOK sample
        else
            ((++failures_in_a_row))
            oks_in_a_row=0
            echo
            echo Bootstraping... "${failures_in_a_row}" checks of ${failures_threshold}

            # Reports failed pods in OpenEBS
            if [[ "${COUNT_OPENEBS_NOT_READY:-0}" -ne 0 ]]
            then
                echo "OpenEBS: Waiting for ${COUNT_OPENEBS_NOT_READY} of $((${COUNT_OPENEBS_NOT_READY}+${COUNT_OPENEBS_READY})) pods to be ready:"
                echo "${OPENEBS_NOT_READY}"
                echo
            fi

            # Reports failed pods in MetalLB
            if [[ "${COUNT_METALLB_NOT_READY:-0}" -ne 0 ]]
            then
                echo "MetalLB: Waiting for ${COUNT_METALLB_NOT_READY} of $((${COUNT_METALLB_NOT_READY}+${COUNT_METALLB_READY})) pods to be ready:"
                echo "${METALLB_NOT_READY}"
                echo
            fi

            # Reports failed pods in CertManager
            if [[ "${COUNT_CERTMANAGER_NOT_READY:-0}" -ne 0 ]]
            then
                echo "CertManager: Waiting for ${COUNT_CERTMANAGER_NOT_READY} of $((${COUNT_CERTMANAGER_NOT_READY}+${COUNT_CERTMANAGER_READY})) pods to be ready:"
                echo "${CERTMANAGER_NOT_READY}"
                echo
            fi
        fi

        #------------ NEXT SAMPLE
        sleep ${sampling_period}
    done

    ####################################################################################
    # OUTCOME
    ####################################################################################
    if [[ (${failures_in_a_row} -ge ${failures_threshold}) ]]
    then
        echo
        FATAL_TRACK k8scluster "K8S CLUSTER IS BROKEN"
    else
        echo
        echo "K8S CLUSTER IS READY"
    fi
    [ -z "${DEBUG_INSTALL}" ] || DEBUG end of function
}

# main
while getopts ":-: " o; do
    case "${o}" in
        -)
            [ "${OPTARG}" == "debug" ] && DEBUG_INSTALL="y" && continue
            [ "${OPTARG}" == "storageclass" ] && INSTALL_STORAGECLASS="y" && continue
            [ "${OPTARG}" == "metallb" ] && INSTALL_METALLB="y" && continue
            [ "${OPTARG}" == "nginx" ] && INSTALL_NGINX="y" && continue
            [ "${OPTARG}" == "certmgr" ] && INSTALL_CERTMANAGER="y" && continue
            [ "${OPTARG}" == "all" ] && INSTALL_STORAGECLASS="y" && INSTALL_METALLB="y" && INSTALL_NGINX="y" && INSTALL_CERTMANAGER="y" && continue
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
DEFAULT_IP=${DEFAULT_IP:-}
K8SCLUSTER_CONFIG_FOLDER=${K8SCLUSTER_CONFIG_FOLDER:-}
INSTALL_STORAGECLASS=${INSTALL_STORAGECLASS:-}
INSTALL_METALLB=${INSTALL_METALLB:-}
INSTALL_CERTMANAGER=${INSTALL_CERTMANAGER:-}
INSTALL_NGINX=${INSTALL_NGINX:-}
echo "DEBUG_INSTALL=${DEBUG_INSTALL}"
echo "DEFAULT_IP=${DEFAULT_IP}"
echo "K8SCLUSTER_CONFIG_FOLDER=${K8SCLUSTER_CONFIG_FOLDER}"

export HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")
source "${HERE}/../../../library/logging"
source "${HERE}/../../../library/track"

if [ -n "${INSTALL_STORAGECLASS}" ]; then
    install_k8s_storageclass
    track k8scluster k8s_storageclass_ok
fi
if [ -n "${INSTALL_METALLB}" ]; then
    install_helm_metallb
    track k8scluster k8s_metallb_ok
fi
if [ -n "${INSTALL_CERTMANAGER}" ]; then
    install_helm_certmanager
    track k8scluster k8s_certmanager_ok
fi
if [ -n "${INSTALL_NGINX}" ]; then
    install_helm_nginx
    track k8scluster k8s_nginx_ok
fi
check_for_readiness
track k8scluster k8s_ready_ok
if [ -n "${INSTALL_METALLB}" ]; then
    configure_ipaddresspool_metallb
fi
