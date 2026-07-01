#!/usr/bin/env bash
# infrastructure/provisioning/01-create-aks-cluster.sh
#
# Run this yourself in Azure Cloud Shell or a terminal with `az` CLI logged in.
# Creates a small, cost-conscious AKS cluster for the assessment.

set -euo pipefail

RESOURCE_GROUP="sre-assessment-rg"
LOCATION="eastus"          # change if you want a region closer to Lagos, e.g. "southafricanorth"
CLUSTER_NAME="sre-assessment-aks"
NODE_COUNT=3
NODE_SIZE="Standard_D2s_v3"   # 2 vCPU / 8GB — enough for Online Boutique + OTel collector + Elastic Agent

echo "==> Logging in (if not already)"
az login

echo "==> Creating resource group"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

echo "==> Creating AKS cluster (this takes 5-10 minutes)"
az aks create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --node-count "$NODE_COUNT" \
  --node-vm-size "$NODE_SIZE" \
  --generate-ssh-keys \
  --enable-managed-identity

echo "==> Fetching kubeconfig"
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --overwrite-existing

echo "==> Verifying cluster access"
kubectl get nodes

echo "==> Done. Cluster is ready."
echo "==> IMPORTANT: remember to run 99-teardown.sh when finished to avoid ongoing Azure charges."
