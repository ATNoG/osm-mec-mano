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

# OSM Charms and interfaces

**Description**: This document describes the high-level view of the OSM Charms and interfaces. An important note is that these charms Kubernetes Charms, so they must be deployed on top of a Kubernetes Cloud using Juju.

## Folder tree

In the current directory, there is one folder "interfaces" that has all the interfaces of the OSM components, which are basically two: osm-nbi, and osm-ro.

Additionally, we can see six folders that contain each OSM core components: lcm-k8s, mon-k8s, nbi-k8s, pol-k8s, ro-k8s, and ui-k8s.

Then, we can see a folder "bundle" which has the templates for the OSM bundles in single instance and HA.

The "layers" folder include one common layer for all the osm charms (osm-common)

```txt

├── bundles
│   ├── osm
│   └── osm-ha
├── interfaces
│   ├── osm-nbi
│   └── osm-ro
├── layers
│   └── osm-common
├── lcm-k8s
├── mon-k8s
├── nbi-k8s
├── pol-k8s
├── ro-k8s
├── ui-k8s
└── ng-ui --> new operator framework

```

## Charms

All the charms have a very similar structure. This subsection explains the purpose of each file inside the charms, as well as basic steps to get started.

The folder structure for each charm looks like this:

```txt
<charm>-k8s/
├── config.yaml
├── icon.svg
├── layer.yaml
├── metadata.yaml
├── reactive
│   ├── <charm>.py
│   └── spec_template.yaml
├── README.md
├── .gitignore
├── .yamllint.yaml
└── tox.ini
```

Purpose of each file:

- **config.yaml**: YAML file that include all the configurable options for the charm.
- **icon.svg**: SVG icon. This is the icon that will appear in the Charm Store.
- **layer.yaml**: YAML file with the layers that the charm needs. All the OSM Charms need at least the following layers: caas-base, status, leadership, and osm-common. If charms provide or require interfaces, which all of them do, those interfaces should be specified in this file too.
- **metadata.yaml**: YAML file that describe the top level information of the charm: name, description, series, interfaces that provide/require, needed storage, and deployment type.
- **reactive/\<charm>.py**: Python file that implements the actual logic to the charm.
- **reactive/spec_template.yaml**: Pod spec template to be used by the pods.
- **README.md**: This file describes how to build the charm, how to prepare the environment to test it with Microk8s.
- **.gitignore**: Typical Git Ignore file, to avoid pushing unwanted files to upstream.
- **.yamllint.yaml**: YAML file to specify the files to exclude from the yamllint test that tox.ini does.
- **tox.ini**: Includes basic functions to build the charms, and check the linting.

## Interfaces

Each interface needs at least three files:

- **interface.yaml:** Metadata of the interface: name, maintainer, and summary.
- **provides.py:** Code for the charm that provides the interface.
- **requires.py:** Code for the charm that requires the interface.

Additionally, there are also files for copyright and a README that explains how to use the interface.

# Steps for testing

## Dependencies

```bash
sudo apt install tox -y
```

## Check the syntax of the charms

```bash
./lint.sh
```

## Build all the charms

```bash
./build.sh
```

## Generate bundle

```bash
# Generate bundle from built charms
python3 generate_bundle.py --local --destination osm.yaml
# Help
python3 generate_bundle.py --help
```

## Install VCA

```bash
sudo snap install juju --classic
juju bootstrap localhost osm-lxd
```

## Generate overlay

> NOTE: This will be removed once the installer is merged.

```bash
sudo snap install osmclient
sudo snap alias osmclient.osm osm
sudo snap connect osmclient:juju-client-observe
sudo snap connect osmclient:ssh-public-keys
sudo snap connect osmclient:network-control
osmclient.overlay  # Execute the commands printed by this command to enable native charms
```

## Bootstrap Juju controller in Microk8s

```bash
sudo snap install microk8s --classic
sudo usermod -a -G microk8s ubuntu
sudo chown -f -R ubuntu ~/.kube
newgrp microk8s
microk8s.status --wait-ready
microk8s.enable storage dns  # (metallb) is optional
juju bootstrap microk8s osm-k8s
```

## Deploy OSM with charms

```bash
juju add-model osm
juju deploy ./osm.yaml --overlay vca-overlay.yaml
```

## Wait until Charms are deployed

```bash
watch -c juju status --color  # Wait until every application is in active state
export OSM_HOSTNAME=<ip-nbi>
osm ns-list
# ...
```
