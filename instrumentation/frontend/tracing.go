// instrumentation/frontend/tracing.go
//
// frontend (Go) — OTel SDK setup.
//
// Go's OTel ecosystem doesn't have "auto-instrumentation" in the same sense
// as Python/Node (no bytecode weaving) — "auto" here means using the
// off-the-shelf otelhttp / otelgrpc middleware wrappers rather than manual
// span creation for every handler, which is the Go-idiomatic equivalent.
//
// Call InitTracer() once in main() before starting the HTTP server.

package tracing

import (
	"context"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	otelmetric "go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
)

var Tracer = otel.Tracer("frontend")
var Meter = otel.Meter("frontend")

// AddToCartCounter — custom metric (requirement 1.2.5): counts add-to-cart
// clicks, a directly business-relevant signal for the funnel dashboard in
// Section 2.2 (Dashboard 3, cart abandonment indicator).
var AddToCartCounter, _ = Meter.Int64Counter(
	"frontend.cart.add_to_cart.count",
	otelmetric.WithDescription("Number of add-to-cart actions submitted from the frontend"),
	otelmetric.WithUnit("1"),
)

func InitTracer(ctx context.Context) (func(context.Context) error, error) {
	nodeIP := os.Getenv("NODE_IP")
	if nodeIP == "" {
		nodeIP = "localhost"
	}
	agentEndpoint := nodeIP + ":4317" // local DaemonSet agent, OTLP/gRPC

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName("frontend"),
			semconv.ServiceVersion(getEnvOrDefault("SERVICE_VERSION", "1.0.0")),
			semconv.DeploymentEnvironment(getEnvOrDefault("DEPLOY_ENV", "assessment")),
		),
	)
	if err != nil {
		return nil, err
	}

	traceExporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(agentEndpoint),
		otlptracegrpc.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter),
		sdktrace.WithResource(res),
		// Note: sampling decision at this SDK level is left at "always on" —
		// the actual sampling happens at the gateway (tail-based), so the
		// agent/SDK layer should forward everything and let the gateway decide.
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
	)
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{}, // W3C traceparent — required for cross-service propagation
		propagation.Baggage{},
	))

	metricExporter, err := otlpmetricgrpc.New(ctx,
		otlpmetricgrpc.WithEndpoint(agentEndpoint),
		otlpmetricgrpc.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}
	mp := metric.NewMeterProvider(
		metric.WithResource(res),
		metric.WithReader(metric.NewPeriodicReader(metricExporter)),
	)
	otel.SetMeterProvider(mp)

	shutdown := func(ctx context.Context) error {
		if err := tp.Shutdown(ctx); err != nil {
			return err
		}
		return mp.Shutdown(ctx)
	}
	return shutdown, nil
}

func getEnvOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
