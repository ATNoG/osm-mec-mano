<!-- Copyright 2021 Canonical Ltd.

Licensed under the Apache License, Version 2.0 (the "License"); you may
not use this file except in compliance with the License. You may obtain
a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.

For those usages not covered by the Apache License, Version 2.0 please
contact: legal@canonical.com

To get in touch with the maintainers, please contact:
osm-charmers@lists.launchpad.net -->

# MariaDB Operator

A Juju charm deploying and managing MariaDB on Kubernetes.

## Overview

MariaDB turns data into structured information in a wide array of
applications, ranging from banking to websites. Originally designed as
enhanced, drop-in replacement for MySQL, MariaDB is used because it is fast,
scalable and robust, with a rich ecosystem of storage engines, plugins and
many other tools make it very versatile for a wide variety of use cases.

MariaDB is developed as open source software and as a relational database it
provides an SQL interface for accessing data. The latest versions of MariaDB
also include GIS and JSON features.

More information can be found in [the MariaDB Knowledge Base](https://mariadb.com/kb/en/documentation/).

## Usage

For details on using Kubernetes with Juju [see here](https://juju.is/docs/kubernetes), and for
details on using Juju with MicroK8s for easy local testing [see here](https://juju.is/docs/microk8s-cloud).

To deploy the charm into a Juju Kubernetes model:

    juju deploy cs:~charmed-osm/mariadb

The charm can then be easily related to an application that supports the mysql
relation, such as:

    juju deploy cs:~charmed-osm/keystone
    juju relate keystone mariadb-k8s

Once the "Workload" status of both mariadb-k8s and keystone is "active", using
the "Application" IP of keystone (from `juju status`):

    # Change as appropriate for you juju model
    KEYSTONE_APPLICATION_IP=10.152.183.222
    curl -i -H "Content-Type: application/json" -d '
    { "auth": {
        "identity": {
          "methods": ["password"],
          "password": {
            "user": {
              "name": "admin",
              "domain": { "id": "default" },
             "password": "admin"
           }
         }
       }
     }
    ' "http://${KEYSTONE_APPLICATION_IP}:5000/v3/auth/tokens" ; echo

This will create a token that you could use to query Keystone.

---

For more details, [see here](https://charmhub.io/mariadb/docs/).
