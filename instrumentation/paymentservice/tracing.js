// instrumentation/paymentservice/tracing.js
//
// paymentservice (Node.js, gRPC) — instrumentation entrypoint.
//
// Usage: `node -r ./tracing.js server.js` OR require this file as the very
// first line of the service's main entrypoint, before any other imports
// (auto-instrumentation patches modules at require-time, so it must load
// first).
//
// Auto-instrumentation covers: gRPC server/client, HTTP.
// Manual instrumentation adds: 2 business-logic spans + error recording +
// 1 custom metric, per Section 1.2 requirements.

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { Resource } = require('@opentelemetry/resources');
const {
  SemanticResourceAttributes,
} = require('@opentelemetry/semantic-conventions');

// Local DaemonSet agent on this node (requirement 1.2.7: export to local
// agent via hostIP, not directly to the gateway/Elastic).
const NODE_IP = process.env.NODE_IP || 'localhost';
const OTLP_ENDPOINT = `http://${NODE_IP}:4318`;

const resource = new Resource({
  [SemanticResourceAttributes.SERVICE_NAME]: 'paymentservice',
  [SemanticResourceAttributes.SERVICE_VERSION]: process.env.SERVICE_VERSION || '1.0.0',
  [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: process.env.DEPLOY_ENV || 'assessment',
});

const traceExporter = new OTLPTraceExporter({
  url: `${OTLP_ENDPOINT}/v1/traces`,
});

const metricExporter = new OTLPMetricExporter({
  url: `${OTLP_ENDPOINT}/v1/metrics`,
});

const sdk = new NodeSDK({
  resource,
  traceExporter,
  metricReader: new PeriodicExportingMetricReader({
    exporter: metricExporter,
    exportIntervalMillis: 15000,
  }),
  instrumentations: [
    getNodeAutoInstrumentations({
      // keep fs instrumentation off — noisy, not useful for this service
      '@opentelemetry/instrumentation-fs': { enabled: false },
    }),
  ],
});

sdk.start();

process.on('SIGTERM', () => {
  sdk.shutdown().finally(() => process.exit(0));
});

module.exports = { sdk };
