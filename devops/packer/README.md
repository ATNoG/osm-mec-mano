# Creation of standard VM images with Packer

## Reference

These Packer templates are derived from the templates for building Vagrant boxes for various OS produced by the [Bento Project](https://github.com/chef/bento), produced under Apache 2 license.

## Pre-requirements

- Hypervisor installed to generate the required type of boxes (e.g. VirtualBox, VMware, Parallels, etc.)
- Packer >=1.6.5
- Optional:
  - Vagrant >=2.2
  - An Openstack cloud available.

## How to build images from Packer templates

Example 1: How to build an OSM box just for the VirtualBox provider:

```bash
cd packer_templates/osm
packer build -only=virtualbox-iso osm-8.0.4-amd64.json
```

Example 2: How to build an OSM VM with the OpenStack provider:

```bash
source openrc.sh    # This is only needed the first time
jq 'del(."post-processors")' osm-8.0.4-amd64.json > tmp.json
packer build -only=openstack tmp.json
rm tmp.json
```

As it can be seen, this type of build needs some additional details and commands, since:

- We need to source the **OpenStack credentials**, besides **additional environment variables** that are required to pass cloud-dependent parameters to Packer.
- We must **rip the `post-processors` part** of the template, since it is likely to be incompatible with the `openstack` builder. This rip can be made easily `jq` but, unfortunately, Packer does not work reliably with piped inputs, so we need to use an intermediate temporary file.

## How to test Vagrant boxes produced by Packer

1. Import the local box into Packer:
   ```bash
   cd ../../builds
   vagrant box add --name osm/osm-rel8 osm-8.0.4.virtualbox.box
   ```
2. Use the example at `vagrant_tests` to test it:
   ```bash
   cd ../vagrant_tests/
   # Edit the box name in `Vagrantfile` as appropriate
   vagrant up
   ```
3. In case the local image is no longer needed, it can be removed by:
   ```bash
   vagrant destroy
   vagrant box remove osm/osm-rel8
   ```

## How to upload boxes to Vagrant Cloud

You need to use the [Vagrant web page](https://app.vagrantup.com/boxes/search).

Here there is a [step-by-step guide](https://blog.ycshao.com/2017/09/16/how-to-upload-vagrant-box-to-vagrant-cloud/) with screenshots.
