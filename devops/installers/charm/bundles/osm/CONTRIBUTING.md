<!-- Copyright 2022 ETSI

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

# Contributing

## Overview

This documents explains the processes and practices recommended for contributing enhancements to
this bundle.

- Generally, before developing enhancements to this charm, you should consider [opening an issue
  ](https://osm.etsi.org/bugzilla/enter_bug.cgi?product=OSM) explaining your use case. (Component=devops, version=master)
- If you would like to chat with us about your use-cases or proposed implementation, you can reach
  us at [OSM Juju public channel](https://opensourcemano.slack.com/archives/C027KJGPECA).
- Familiarising yourself with the [Charmed Operator Framework](https://juju.is/docs/sdk) library
  will help you a lot when working on new features or bug fixes.
- All enhancements require review before being merged. Code review typically examines
  - code quality
  - test coverage
  - user experience for Juju administrators this charm.
- Please help us out in ensuring easy to review branches by rebasing your gerrit patch onto
  the `master` branch.

## Code Repository

To clone the repository for this bundle:

```shell
git clone "https://osm.etsi.org/gerrit/osm/devops"
```

The bundle can be found in the following directory:

```shell
cd devops/installers/charm/bundles/osm
```
