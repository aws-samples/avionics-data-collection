#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -x

# Let the system boot up
sleep 30

# Install dependencies and tooling - this section should be baked into the AMI
apt-get --quiet update
apt-get --yes install --no-install-recommends nfs-common default-jdk-headless

# Download AWS IoT Greengrass Core v2 and install dependencies - this section can be baked into the AMI
# https://docs.aws.amazon.com/greengrass/v2/developerguide/install-greengrass-core-v2.html
mkdir -p /greengrass
curl -s https://d2s8p88vqu9w66.cloudfront.net/releases/greengrass-nucleus-latest.zip > /greengrass/greengrass-nucleus-latest.zip
unzip -o /greengrass/greengrass-nucleus-latest.zip -d /greengrass/GreengrassCore
rm -f /greengrass/greengrass-nucleus-latest.zip

# Mount NFS share from Snowcone
mkdir -p /snowcone_nfs
echo "${SNOW_NFS_IP}:/buckets /snowcone_nfs nfs defaults 0 0" | tee -a /etc/fstab > /dev/null
mount --all

# USE ONLY FOR PROTOTYPING! Configure credentials for Greengrass provisioning
export AWS_ACCESS_KEY_ID="${GREENGRASS_PROVISIONER_AWS_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${GREENGRASS_PROVISIONER_AWS_SECRET_ACCESS_KEY}"

# Install AWS IoT Greengrass Core v2, provision thing, and enable auto-start
# https://docs.aws.amazon.com/greengrass/v2/developerguide/install-greengrass-core-v2.html
# Workaround: use the -Droot to specify a root directory, instead of the --root option, to prevent file permission errors (v2.0.3 and earlier)
# see https://github.com/aws-greengrass/aws-greengrass-logging-java/pull/98 for the fix
java \
  -Dlog.store=FILE \
  -Droot="/greengrass/v2" \
  -jar /greengrass/GreengrassCore/lib/Greengrass.jar \
  --aws-region "${AWS_REGION}" \
  --thing-name "${THING_NAME}" \
  --thing-group-name "${THING_GROUP}" \
  --tes-role-name GreengrassV2TokenExchangeRole \
  --tes-role-alias-name GreengrassV2TokenExchangeRoleAlias \
  --component-default-user ggc_user:ggc_group \
  --provision true \
  --setup-system-service true
