<!-- Copyright 2022 Canonical Ltd.

Licensed under the Apache License, Version 2.0 (the "License"); you may
not use this file except in compliance with the License. You may obtain
a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.
-->

# OSM Update DB Operator

[![code style](https://img.shields.io/badge/code%20style-black-000000.svg)](https://github.com/psf/black/tree/main)

## Description

Charm used to update the OSM databases during an OSM upgrade process. To be used you should have an instance of OSM running that you may want to upgrade

## Usage

### Deploy the charm (locally)

```shell
juju add-model update-db
juju deploy osm-update-db-operator --series focal
```

Set MongoDB and MySQL URIs:

```shell
juju config osm-update-db-operator mysql-uri=<mysql_uri>
juju config osm-update-db-operator mongodb-uri=<mongodb_uri>
```

### Updating the databases

In case we want to update both databases, we need to run the following command:

```shell
juju run-action osm-update-db-operator/0 update-db current-version=<Number_of_current_version> target-version=<Number_of_target_version>
# Example:
juju run-action osm-update-db-operator/0 update-db current-version=9 target-version=10
```

In case only you just want to update MongoDB, then we can use a flag 'mongodb-only=True':

```shell
juju run-action osm-update-db-operator/0 update-db current-version=9 target-version=10 mongodb-only=True
```

In case only you just want to update MySQL database, then we can use a flag 'mysql-only=True':

```shell
juju run-action osm-update-db-operator/0 update-db current-version=9 target-version=10 mysql-only=True
```

You can check if the update of the database was properly done checking the result of the command:

```shell
juju show-action-output <Number_of_the_action>
```

### Fixes for bugs

Updates de database to apply the changes needed to fix a bug. You need to specify the bug number. Example:

```shell
juju run-action osm-update-db-operator/0 apply-patch bug-number=1837
```

## Contributing

Please see the [Juju SDK docs](https://juju.is/docs/sdk) for guidelines
on enhancements to this charm following best practice guidelines, and
`CONTRIBUTING.md` for developer guidance.
