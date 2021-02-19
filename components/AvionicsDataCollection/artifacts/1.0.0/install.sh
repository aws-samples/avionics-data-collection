#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -x

# wait for apt-get to be available
while fuser /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
  sleep 5
done

apt-get --quiet update
apt-get --yes install python3 python3-pip
pip3 install requests awsiotsdk==1.5.4
