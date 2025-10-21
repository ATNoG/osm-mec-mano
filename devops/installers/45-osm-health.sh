#!/usr/bin/env bash

#   Copyright 2020 Telefónica Investigación y Desarrollo S.A.U.
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

HERE=$(dirname "$(readlink --canonicalize "$BASH_SOURCE")")

source "${HERE}/00-default-install-options.rc"
[ ! -f "${OSM_HOME_DIR}/user-install-options.rc" ] || source "${OSM_HOME_DIR}/user-install-options.rc"
source "${CREDENTIALS_DIR}/git_environment.rc"
export KUBECONFIG="${OSM_HOME_DIR}/clusters/kubeconfig-osm.yaml"

# Default values
sampling_period=5       # seconds
time_for_readiness=2    # minutes ready
time_for_failure=7      # minutes broken

oks_threshold=$((time_for_readiness*60/${sampling_period}))     # No. ok samples to declare the system ready
failures_threshold=$((time_for_failure*60/${sampling_period}))  # No. nok samples to declare the system broken
failures_in_a_row=0
oks_in_a_row=0


# Show status of the OSM services deployed with helm
echo "helm -n ${OSM_NAMESPACE} list"
helm -n ${OSM_NAMESPACE} list
echo "helm -n ${OSM_NAMESPACE} status ${OSM_HELM_RELEASE}"
helm -n ${OSM_NAMESPACE} status ${OSM_HELM_RELEASE}

####################################################################################
# Loop to check system readiness
####################################################################################
while [[ (${failures_in_a_row} -lt ${failures_threshold}) && (${oks_in_a_row} -lt ${oks_threshold}) ]]
do

    # State of Deployments
    DEPLOYMENTS_STATE=$(kubectl get deployment -n ${OSM_NAMESPACE} --no-headers 2>&1)
    DEPLOYMENTS_READY=$(echo "${DEPLOYMENTS_STATE}" | awk '$2=="1/1" && $4=="1" {printf ("%20s\t%s\t%s\n", $1, $2, $4)}')
    DEPLOYMENTS_NOT_READY=$(echo "${DEPLOYMENTS_STATE}" | awk '$2!="1/1" || $4!="1" {printf ("%20s\t%s\t%s\n", $1, $2, $4)}')
    COUNT_DEPLOYMENTS_READY=$(echo "${DEPLOYMENTS_READY}" | grep -v -e '^$' | wc -l || true)
    COUNT_DEPLOYMENTS_NOT_READY=$(echo "${DEPLOYMENTS_NOT_READY}" | grep -v -e '^$' | wc -l || true)

    # State of Statefulsets
    STS_STATE=$(kubectl get statefulset -n ${OSM_NAMESPACE} --no-headers 2>&1)
    STS_READY=$(echo "${STS_STATE}" | awk '$2=="1/1" || $2=="2/2" || $2=="3/3" {printf ("%20s\t%s\t%s\n", $1, $2, $4)}')
    STS_NOT_READY=$(echo "${STS_STATE}" | awk '$2!="1/1" && $2!="2/2" && $2!="3/3" {printf ("%20s\t%s\t%s\n", $1, $2, $4)}')
    COUNT_STS_READY=$(echo "${STS_READY}" | grep -v -e '^$' | wc -l || true)
    COUNT_STS_NOT_READY=$(echo "${STS_NOT_READY}" | grep -v -e '^$' | wc -l || true)

    # OK sample
    if [[ $((${COUNT_DEPLOYMENTS_NOT_READY}+${COUNT_STS_NOT_READY})) -eq 0 ]]
    then
        ((++oks_in_a_row))
        failures_in_a_row=0
        echo -ne ===\> Successful checks: "${oks_in_a_row}"/${oks_threshold}\\r
    # NOK sample
    else
        ((++failures_in_a_row))
        oks_in_a_row=0
        echo
        echo Bootstraping... "${failures_in_a_row}" attempts of ${failures_threshold}

        # Reports failed deployments
        if [[ "${COUNT_DEPLOYMENTS_NOT_READY}" -ne 0 ]]
        then
            echo ${COUNT_DEPLOYMENTS_NOT_READY} of $((${COUNT_DEPLOYMENTS_NOT_READY}+${COUNT_DEPLOYMENTS_READY})) deployments starting:
            echo "${DEPLOYMENTS_NOT_READY}"
            echo
        fi

        # Reports failed statefulsets
        if [[ "${COUNT_STS_NOT_READY}" -ne 0 ]]
        then
            echo ${COUNT_STS_NOT_READY} of $((${COUNT_STS_NOT_READY}+${COUNT_STS_READY})) statefulsets starting:
            echo "${STS_NOT_READY}"
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
    echo SYSTEM IS BROKEN
    exit 1
else
    echo
    echo SYSTEM IS READY
fi

exit 0
