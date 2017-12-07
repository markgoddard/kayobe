#!/bin/bash

# Deploy a cloud, end-to-end.

# Issues:
# * Can't use overlay storage driver for seed because ansible fails when running
#   template module for bifrost.
# * Issue in shade list_nics_for_machine. Upstream fix made.
# * Need https://review.openstack.org/#/c/526007
# * Glean didn't work on controller because eth0 ifcfg script existed due to
#   cloud-init. Prevent cloud-init from creating this?

set -e

PARENT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# FIXME: Chicken and egg...
#git clone https://markgoddard@github.com/markgoddard/kayobe -b scripted-dev-env
#cd kayobe/

mkdir -p config/src
if [[ ! -d config/src/kayobe-config ]]; then
    git clone https://markgoddard@github.com/stackhpc/dev-kayobe-config -b add-seed-and-hv config/src/kayobe-config
fi

$PARENT/install.sh

# Seed hypervisor

# FIXME: use a libvirt network?
sudo iptables -t nat -A POSTROUTING -o em1 -j MASQUERADE
# FIXME: use a libvirt network?

sudo sysctl -w net.ipv4.conf.all.forwarding=1
$PARENT/seed-hypervisor-deploy.sh

# Seed

# FIXME: Configdrive in seed did not apply an IP address or resolv.conf.
# Manually modified seed-root image via guestfish.
$PARENT/seed-deploy.sh

# Controller

# Create and boot a controller.
sudo virsh vol-create-as --pool default --name controller-root --capacity 100G --format qcow2
sudo virsh define $PARENT/controller.xml
sudo virsh start controller0

# Wait for discovery
sleep 120

# Install VBMC
sudo yum -y install libvirt-devel
virtualenv vbmc-venv
vbmc-venv/bin/pip install -U pip
vbmc-venv/bin/pip install virtualbmc
# sudo required for libvirt currently
sudo vbmc-venv/bin/vbmc add controller0 --port 1234 --username admin --password admin
sudo vbmc-venv/bin/vbmc start controller0

# Fix up ironic node.
node_uuid=$(ssh centos@192.168.33.5 sudo docker exec bifrost_deploy bash -c '"OS_CLOUD=bifrost OS_BAREMETAL_API_VERSION=1.34 openstack baremetal node list -f value --fields uuid"')
ssh centos@192.168.33.5 \
  sudo docker exec bifrost_deploy \
  bash -c '"OS_CLOUD=bifrost OS_BAREMETAL_API_VERSION=1.34 openstack baremetal node set '$node_uuid' --name controller0 --driver-info ipmi_address=192.168.33.4 --driver-info ipmi_username=admin --driver-info ipmi_password=admin --driver-info ipmi_port=1234"'

# Discover & provision
(source dev/environment-setup.sh ; kayobe overcloud inventory discover)
(source dev/environment-setup.sh ; kayobe overcloud provision)

# Deploy
$PARENT/overcloud-deploy.sh
