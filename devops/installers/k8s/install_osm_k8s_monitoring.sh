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

# Obtain the path where the script is located
HERE=$(dirname $(readlink -f ${BASH_SOURCE[0]}))

echo $HERE
# Load component versions to be deployed
source $HERE/versions_monitoring
V_OPERATOR=""
V_MONGODB_EXPORTER=""
V_MYSQL_EXPORTER=""
V_KAFKA_EXPORTER=""

V_OPERATOR=$PROMETHEUS_OPERATOR
V_MONGODB_EXPORTER=$PROMETHEUS_MONGODB_EXPORTER
V_MYSQL_EXPORTER=$PROMETHEUS_MYSQL_EXPORTER
V_KAFKA_EXPORTER=$PROMETHEUS_KAFKA_EXPORTER


function usage(){
    echo -e "usage: $0 [OPTIONS]"
    echo -e "Install OSM Monitoring"
    echo -e "  OPTIONS"
    echo -e "     -n <namespace>   :   namespace to deploy k8s cluster monitoring - default: monitoring"
    echo -e "     -o <osm_namespace> : namespace where OSM is installed - default: osm"
    echo -e "     -s <service_type>:   service type (ClusterIP|NodePort|LoadBalancer) - default: NodePort"
    echo -e "     --debug          :   debug script"
    echo -e "     --dump           :   dump arguments and versions"
    echo -e "     -h / --help      :   print this help"
}

NAMESPACE=monitoring
OSM_NAMESPACE=osm
HELM=""
DEBUG=""
DUMP_VARS=""
SERVICE_TYPE=""
while getopts ":h-:n:o:s:" o; do
    case "${o}" in
        h)
            usage && exit 0
            ;;
        n)
            NAMESPACE="${OPTARG}"
            ;;
        o)
            OSM_NAMESPACE="${OPTARG}"
            ;;
        s)
            SERVICE_TYPE="${OPTARG}"
            ;;
        -)
            [ "${OPTARG}" == "help" ] && usage && exit 0
            [ "${OPTARG}" == "debug" ] && DEBUG="y" && continue
            [ "${OPTARG}" == "dump" ] && DUMP_VARS="y" && continue
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
    echo "Args...."
    echo "NAMESPACE=$NAMESPACE"
    echo "OSM_NAMESPACE=$OSM_NAMESPACE"
    echo "SERVICE_TYPE=$SERVICE_TYPE"
    echo "DEBUG=$DEBUG"
    echo "Versions...."
    echo "V_OPERATOR=$V_OPERATOR"
    echo "V_MONGODB_EXPORTER=$V_MONGODB_EXPORTER"
    echo "V_MYSQL_EXPORTER=$V_MYSQL_EXPORTER"
    echo "V_KAFKA_EXPORTER=$V_KAFKA_EXPORTER"
}

# Check K8s version
kubernetes_version=`kubectl version --short | grep Server | awk '{print $3}'`
min_kubernetes_version="v1.16.0"
if [[ "$kubernetes_version" < "$min_kubernetes_version" ]]
then
    echo "K8s monitoring could not be installed: Kube-prometheus-stack requires a Kubernetes 1.16+ (current version: $kubernetes_version)"
    exit 1
fi

if [ -n "$SERVICE_TYPE" ] ; then
    if [ [ $SERVICE_TYPE != "ClusterIP" ] || [ $SERVICE_TYPE != "NodePort" ] || [ $SERVICE_TYPE != "LoadBalancer" ] ] ; then
        echo "Wrong service type..."
    usage && exit 1
    fi
else
    SERVICE_TYPE="NodePort"
fi

if [ -n "$DEBUG" ] ; then
    set -x
fi

if [ -n "$DUMP_VARS" ] ; then
    dump_vars
fi

# Create monitoring namespace
echo "Creating namespace $NAMESPACE"
kubectl create namespace $NAMESPACE

# Needed changes for Kube-Prometheus on Kubeadm installation
# Kube-Controller-Manager
sudo sed -e "s/- --bind-address=127.0.0.1/- --bind-address=0.0.0.0/" -i /etc/kubernetes/manifests/kube-controller-manager.yaml
# Kube-Scheduler
sudo sed -e "s/- --bind-address=127.0.0.1/- --bind-address=0.0.0.0/" -i /etc/kubernetes/manifests/kube-scheduler.yaml
# Kube-Proxy
kubectl -n kube-system get cm/kube-proxy -o yaml > $HERE/kube-proxy-cm.yaml
sed -e "s/metricsBindAddress: \"\"/metricsBindAddress: 0.0.0.0:10249/" -i $HERE/kube-proxy-cm.yaml
kubectl -n kube-system delete cm kube-proxy
kubectl -n kube-system apply -f $HERE/kube-proxy-cm.yaml
rm $HERE/kube-proxy-cm.yaml
kubectl delete pod -l k8s-app=kube-proxy -n kube-system
# Etcd
sudo cp /etc/kubernetes/pki/etcd/healthcheck-client.key $HERE/healthcheck-client.key
sudo chmod a+r $HERE/healthcheck-client.key
kubectl -n $NAMESPACE create secret generic etcd-client-cert --from-file=/etc/kubernetes/pki/etcd/ca.crt --from-file=/etc/kubernetes/pki/etcd/healthcheck-client.crt --from-file=$HERE/healthcheck-client.key
sudo awk '/--trusted-ca-file=\/etc\/kubernetes\/pki\/etcd\/ca.crt/ { print; print "    - --metrics=extensive"; next }1' /etc/kubernetes/manifests/etcd.yaml > $HERE/tmp && sudo mv $HERE/tmp /etc/kubernetes/manifests/etcd.yaml
sudo chown root:root  /etc/kubernetes/manifests/etcd.yaml
sudo chmod 600 /etc/kubernetes/manifests/etcd.yaml

# Add Helm prometheus-community repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# kube-prometheus-stack installation (previously called prometheus-operator)
$HERE/change-charts-prometheus-operator.sh
echo "Creating stable/kube-prometheus-stack"
cat > $HERE/kube-prometheus-stack-values.yaml <<EOF
kubeControllerManager:
  service:
    enabled: true
    port: 10257
    targetPort: 10257
  serviceMonitor:
    https: true
    insecureSkipVerify: true
kubeScheduler:
  service: 
    enabled: true
    port: 10259
    targetPort: 10259
  serviceMonitor:
    https: true
    insecureSkipVerify: true
kubelet:
  serviceMonitor:
    https: true
kubeEtcd:
  serviceMonitor:
   scheme: https
   insecureSkipVerify: false
   serverName: localhost
   caFile: /etc/prometheus/secrets/etcd-client-cert/ca.crt
   certFile: /etc/prometheus/secrets/etcd-client-cert/healthcheck-client.crt
   keyFile: /etc/prometheus/secrets/etcd-client-cert/healthcheck-client.key
alertmanager:
  service:
    type: $SERVICE_TYPE
grafana:
  enabled: false
  forceDeployDashboards: true
prometheus:
  service:
    type: $SERVICE_TYPE
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    secrets: ['etcd-client-cert']
EOF
helm install osm-monitoring --namespace $NAMESPACE --version=$V_OPERATOR -f $HERE/kube-prometheus-stack-values.yaml $HERE/helm_charts/kube-prometheus-stack

# Exporters installation
# MongoDB
# exporter
echo "Creating prometheus-community/prometheus-mongodb-exporter"
helm install osm-mongodb-exporter --namespace $NAMESPACE --version=$V_MONGODB_EXPORTER --set serviceMonitor.additionalLabels.release=osm-monitoring,mongodb.uri='mongodb://mongodb-k8s.osm:27017' prometheus-community/prometheus-mongodb-exporter
#dashboard:
kubectl -n $NAMESPACE apply -f $HERE/mongodb-exporter-dashboard.yaml
# Mysql
# exporter
echo "Creating prometheus-community/prometheus-mysql-exporter"
helm install osm-mysql-exporter --namespace $NAMESPACE --version=$V_MYSQL_EXPORTER --set serviceMonitor.enabled=true,serviceMonitor.additionalLabels.release=osm-monitoring,mysql.user="root",mysql.pass=`kubectl -n ${OSM_NAMESPACE} get secret ro-db-secret -o yaml | grep -i -A1 '^data:$' | grep MYSQL_ROOT_PASSWORD | awk '{print $2}' | base64 -d`,mysql.host="mysql.osm",mysql.port="3306",'collectors.info_schema\.tables=true' prometheus-community/prometheus-mysql-exporter
#dashboard:
kubectl -n $NAMESPACE apply -f $HERE/mysql-exporter-dashboard.yaml
# Kafka
# exporter
echo "Creating prometheus-community/prometheus-kafka-exporter"
helm install osm-kafka-exporter --namespace $NAMESPACE --version=$V_KAFKA_EXPORTER --set prometheus.serviceMonitor.enabled=true,prometheus.serviceMonitor.additionalLabels.release=osm-monitoring,kafkaServer={kafka.osm.svc.cluster.local:9092},service.port=9092 prometheus-community/prometheus-kafka-exporter
# dashboard:
kubectl -n $NAMESPACE apply -f $HERE/kafka-exporter-dashboard.yaml

# Deploy summary dashboard
kubectl -n $NAMESPACE apply -f $HERE/summary-dashboard.yaml

# Deploy nodes dashboards
kubectl -n $NAMESPACE apply -f $HERE/nodes-dashboard.yaml

