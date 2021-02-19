#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -x

AWS_REGION=$(aws configure get region)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r '.Account')
THING_GROUP="FlyThings"
GG_COMPONENT_BUCKET="s3://EXAMPLE-AVIONICS-DATA-COLLECTION"

GG_COMPONENT_VERSION=$(grep "ComponentVersion" components/AvionicsDataCollection/recipe/AvionicsDataCollection.yaml | \
  sed -E -e 's/^ComponentVersion: +//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" \
)

aws s3 sync components/AvionicsDataCollection/artifacts/${GG_COMPONENT_VERSION} "${GG_COMPONENT_BUCKET}/AvionicsDataCollection/${GG_COMPONENT_VERSION}"

aws greengrassv2 create-component-version \
  --inline-recipe fileb://components/AvionicsDataCollection/recipe/AvionicsDataCollection.yaml

sleep 2

aws greengrassv2 create-deployment \
  --target-arn "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:thinggroup/${THING_GROUP}" \
  --deployment-name "${THING_GROUP}Deployment" \
  --components AvionicsDataCollection={componentVersion=${GG_COMPONENT_VERSION}}
