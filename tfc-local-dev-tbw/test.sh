#! /usr/bin/env bash
set -euo pipefail
set -x

if ! command -v "tf12" > /dev/null 2>&1 ; then
  echo "Create an alias for terraform 0.12 as tf12"
  exit 1
fi

if ! command -v "tf13" > /dev/null 2>&1 ; then
  echo "Create an alias for terraform 0.13 as tf13"
  exit 1
fi

# Always work from a fresh workspace
workspace="investigation-${RANDOM}"
org="hashicorp"
hostname="tfe-zone-4e8a2daa.ngrok.io"

printf "organization = \"%s\"\nworkspaces { name = \"%s\" }\nhostname=\"%s\"" \
  "$org" \
  "$workspace" \
  "$hostname" \
  > tmp.hcl

token="$(jq -r ".credentials.\"${hostname}\".token" < ~/.terraform.d/credentials.tfrc.json)"

function finish {
  # On our way out, do all these even if they fail.
  set +e
  curl \
    --header "Authorization: Bearer $token" \
    --header "Content-Type: application/vnd.api+json" \
    --request DELETE \
    "https://${hostname}/api/v2/organizations/${org}/workspaces/${workspace}"

  rm -rf .terraform
  rm -rf tmp.hcl
  rm -rf plan.out
  cp m/m.before m/m.tf
}
trap finish EXIT

# Initialize and apply, creating a state file. This is important because it
# adds the upgrade conditions of the plugin resolution system into the state
# file.
tf12 init --input=false \
   -backend-config=tmp.hcl

# Now apply to push a state into the workspace.
tf12 apply --auto-approve

# I couldn't _exactly_ understand why this is necessary, but I couldn't
# reproduce the failure without it, trigger a change in the module.
cp m/m.after m/m.tf

# Reinitialize with tf 0.13
tf13 init --input=false \
  -backend-config=tmp.hcl

# Set the workspace version to 0.13
curl \
  --header "Authorization: Bearer $token" \
  --header "Content-Type: application/vnd.api+json" \
  --request PATCH \
  --data @payload.json \
  "https://${hostname}/api/v2/organizations/${org}/workspaces/${workspace}" | jq

# Now trigger the apply through TFC
tf13 apply --auto-approve
