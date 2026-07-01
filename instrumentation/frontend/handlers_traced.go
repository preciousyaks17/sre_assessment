// instrumentation/frontend/handlers_traced.go
//
// Custom business-logic spans for the frontend service, plus the
// otelhttp middleware wiring for HTTP + gRPC client auto-instrumentation.
//
// This shows the pattern to apply to the existing frontend handlers.go —
// wrap the router with otelhttp, and wrap the two named business
// operations with manual spans per requirement 1.2.3/1.2.4.

package tracing

import (
	"context"
	"net/http"

	"go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	otelmetric "go.opentelemetry.io/otel/metric"
	"google.golang.org/grpc"
)

// WrapHandler applies otelhttp auto-instrumentation to the router.
// Use in main.go: http.Handle("/", tracing.WrapHandler(router))
func WrapHandler(handler http.Handler) http.Handler {
	return otelhttp.NewHandler(handler, "frontend-http")
}

// DialOptionsWithTracing returns the gRPC dial options needed so outbound
// calls to downstream services (productcatalog, cart, checkout, etc.)
// propagate W3C trace context (requirement 1.2.6: context propagation
// across gRPC boundaries).
func DialOptionsWithTracing() []grpc.DialOption {
	return []grpc.DialOption{
		grpc.WithUnaryInterceptor(otelgrpc.UnaryClientInterceptor()),
		grpc.WithStreamInterceptor(otelgrpc.StreamClientInterceptor()),
	}
}

// TracedValidateCartContents — custom span #1: "validate-cart-contents"
// Wraps cart validation before checkout (e.g. checking stock/quantity
// sanity) and carries business-context attributes.
func TracedValidateCartContents(ctx context.Context, userID string, items []CartItem) (bool, error) {
	ctx, span := Tracer.Start(ctx, "validate-cart-contents")
	defer span.End()

	span.SetAttributes(
		attribute.String("user.id", userID),
		attribute.Int("product.count", len(items)),
	)

	var total int32
	for _, item := range items {
		if item.Quantity <= 0 {
			span.SetStatus(codes.Error, "invalid item quantity")
			span.SetAttributes(attribute.String("cart.invalid_item", item.ProductID))
			return false, ErrInvalidCartItem
		}
		total += item.Quantity
	}

	span.SetAttributes(attribute.Int("cart.total_quantity", int(total)))
	return true, nil
}

// TracedCalculateShippingCost — custom span #2: "calculate-shipping-cost"
func TracedCalculateShippingCost(ctx context.Context, userID string, orderTotal float64, itemCount int) (float64, error) {
	ctx, span := Tracer.Start(ctx, "calculate-shipping-cost")
	defer span.End()

	span.SetAttributes(
		attribute.String("user.id", userID),
		attribute.Float64("order.total", orderTotal),
		attribute.Int("product.count", itemCount),
	)

	// Simplified flat-rate + per-item shipping logic, standing in for the
	// real shipping service call this would normally wrap.
	shipping := 4.99 + float64(itemCount)*0.5
	span.SetAttributes(attribute.Float64("shipping.cost", shipping))

	return shipping, nil
}

// RecordAddToCart increments the custom counter metric — call this from
// the add-to-cart HTTP handler.
func RecordAddToCart(ctx context.Context, productID string) {
	AddToCartCounter.Add(ctx, 1, otelmetric.WithAttributes(
		attribute.String("product.id", productID),
	))
}

// --- supporting types/errors referenced above ---

type CartItem struct {
	ProductID string
	Quantity  int32
}

var ErrInvalidCartItem = httpError{"invalid cart item quantity"}

type httpError struct{ msg string }

func (e httpError) Error() string { return e.msg }
