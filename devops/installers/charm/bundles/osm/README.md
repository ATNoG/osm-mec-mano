<!--
 Copyright 2020 Canonical Ltd.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
-->

# Installation

Charmed OSM runs on the Ubuntu Long Term Support (LTS) release Bionic. Additionally, we recommend installing on a freshly installed virtual machine or bare metal with minimum requirements of:

- **16 GB RAM**
- **4 CPUs**
- **50 GB** of free storage space

The steps needed for the bundle installation are as follows:

- Installing MicroK8s and Juju
- Setting up the MicroK8s and LXD
- Bootstrapping the Juju controller
- Deploying the charmed OSM bundle
- Installing OSM client
- Integration of charmed OSM with MicroStack VIM

Follow the installation steps [here](https://juju.is/tutorials/charmed-osm-get-started#1-introduction)

# Bundle Components

- [grafana](https://jaas.ai/u/charmed-osm/grafana/0): A CAAS charm to deploy grafana for metrics visualization
- [kafka k8s](https://jaas.ai/u/charmed-osm/kafka-k8s): A CAAS charm to deploy Kafka used as a messaging bus between OSM components
- [lcm](https://jaas.ai/u/charmed-osm/lcm/0): A CAAS charm to deploy OSM's Lifecycle Management (LCM) component responsible for network services orchestration.
- [mariadb k8s](https://jaas.ai/u/charmed-osm/mariadb-k8s): A Juju charm deploying and managing database server (MariaDB) on Kubernetes
- [mon](https://jaas.ai/u/charmed-osm/mon/0): A CAAS charm to deploy OSM's Monitoring Interface (MON) responsible for metrics collection
- [mongodb k8s](https://jaas.ai/u/charmed-osm/mongodb-k8s): A CAAS charm to deploy MongoDB responsible for structuring the data
- [nbi](https://jaas.ai/u/charmed-osm/nbi/5): A juju charm to deploy OSM's Northbound Interface (NBI) on Kubernetes.
- [pol](https://jaas.ai/u/charmed-osm/pol/0): A CAAS charm to deploy OSM's Policy Module (POL) responsible for configuring alarms and actions
- [prometheus](https://jaas.ai/u/charmed-osm/prometheus): A CAAS charm to deploy Prometheus.
- [ro](https://jaas.ai/u/charmed-osm/ro/0): A CAAS charm to deploy OSM's Resource Orchestrator (RO) responsible for the life cycle management of VIM resources.
- [ng-ui](https://jaas.ai/u/charmed-osm/ng-ui): A CAAS charm to deploy OSM's User Interface (UI)
- [zookeeper k8s](https://jaas.ai/u/charmed-osm/zookeeper-k8s): A CAAS charm to deploy zookeeper for distributed synchronization

# Troubleshooting

If you have any trouble with the installation, please contact us, we will be glad to answer your questions.

You can directly contact the team:

- Guillermo Calvino ([guillermo.calvino@canonical.com](guillermo.calvino@canonical.com))
- Gulsum Atici ([gulsum.atici@canonical.com](gulsum.atici@canonical.com))
- Mark Beierl ([mark.beierl@canonical.com](mark.beierl@canonical.com))
- Patricia Reinoso ([patricia.reinoso@canonical.com](patricia.reinoso@canonical.com))
- Wajeeha Hamid ([wajeeha.hamid@canonical.com](wajeeha.hamid@canonical.com))
