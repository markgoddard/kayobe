#!/bin/bash

# Deploy a control plane onto a CentOS host running in a Docker container.
# Issues:
# - Had to disable keepalived due to ip_vs permissions issues. To try:
#   - -v /lib/modules:/lib/modules:ro
# - net=host not working after complete run (also used -v /run:/run:shared).
# - Nova sysctls for bridging not working when net=default. To try:
#   - --device=/proc/sys/net/bridge:/proc/sys/net/bridge
#   - set_sysctl=false

set -e

# Ensure passwordless sudo
sudo echo hi

sudo modprobe overlay

# Required for keepalived.
sudo modprobe ip_vs

# FIXME: Not working.
#ssh-keygen -f "~/.ssh/known_hosts" -R [localhost]:2223

build=1
hostname=controller0
ip=192.168.33.3
net=default
ssh_key=~/.ssh/id_rsa
if [[ $net == "host" ]]; then
    port=22
else
    port=2223
fi

if [[ $(docker ps -qf name=centos-sshd) = "" ]]; then
    if [[ $build -eq 1 ]]; then
        cp ~/.ssh/id_rsa.pub tools/test-ssh-key.pub
        docker build -f tools/Dockerfile.CentOS -t markgoddard/centos-sshd tools
    else
        docker pull markgoddard/centos-sshd
    fi
  
    # Run as a privileged daemon, to support docker-in-docker.
    # Make /var/lib/docker a volume, to work around problems with nested overlay
    # file systems due to docker-in-docker.
    # Read only mount the host's cgroups sysfs, and add required tmp directories.
    # Use the host's network namespace.
    # Add a host entry for the ansible hostname (controller0) pointing to the
    # API address.
    # Forward port 2223 for SSH.
    docker run \
        -d \
        --privileged \
        -v centos-sshd-docker:/var/lib/docker \
        -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
        -v /lib/modules:/lib/modules:ro \
        --device=/proc/sys/net/bridge:/proc/sys/net/bridge \
        --tmpfs /run \
        --tmpfs /tmp \
        --net=$net \
        --hostname $hostname \
        --add-host $hostname:$ip \
        -p $port:22 \
        --name centos-sshd \
        markgoddard/centos-sshd
fi

until ssh -i $ssh_key root@localhost -p $port -o StrictHostKeyChecking=no rm -f /run/nologin; do
    sleep 1
done
