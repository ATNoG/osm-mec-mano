<!--
Copyright 2020 British Telecommunications plc

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
Author: Antonio Marsico (antonio.marsico@bt.com)
-->


# User guide

This short guide explains how to use directly the Ansible playbook to install OSM to an OpenStack infrastructure.

## Prerequisites
The ansible playbook requires `ansible` and `openstacksdk` to be executed. `python-openstackclient` is not mandatory but highly recommended. They are part of Python pip and can be installed as follows:

`$ sudo -H pip install python-openstackclient "openstacksdk<1" "ansible>=2.10,<2.11"`

## Execute the playbook

In order to execute the playbook, it is required an OpenStack openrc file. It can be downloaded from the OpenStack web interface Horizon.

After that, it can be loaded with the following command:

`$ . openrc`

Then, all the credentials are loaded in the bash environment. Now it is possible to execute the playbook to configure OpenStack and install OSM:

`$ ansible-playbook -e external_network_name=<your openstack external network> site.yml`