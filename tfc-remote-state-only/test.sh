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

token="$(jq -r '.credentials."app.terraform.io".token' < ~/.terraform.d/credentials.tfrc.json)"

# Always work from a fresh workspace
workspace="investigation-${RANDOM}"
org="o"
printf "organization = \"%s\"\nworkspaces { name = \"%s\" }" \
  "$org" \
  "$workspace" \
  > tmp.hcl

function finish {
  curl \
    --header "Authorization: Bearer $token" \
    --header "Content-Type: application/vnd.api+json" \
    --request DELETE \
    "https://app.terraform.io/api/v2/organizations/${org}/workspaces/${workspace}"

  rm -rf .terraform
  rm -rf tmp.hcl
  cp m/m.before m/m.tf
}
trap finish EXIT

# Initialize and apply, creating a state file. This is important because it
# adds the upgrade conditions of the plugin resolution system into the state
# file.
tf12 init --input=false \
   -backend-config=tmp.hcl

# That init will have created a fresh workspace. Set it to local exec mode.
curl \
  --header "Authorization: Bearer $token" \
  --header "Content-Type: application/vnd.api+json" \
  --request PATCH \
  --data @payload.json \
  "https://app.terraform.io/api/v2/organizations/${org}/workspaces/${workspace}" | jq

# Now apply to push a state into the workspace.
tf12 apply --auto-approve

# I couldn't _exactly_ understand why this is necessary, but I couldn't
# reproduce the failure without it, trigger a change in the module.
cp m/m.after m/m.tf

# Now delete the .terraform directory.
rm -rf .terraform

# This is roughly the conditions under which TBW would start a plan. It is
# initilizing without a .terraform directory, but with the backend.
tf13 init --input=false \
  -backend-config=tmp.hcl

# Write out the plan, this will be used to apply later.
tf13 plan -out plan.out

# Now reinitialize without the backend and without the backend configuration
# cached in .terraform/terraform.tfstate.
rm -rf .terraform/terraform.tfstate
tf13 init --input=false -backend=false

# Unfortunately, it will be missing configuration needed to properly use this
# plan file, and this will fail.
tf13 apply plan.out
