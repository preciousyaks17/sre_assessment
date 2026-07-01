#!/usr/bin/env bash
# infrastructure/provisioning/99-teardown.sh
#
# Run this once the assessment is submitted, to avoid ongoing Azure charges.
# AKS clusters + VMs cost money every hour they're running.

set -euo pipefail

RESOURCE_GROUP="sre-assessment-rg"

echo "==> This will DELETE the entire resource group and everything in it."
read -p "Type 'yes' to confirm: " CONFIRM

if [ "$CONFIRM" = "yes" ]; then
  az group delete --name "$RESOURCE_GROUP" --yes --no-wait
  echo "==> Deletion started (running in background, check Azure portal for progress)."
else
  echo "==> Aborted. Nothing deleted."
fi

echo ""
echo "==> Also remember to delete/pause your Elastic Cloud trial deployment"
echo "    at https://cloud.elastic.co if you don't want it to auto-convert"
echo "    to a paid subscription after the trial period."
