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

 For those usages not covered by the Apache License, Version 2.0 please
 contact: legal@canonical.com

 To get in touch with the maintainers, please contact:
 osm-charmers@lists.launchpad.net
-->

# Debugging Charmed OSM

This document aims to provide the OSM community an easy way of testing and debugging OSM.

Benefits:

- Use upstream published images for debugging: No need to build local images anymore.
- Easily configure modules for debugging_mode: `juju config <module> debug_mode=True debug_pubkey="ssh-rsa ..."`.
- Debug in K8s: All pods (the debugged ones and the rest) will be running always in K8s.
- Seemless setup: VSCode will connect through SSH to the pods.
- Keep your changes save: Possibility to mount local module to the container; all the changes will be saved automatically to your local filesystem.

## Install OSM

Download the installer:

```bash
wget http://osm-download.etsi.org/ftp/osm-10.0-ten/install_osm.sh
chmod +x install_osm.sh
```

Install OSM from master (tag=testing-daily):

```bash
./install_osm.sh -R testing-daily -r testing --charmed
```

Install OSM from a specific tag:

```bash
./install_osm.sh -R testing-daily -r testing --charmed --tag <X.Y.Z>
```

## Debugging

Once the Charmed OSM installation has finished, you can select which applications you want to run with the debug mode.

```bash
# LCM
juju config lcm debug_mode=True  debug_pubkey="`cat ~/.ssh/id_rsa.pub`"
# MON
juju config mon debug_mode=True  debug_pubkey="`cat ~/.ssh/id_rsa.pub`"
# NBI
juju config nbi debug_mode=True  debug_pubkey="`cat ~/.ssh/id_rsa.pub`"
# RO
juju config ro debug_mode=True  debug_pubkey="`cat ~/.ssh/id_rsa.pub`"
# POL
juju config pol debug_mode=True  debug_pubkey="`cat ~/.ssh/id_rsa.pub`"
```

Enabling the debug_mode will put a `sleep infinity` as the entrypoint of the container. That way, we can later connect to the pod through SSH in VSCode, and run the entrypoint of the application from the debugger.

### Mounting local modules

The Charmed OSM Debugging mode allows you to mount local modules to the desired charms. The following commands show which modules can be mounted in each charm.

```bash
LCM_LOCAL_PATH="/path/to/LCM"
N2VC_LOCAL_PATH="/path/to/N2VC"
NBI_LOCAL_PATH="/path/to/NBI"
RO_LOCAL_PATH="/path/to/RO"
MON_LOCAL_PATH="/path/to/MON"
POL_LOCAL_PATH="/path/to/POL"
COMMON_LOCAL_PATH="/path/to/common"

# LCM
juju config lcm debug_lcm_local_path=$LCM_LOCAL_PATH
juju config lcm debug_n2vc_local_path=$N2VC_LOCAL_PATH
juju config lcm debug_common_local_path=$COMMON_LOCAL_PATH
# MON
juju config mon debug_mon_local_path=$MON_LOCAL_PATH
juju config mon debug_n2vc_local_path=$N2VC_LOCAL_PATH
juju config mon debug_common_local_path=$COMMON_LOCAL_PATH
# NBI
juju config nbi debug_nbi_local_path=$LCM_LOCAL_PATH
juju config nbi debug_common_local_path=$COMMON_LOCAL_PATH
# RO
juju config ro debug_ro_local_path=$RO_LOCAL_PATH
juju config ro debug_common_local_path=$COMMON_LOCAL_PATH
# POL
juju config pol debug_pol_local_path=$POL_LOCAL_PATH
juju config pol debug_common_local_path=$COMMON_LOCAL_PATH
```

### Generate SSH config file

Preparing the pods includes setting up the `~/.ssh/config` so the VSCode can easily discover which ssh hosts are available

Just execute:

```bash
./generate_ssh_config.sh
```

> NOTE: The public key that will be used will be `$HOME/.ssh/id_rsa.pub`. If you want to use a different one, add the absolute path to it as a first argument: `./generate_ssh_config.sh /path/to/key.pub`.

### Connect to Pods

In VScode, navigate to [Remote Explorer](https://code.visualstudio.com/docs/remote/ssh#_remember-hosts-and-advanced-settings), and select the pod to which you want to connect.

You should be able to see the following hosts in the Remote Explorer:

- lcm
- mon
- nbi
- ro
- pol

Right click on the host, and "Connect to host in a New Window".

### Add workspace

The `./generate_ssh_config.sh` script adds a workspace to the `/root` folder of each pod, with the following name: `debug.code-workspace`.

In the window of the connected host, go to `File/Open Workspace from File...`. Then select the `debug.code-workspace` file.

### Run and Debug

Open the `Terminal` tab, and the Python extension will be automatically downloaded. It will be installed in the remote pod.

Go to the `Explorer (ctrl + shift + E)` to see the module folders in the charm. You can add breakpoints and start debugging. 

Go to the `Run and Debug (ctrl + shift + D)` and press `F5` to start the main entrypoint of the charm.

Happy debugging!
