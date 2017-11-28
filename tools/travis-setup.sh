#!/bin/bash

# Script for running a TravisCI job to test use of kayobe.
# Deploys a single host control plane in the job's VM.

set -e

# Clone the development kayobe configuration.
mkdir -p config/src
git clone https://github.com/stackhpc/dev-kayobe-config \
  -b container-config \
  config/src/kayobe-config

# Generate an SSH key.
ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa
