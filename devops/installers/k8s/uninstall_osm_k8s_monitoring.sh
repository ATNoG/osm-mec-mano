#!/bin/bash

#   Copyright 2019 Minsait - Indra S.A.
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
#   Author: Jose Manuel Palacios (jmpalacios@minsait.com)
#   Author: Jose Antonio Martinez (jamartinezv@minsait.com)

function usage(){
    echo -e "usage: $0 [OPTIONS]"
    echo -e "Uninstall OSM Monitoring"
    echo -e "  OPTIONS"
    echo -e "     -n <namespace>:   use specified kubernetes namespace - default: monitoring"
    echo -e "     --debug       :   debug script"
    echo -e "     -h / --help   :   print this help"
}

NAMESPACE=monitoring
DEBUG=""
while getopts ":h-:n:" o; do
    case "${o}" in
        h)
            usage && exit 0
            ;;
        n)
            NAMESPACE="${OPTARG}"
            ;;

        -)
            [ "${OPTARG}" == "help" ] && usage && exit 0
            [ "${OPTARG}" == "debug" ] && DEBUG="y" && continue
            echo -e "Invalid option: '--$OPTARG'\n" >&2
            usage && exit 1
            ;;

        \?)
            echo -e "Invalid option: '-$OPTARG'\n" >&2
            usage && exit 1
            ;;
        *)
            usage && exit 1
            ;;
    esac
done

function dump_vars(){
    echo "NAMESPACE=$NAMESPACE"
    echo "DEBUG=$DEBUG"
}

if [ -n "$DEBUG" ] ; then
        set -x
fi



# remove dashboards
echo "Deleting dashboards...."
kubectl -n $NAMESPACE delete configmap osm-monitoring-osm-summary-grafana > /dev/null 2>&1
kubectl -n $NAMESPACE delete configmap osm-monitoring-osm-nodes-grafana > /dev/null 2>&1
kubectl -n $NAMESPACE delete configmap osm-monitoring-prometheus-kafka-exporter-grafana > /dev/null 2>&1
kubectl -n $NAMESPACE delete configmap osm-monitoring-prometheus-mysql-exporter-grafana > /dev/null 2>&1
kubectl -n $NAMESPACE delete configmap osm-monitoring-prometheus-mongodb-exporter-grafana > /dev/null 2>&1

# remove exporters
echo "Deleting exporters...."
helm delete --purge osm-kafka-exporter > /dev/null 2>&1
helm delete --purge osm-mysql-exporter > /dev/null 2>&1
helm delete --purge osm-mongodb-exporter > /dev/null 2>&1

# remove kube-prometheus-stack
echo "Deleting kube-prometheus-stack...."
helm delete --purge osm-monitoring > /dev/null 2>&1

# Delete CRDs
kubectl delete crd prometheusrules.monitoring.coreos.com > /dev/null 2>&1
kubectl delete crd servicemonitors.monitoring.coreos.com > /dev/null 2>&1
kubectl delete crd alertmanagers.monitoring.coreos.com > /dev/null 2>&1
kubectl delete crd prometheuses.monitoring.coreos.com > /dev/null 2>&1
kubectl delete crd alertmanagers.monitoring.coreos.com > /dev/null 2>&1
kubectl delete crd podmonitors.monitoring.coreos.com > /dev/null 2>&1

# Delete svcs
kubectl -n kube-system delete service osm-monitoring-kube-promet-coredns
kubectl -n kube-system delete service osm-monitoring-kube-promet-kube-controller-manager
kubectl -n kube-system delete service osm-monitoring-kube-promet-kube-etcd
kubectl -n kube-system delete service osm-monitoring-kube-promet-kube-proxy
kubectl -n kube-system delete service osm-monitoring-kube-promet-kube-scheduler
kubectl -n kube-system delete service osm-monitoring-kube-promet-kubelet

# Delete webhooks
kubectl delete validatingwebhookconfigurations.admissionregistration.k8s.io osm-monitoring-kube-promet-admission
kubectl delete mutatingwebhookconfigurations.admissionregistration.k8s.io osm-monitoring-kube-promet-admission

# Delete monitoring namespace
echo "Deleting monitoring namespace...."
kubectl delete namespace $NAMESPACE
