<!--
Copyright 2019 Minsait - Indra S.A.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
Author: Jose Manuel Palacios (jmpalacios@minsait.com)
Author: Jose Antonio Martinez (jamartinezv@minsait.com)
-->

# OSM Monitoring

## Introduction

This is an utility to monitor the OSM nodes and pods in the Kubernetes deployment. Metrics are stored in Prometheus and accessible in Grafana. Note that those "Prometheus" instance is not the same in the OSM core, but different one, aimed at the monitoring of the platform itself.

## Requirements

OSM must be/have been deployed using the Kubernetes installer (that is, with the -c k8s option).

## Versions

For reference, the versions for the external components used are as follows:

* PROMETHEUS_OPERATOR=30.0.3
* PROMETHEUS_MONGODB_EXPORTER=2.9.0
* PROMETHEUS_MYSQL_EXPORTER=1.5.0
* PROMETHEUS_KAFKA_EXPORTER=1.5.0
* HELM_CLIENT=3.7.2

## Functionality

Kubernetes cluster metrics (for nodes, pods, deployments, etc.) are stored in the dedicated Prometheus instance and accessible using Grafana.

"Kube-prometheus-stack" (<https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack>) provides the basic components and the monitoring of the basic Kubernetes resources. Additional "exporters" are used to gather metrics from Kafka, Mysql and Mongodb.
It is important to note that Grafana is not installed with this chart because we are using Grafana installed with OSM core.

## Install procedure

There are two ways to install the monitoring component based on the OSM global installer (<https://osm-download.etsi.org/ftp/osm-11.0-eleven/install_osm.sh>)

* Using the --k8s_monitor switch in the OSM installation:

```bash
./install_osm.sh -c k8s --k8s_monitor
```

* As a separated component (K8s based OSM only):

```bash
./install_osm.sh -o k8s_monitor
```

All the components will be installed in the "monitoring" namespace. In addition, for debugging purposes, there is a standalone script is available in `devops/installers/k8s/install_osm_k8s_monitoring.sh`. To see the available options, type --help.

```sh
usage: ./install_osm_k8s_monitoring.sh [OPTIONS]
Install OSM Monitoring
  OPTIONS
     -n <namespace>   :   use specified kubernetes namespace - default: monitoring
     -s <service_type>:   service type (ClusterIP|NodePort|LoadBalancer) - default: NodePort
     --debug          :   debug script
     --dump           :   dump arguments and versions
     -h / --help      :   print this help
```

## Access to Grafana

The Grafana console can be accessed on the IP address of any node using port 3000, since a NodePort service is used: `http://<ip_your_osm_host>:3000`

The initial credentials are:

* Username: admin
* Password: admin

## Uninstall procedure

Use the uninstall script

```sh
./install_osm.sh -o k8s_monitor --uninstall
```

In addition, for debugging purposes, there is a standalone script is available in `devops/installers/k8s/uninstall_osm_k8s_monitoring.sh`. To see the available options type --help.

```bash
usage: ./uninstall_osm_k8s_monitoring.sh [OPTIONS]
Uninstall OSM Monitoring
  OPTIONS
     -n <namespace>:   use specified kubernetes namespace - default: monitoring
     --debug       :   debug script
     -h / --help   :   print this help
```

## Grafana Dashboards

Dashboard are organized in two folders:

* The folder "Kubernetes cluster" contains the dashboards available upstream as part of the standard prometheus operator helm installation:

  * Kubernetes components (api server, kubelet, pods, etc)
  * Nodes of the cluster.
  * Prometheus operator components.

* The folder "Open Source MANO" contains additional dashboards customized for OSM:
  * Summary with a quick view of the overall status.
  * Host information
  * Third party components: Kafka, MongoDB, MySQL.

## Adding new dashboards

New dashboards for OSM components should be included in "Open Source MANO" folder. Once we have the dashboard json file, please follow the instructions below to incorporate it into Grafana.

```bash
kubectl -n monitoring create configmap <configmap-name> --from-file=<dashboard-json-file>
kubectl -n monitoring patch configmap <configmap-name> --patch '{"metadata": {"labels": {"grafana_dashboard": "1"},{"annotations": {k8s-sidecar-target-directory: "/tmp/dashboards/Open Source MANO"}}}}'
```
where <configmap-name> and <dashboard-json-file> needs to be replaced with desired values. A proposal is that <configmap-name> begins with "osm-monitoring-osm-"

Once configmap is created and patched, we can download the manifest file for future use with next command:
```
kubectl -n monitoring get configmap <configmap-name> -o yaml > <confimap-file>
```

Grafana Sidecar will read the label `grafana_dashboard: "1"` in the configmap and upload the dashboard information to Grafana.

The current dashboards can also be updated. It is only needed to modify/update the required yaml file available in `devops/installers/k8s` and apply them via kubectl. As an example `kubectl -n monitoring apply -f summary-dashboard.yaml` will update the changes made in the summary dashboard.
