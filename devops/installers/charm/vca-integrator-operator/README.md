<!--
Copyright ETSI Contributors and Others.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
implied.
See the License for the specific language governing permissions and
limitations under the License.
-->

# OSM VCA Integrator Operator

## Description

TODO

## How-to guides

### Deploy and configure

Deploy the OSM VCA Integrator Charm using the Juju command line:

```shell
$ juju add-model osm-vca-integrator
$ juju deploy osm-vca-integrator
$ juju config osm-vca-integrator \
    k8s-cloud=microk8s \
    controllers="`cat ~/.local/share/juju/controllers.yaml`" \
    accounts="`cat ~/.local/share/juju/accounts.yaml`" \
    public-key="`cat ~/.local/share/juju/ssh/juju_id_rsa.pub`"
```

## Contributing

Please see the [Juju SDK docs](https://juju.is/docs/sdk) for guidelines
on enhancements to this charm following best practice guidelines, and
`CONTRIBUTING.md` for developer guidance.
