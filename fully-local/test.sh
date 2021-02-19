#! /usr/bin/env bash
set -euo pipefail

if ! command -v "tf12" > /dev/null 2>&1 ; then
  echo "Create an alias for terraform 0.12 as tf12"
  exit 1
fi

if ! command -v "tf13" > /dev/null 2>&1 ; then
  echo "Create an alias for terraform 0.13 as tf13"
  exit 1
fi

function finish {
  rm -rf plan.out
  rm -rf .terraform
  rm -rf terraform.tfstate
  rm -rf terraform.tfstate.backup
  cp m/m.before m/m.tf
}
trap finish EXIT

# Initialize and apply, creating a state file. This is important because it
# adds the upgrade conditions of the plugin resolution system into the state
# file.
tf12 init --input=false
tf12 apply --auto-approve

# I couldn't _exactly_ understand why this is necessary, but I couldn't
# reproduce the failure without it, trigger a change in the module.
cp m/m.after m/m.tf

# Now delete the .terraform directory.
rm -rf .terraform

# This is roughly the conditions under which TBW would start a plan. It is
# initilizing without a .terraform directory, but with the backend.
tf13 init --input=false

cat .terraform/plugins/selections.json

# Write out the plan, this will be used to apply later.
tf13 plan -out plan.out

# Now reinitialize without the presence of the state files, this won't have
# properly setup the providers in our case.
rm -rf terraform.tfstate terraform.tfstate.backup
tf13 init --input=false

cat .terraform/plugins/selections.json

# Unfortunately, it will be missing configuration needed to properly use this
# plan file, and this will fail.
tf13 apply plan.out
