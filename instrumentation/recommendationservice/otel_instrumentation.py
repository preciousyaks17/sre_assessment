# instrumentation/recommendationservice/otel_instrumentation.py
#
# recommendationservice (Python, gRPC) — instrumentation entrypoint.
#
# Usage: import and call `configure_tracing()` before the gRPC server starts
# (e.g. at the top of recommendation_server.py), then use the provided
# decorators/helpers for the required custom spans/metrics.
#
# Auto-instrumentation covers: gRPC server + client calls.
# Manual instrumentation adds: 2 business-logic spans + 1 custom metric,
# per Section 1.2 requirements.

import os

from opentelemetry import trace, metrics
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.instrumentation.grpc import GrpcInstrumentorServer, GrpcInstrumentorClient

# --- Resource attributes (requirement: service.name, service.version, deployment.environment) ---
# NODE_IP is injected via the K8s downward API (see values-agent.yaml Service
# routing note) so each pod talks to the DaemonSet agent on its own node.
NODE_IP = os.environ.get("NODE_IP", "localhost")
OTLP_ENDPOINT = f"http://{NODE_IP}:4318"  # local agent's OTLP/HTTP port

_resource = Resource.create({
    "service.name": "recommendationservice",
    "service.version": os.environ.get("SERVICE_VERSION", "1.0.0"),
    "deployment.environment": os.environ.get("DEPLOY_ENV", "assessment"),
})

_tracer_provider = None
_meter_provider = None
_recommendation_counter = None
_recommendation_latency_histogram = None


def configure_tracing():
    """Call once at service startup, before the gRPC server binds."""
    global _tracer_provider, _meter_provider
    global _recommendation_counter, _recommendation_latency_histogram

    # --- Traces ---
    _tracer_provider = TracerProvider(resource=_resource)
    span_exporter = OTLPSpanExporter(endpoint=f"{OTLP_ENDPOINT}/v1/traces")
    _tracer_provider.add_span_processor(BatchSpanProcessor(span_exporter))
    trace.set_tracer_provider(_tracer_provider)

    # --- Metrics ---
    metric_exporter = OTLPMetricExporter(endpoint=f"{OTLP_ENDPOINT}/v1/metrics")
    reader = PeriodicExportingMetricReader(metric_exporter, export_interval_millis=15000)
    _meter_provider = MeterProvider(resource=_resource, metric_readers=[reader])
    metrics.set_meter_provider(_meter_provider)

    meter = metrics.get_meter("recommendationservice")

    # Custom metric #1: counter of recommendations served (business-relevant signal)
    _recommendation_counter = meter.create_counter(
        name="recommendation.served.count",
        description="Number of product recommendations returned to clients",
        unit="1",
    )

    # Custom metric #2 (bonus, histogram): latency of the recommendation
    # generation logic specifically (distinct from the gRPC span duration,
    # which includes network overhead) — useful for isolating algorithm
    # slowness from transport slowness.
    _recommendation_latency_histogram = meter.create_histogram(
        name="recommendation.generation.duration",
        description="Time to generate the recommendation list, excluding gRPC transport",
        unit="ms",
    )

    # --- gRPC auto-instrumentation (server + client for downstream calls,
    # e.g. to productcatalogservice) ---
    GrpcInstrumentorServer().instrument()
    GrpcInstrumentorClient().instrument()


def get_tracer():
    return trace.get_tracer("recommendationservice")


# --- Custom span helpers (requirement: at least 2 custom spans capturing
# business-logic operations, with business-context attributes) ---

def traced_filter_candidates(product_ids, exclude_ids):
    """
    Custom span #1: 'filter-recommendation-candidates'
    Wraps the logic that removes already-in-cart / already-viewed products
    from the candidate pool before recommendation.
    """
    tracer = get_tracer()
    with tracer.start_as_current_span("filter-recommendation-candidates") as span:
        span.set_attribute("recommendation.candidate_count", len(product_ids))
        span.set_attribute("recommendation.excluded_count", len(exclude_ids))
        filtered = [p for p in product_ids if p not in exclude_ids]
        span.set_attribute("recommendation.filtered_count", len(filtered))
        return filtered


def traced_generate_recommendations(filtered_candidates, max_results, user_id=None):
    """
    Custom span #2: 'generate-recommendation-list'
    Wraps the actual selection logic and records the custom latency
    histogram + counter metric.
    """
    import random
    import time

    tracer = get_tracer()
    start = time.monotonic()

    with tracer.start_as_current_span("generate-recommendation-list") as span:
        if user_id:
            span.set_attribute("user.id", user_id)
        span.set_attribute("recommendation.max_results", max_results)

        # Simulated selection logic — real implementation would score/rank;
        # kept simple here since this is instrumentation, not the recsys.
        results = random.sample(
            filtered_candidates, min(max_results, len(filtered_candidates))
        )

        span.set_attribute("recommendation.result_count", len(results))
        span.add_event("recommendations-selected", {"count": len(results)})

        duration_ms = (time.monotonic() - start) * 1000
        _recommendation_latency_histogram.record(
            duration_ms, {"service.name": "recommendationservice"}
        )
        _recommendation_counter.add(
            len(results), {"service.name": "recommendationservice"}
        )

        return results
