#!/usr/bin/env bash
# infrastructure/provisioning/04-install-otel-collector.sh
#
# Installs the OTel Collector agent (DaemonSet) and gateway (Deployment)
# using the values files already written in otel-collector/.
#
# PREREQUISITE: fill in the 2 Elastic values from the OpenTelemetry setup
# screen in Kibana before running this script:
#
#   export ELASTIC_OTLP_ENDPOINT="https://your-project.ingest.region.azure.elastic.cloud:443"
#   export ELASTIC_API_KEY="your-api-key-here"

set -euo pipefail

: "${ELASTIC_OTLP_ENDPOINT:?Set ELASTIC_OTLP_ENDPOINT first}"
: "${ELASTIC_API_KEY:?Set ELASTIC_API_KEY first}"

NAMESPACE="observability"

echo "==> Creating namespace"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Creating secret with Elastic OTLP credentials"
kubectl create secret generic elastic-otlp-credentials \
  --namespace "$NAMESPACE" \
  --from-literal=ELASTIC_OTLP_ENDPOINT="$ELASTIC_OTLP_ENDPOINT" \
  --from-literal=ELASTIC_API_KEY="$ELASTIC_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Adding the OpenTelemetry Helm repo"
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

echo "==> Installing the DaemonSet agent"
helm upgrade --install otel-agent open-telemetry/opentelemetry-collector \
  --namespace "$NAMESPACE" \
  --values ../otel-collector/values-agent.yaml

echo "==> Installing the central gateway"
helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector \
  --namespace "$NAMESPACE" \
  --values ../otel-collector/values-gateway.yaml

echo "==> Checking rollout status"
kubectl get pods -n "$NAMESPACE"

echo ""
echo "==> Once pods are Running, check logs to confirm no export errors:"
echo "    kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=opentelemetry-collector -f"
echo ""
echo "==> Then check Kibana -> Observability -> APM -> Services for incoming data."
echo "    (Services won't appear until instrumented app traffic flows — that's step 5.)"
