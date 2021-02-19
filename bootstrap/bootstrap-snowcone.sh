#!/usr/bin/env bash

if [[ -z "$SNOW_IP" ]]; then
  echo "SNOW_IP not defined! Example: 192.168.1.42"
  exit 1
fi

if [[ -z "$SNOW_MANIFEST" ]]; then
  echo "SNOW_MANIFEST not defined! Example: /path/to/uuid-manifest.manifest.bin"
  exit 1
fi

if [[ -z "$SNOW_UNLOCK_CODE" ]]; then
  echo "SNOW_UNLOCK_CODE not defined! Example: 4efb4a13-d763-460b-be02-66da384e74b7"
  exit 1
fi

if [[ -z "$SNOW_AMI_NAME" ]]; then
  echo "SNOW_AMI_NAME not defined! Example: my-ubuntu1604-ami"
  exit 1
fi

if [[ -z "$SNOW_EC2_IP" ]]; then
  echo "SNOW_EC2_IP not defined! Example: 192.168.1.43"
  exit 1
fi

if [[ -z "$SNOW_NFS_IP" ]]; then
  echo "SNOW_NFS_IP not defined! Example: 192.168.1.44"
  exit 1
fi

if [[ -z "$SNOW_NFS_ALLOWED" ]]; then
  echo "SNOW_NFS_ALLOWED not defined! Example: 192.168.1.0/24"
  exit 1
fi

if [[ -z "$SNOW_NETMASK" ]]; then
  echo "SNOW_NETMASK not defined! Example: 255.255.255.0"
  exit 1
fi

if [[ -z "$AWS_REGION" ]]; then
  echo "AWS_REGION not defined! Example: eu-central-1"
  exit 1
fi

if [[ -z "$GREENGRASS_PROVISIONER_AWS_ACCESS_KEY_ID" ]]; then
  echo "GREENGRASS_PROVISIONER_AWS_ACCESS_KEY_ID not defined!"
  exit 1
fi

if [[ -z "$GREENGRASS_PROVISIONER_AWS_SECRET_ACCESS_KEY" ]]; then
  echo "GREENGRASS_PROVISIONER_AWS_SECRET_ACCESS_KEY not defined!"
  exit 1
fi

if [[ -z "$THING_NAME" ]]; then
  echo "THING_NAME not defined! Example: FlyThing_001"
  exit 1
fi

if [[ -z "$THING_GROUP" ]]; then
  echo "THING_GROUP not defined! Examples: FlyThings"
  exit 1
fi

if ! command -v aws &> /dev/null ; then
  echo "awscli not found! Please install via https://aws.amazon.com/cli/"
  exit 1
fi

if ! command -v snowballEdge &> /dev/null ; then
  echo "snowballEdge not found! Please install via https://aws.amazon.com/snowball/resources/#Snowball_Edge_Client"
  exit 1
fi

if ! command -v jq &> /dev/null ; then
  echo "jq not found! Please install via https://stedolan.github.io/jq/"
  exit 1
fi

set -o nounset
set -o pipefail
set -x

timestamp() {
  date +%Y-%m-%dT%H:%M:%SZ%z
}

export AWS_PAGER=""
export AWS_CLI_AUTO_PROMPT=""

snowballEdge unlock-device \
  --endpoint https://${SNOW_IP} \
  --manifest-file "${SNOW_MANIFEST}" \
  --unlock-code "${SNOW_UNLOCK_CODE}"

snowballEdge wait unlocked \
  --endpoint https://${SNOW_IP} \
  --manifest-file "${SNOW_MANIFEST}" \
  --unlock-code "${SNOW_UNLOCK_CODE}"

SNOW_NIC=$(snowballEdge describe-device \
  --endpoint https://${SNOW_IP} \
  --manifest-file "${SNOW_MANIFEST}" \
  --unlock-code "${SNOW_UNLOCK_CODE}" | \
  jq -r '.PhysicalNetworkInterfaces[0].PhysicalNetworkInterfaceId')

SNOW_ACCESS_KEY=$(snowballEdge list-access-keys \
  --endpoint https://${SNOW_IP} \
  --manifest-file "${SNOW_MANIFEST}" \
  --unlock-code "${SNOW_UNLOCK_CODE}" |
  jq -r '.AccessKeyIds[]')

snowballEdge get-secret-access-key \
  --endpoint https://${SNOW_IP} \
  --manifest-file "${SNOW_MANIFEST}" \
  --unlock-code "${SNOW_UNLOCK_CODE}" \
  --access-key-id "${SNOW_ACCESS_KEY}" | \
  grep "^aws_" | \
  sed 's/ =//' | \
  xargs -I {} bash -c "aws --profile snow configure set {}"
aws --profile snow configure set region snow

######### NFS

# this is expected to fail if the VNI is already created
snowballEdge create-virtual-network-interface \
  --endpoint https://${SNOW_IP} \
  --manifest-file "${SNOW_MANIFEST}" \
  --unlock-code "${SNOW_UNLOCK_CODE}" \
  --ip-address-assignment STATIC \
  --static-ip-address-configuration "IpAddress=${SNOW_NFS_IP},Netmask=${SNOW_NETMASK}" \
  --physical-network-interface-id "${SNOW_NIC}"

# create-virtual-network-interface fails if already created, so fetch the ARN separately

SNOW_NFS_VNI_ARN=$(snowballEdge describe-virtual-network-interfaces \
  --endpoint https://${SNOW_IP} \
  --manifest-file "${SNOW_MANIFEST}" \
  --unlock-code "${SNOW_UNLOCK_CODE}" | \
  jq -r ".VirtualNetworkInterfaces[] | select(.IpAddress==\"${SNOW_NFS_IP}\") | .VirtualNetworkInterfaceArn")

snowballEdge start-service \
  --endpoint https://${SNOW_IP} \
  --manifest-file "${SNOW_MANIFEST}" \
  --unlock-code "${SNOW_UNLOCK_CODE}" \
  --service-id nfs \
  --virtual-network-interface-arns "${SNOW_NFS_VNI_ARN}" \
  --service-configuration "AllowedHosts=${SNOW_NFS_ALLOWED}"

######### EC2 Instance

EC2_INSTANCE_ID=$(aws --profile snow --endpoint http://${SNOW_IP}:8008 \
    ec2 describe-instances | \
    jq -r 'first(.Reservations[].Instances[] | select(.Tags==[{"Key":"Name","Value":"AvionicsDataCollection"}]) | select(.State.Name!="terminated") | select(.State.Name!="shutting-down") | .InstanceId)')

if [[ ! -z "${EC2_INSTANCE_ID}" ]] ; then
  # this is expected to fail if the instance is already running
  aws --profile snow --endpoint http://${SNOW_IP}:8008 \
    ec2 start-instances \
    --instance-ids "${EC2_INSTANCE_ID}"
else
  IMAGE_ID=$(aws --profile snow --endpoint http://${SNOW_IP}:8008 \
    ec2 describe-images | \
    jq -r ".Images[] | select(.Name==\"$SNOW_AMI_NAME\") | .ImageId")

  envsubst < bootstrap-flything.sh > ec2-user-data.txt

  EC2_INSTANCE_ID=$(aws --profile snow --endpoint http://${SNOW_IP}:8008 \
    ec2 run-instances \
    --image-id "${IMAGE_ID}" \
    --instance-type snc1.medium \
    --user-data file://ec2-user-data.txt \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=AvionicsDataCollection}]" | \
    jq -r '.Instances[0].InstanceId')
  rm ec2-user-data.txt

  # this is expected to fail if the VNI is already created
  snowballEdge create-virtual-network-interface \
    --endpoint https://${SNOW_IP} \
    --manifest-file "${SNOW_MANIFEST}" \
    --unlock-code "${SNOW_UNLOCK_CODE}" \
    --ip-address-assignment STATIC \
    --static-ip-address-configuration "IpAddress=${SNOW_EC2_IP},Netmask=${SNOW_NETMASK}" \
    --physical-network-interface-id "${SNOW_NIC}"
fi

set +x
while true ; do
  sleep 2
  EC2_STATE=$(aws --profile snow --endpoint http://${SNOW_IP}:8008 \
    ec2 describe-instances | \
    jq -r ".Reservations[].Instances[] | select(.InstanceId==\"${EC2_INSTANCE_ID}\") | .State.Name")
  if [[ "${EC2_STATE}" == "running" ]] ; then
    break
  else
    echo "$(timestamp) Instance still in state ${EC2_STATE}..."
  fi
done

aws --profile snow --endpoint http://${SNOW_IP}:8008 \
  ec2 associate-address \
  --public-ip "${SNOW_EC2_IP}" \
  --instance-id "${EC2_INSTANCE_ID}"

echo "$(timestamp) Snowcone fully bootstrapped! Instance is now provisioning itself..."
echo "$(timestamp) Instance is now provisioning itself - this might take a while."
