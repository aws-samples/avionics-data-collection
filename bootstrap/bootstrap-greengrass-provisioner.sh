#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -x

THING_GROUP="FlyThings"

# https://docs.aws.amazon.com/greengrass/v2/developerguide/install-greengrass-core-v2.html#provision-minimal-iam-policy
cat << EOF > policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iot:AddThingToThingGroup",
        "iot:AttachPolicy",
        "iot:AttachThingPrincipal",
        "iot:CreateKeysAndCertificate",
        "iot:CreatePolicy",
        "iot:CreateRoleAlias",
        "iot:CreateThing",
        "iot:CreateThingGroup",
        "iot:DescribeEndpoint",
        "iot:DescribeRoleAlias",
        "iot:DescribeThingGroup",
        "iot:GetPolicy",
        "iam:GetRole",
        "iam:CreateRole",
        "iam:PassRole",
        "iam:CreatePolicy",
        "iam:AttachRolePolicy",
        "iam:GetPolicy",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
EOF
POLICY_ARN=$(aws iam create-policy \
  --policy-name GreengrassV2ProvisionerPolicy \
  --policy-document file://policy.json | \
  jq -r '.Policy.Arn')
rm policy.json

aws iam create-user \
  --user-name GreengrassV2Provisioner

aws iam attach-user-policy \
  --user-name GreengrassV2Provisioner \
  --policy-arn ${POLICY_ARN}

aws iam create-access-key \
  --user-name GreengrassV2Provisioner | \
  jq -r '"# GreengrassV2Provisioner Access Keys: export GREENGRASS_PROVISIONER_AWS_ACCESS_KEY_ID=\(.AccessKey.AccessKeyId) ; export GREENGRASS_PROVISIONER_AWS_SECRET_ACCESS_KEY=\(.AccessKey.SecretAccessKey)"'

################################################################################
# https://docs.aws.amazon.com/greengrass/v2/developerguide/device-service-role.html

cat << EOF > role-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "credentials.iot.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
ROLE_ARN=$(aws iam create-role \
  --role-name GreengrassV2TokenExchangeRole \
  --description "Role for Greengrass IoT things to interact with AWS services using token exchange service" \
  --assume-role-policy-document file://role-policy.json | \
  jq -r '.Role.Arn')
rm role-policy.json

aws iot create-role-alias \
  --role-alias GreengrassV2TokenExchangeRoleAlias
  --role-arn ${ROLE_ARN}

cat << EOF > policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iot:DescribeCertificate",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
        "iot:Connect",
        "iot:Publish",
        "iot:Subscribe",
        "iot:Receive",
        "s3:GetBucketLocation"
      ],
      "Resource": "*"
    }
  ]
}
EOF
POLICY_ARN=$(aws iam create-policy \
  --policy-name GreengrassV2TokenExchangeRoleAccess \
  --policy-document file://policy.json | \
  jq -r '.Policy.Arn')
rm policy.json

aws iam attach-role-policy \
  --role-name GreengrassV2TokenExchangeRole \
  --policy-arn ${POLICY_ARN}

aws iam attach-role-policy \
  --role-name GreengrassV2TokenExchangeRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

aws iot create-thing-group \
  --thing-group-name "${THING_GROUP}"
