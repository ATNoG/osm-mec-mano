##
# Copyright 2020 ETSI
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
##

# Snap for OSM client

The snapcraft.yaml located in this folder, allows to build a snap of the OSM client


# Build the Snap

```bash
docker run -v ${PWD}:/build -w /build snapcore/snapcraft:stable /bin/bash -c "apt update && snapcraft"
```


## Working on build steps

As the build can take upwards of 4 minutes, it might be easier to enter the docker
container and perform iterative builds there.

```bash
docker run -v ${PWD}:/build -w /build snapcore/snapcraft:stable /bin/bash -c /bin/bash
apt update
snapcraft
```


## Install

```bash
$ sudo snap install --devmode osmclient_v7.1.0+git4.a4af86f-dirty_amd64.snap
osmclient v7.1.0+git4.a4af86f-dirty installed
$ sudo snap alias osmclient.osm osm
```
