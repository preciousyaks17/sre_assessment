#!/usr/bin/env bash
# infrastructure/provisioning/02-deploy-online-boutique.sh
#
# Deploys Google's Online Boutique sample app (the 11 microservices this
# whole assessment is built around) onto the AKS cluster created in step 1.

set -euo pipefail

echo "==> Cloning Online Boutique manifests"
git clone --depth 1 https://github.com/GoogleCloudPlatform/microservices-demo.git /tmp/microservices-demo

echo "==> Applying manifests to the cluster"
kubectl apply -f /tmp/microservices-demo/release/kubernetes-manifests.yaml

echo "==> Waiting for pods to be ready (this can take a few minutes)"
kubectl wait --for=condition=ready pod --all --timeout=300s -n default || true

echo "==> Checking pod status"
kubectl get pods

echo "==> Getting frontend external IP (may take a minute or two to provision)"
echo "    Run this again if EXTERNAL-IP shows <pending>:"
kubectl get service frontend-external

echo ""
echo "==> Once you have an EXTERNAL-IP, that's your FRONTEND_URL for"
echo "    instrumentation/generate-checkout-traffic.sh later."
