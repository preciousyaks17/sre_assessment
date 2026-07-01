// instrumentation/paymentservice/paymentSpans.js
//
// Custom spans, attributes, and metrics for paymentservice business logic.
// Import this in the gRPC handler (charge.js / server.js) and wrap the
// existing payment logic with these helpers.

const { trace, metrics, SpanStatusCode } = require('@opentelemetry/api');

const tracer = trace.getTracer('paymentservice');
const meter = metrics.getMeter('paymentservice');

// Custom metric: counter of payment attempts, tagged by outcome.
// Business-relevant signal: lets you build a "payment success rate" panel
// directly from metrics without scanning APM transaction data.
const paymentAttemptsCounter = meter.createCounter('payment.attempts.count', {
  description: 'Number of payment charge attempts, labeled by outcome',
  unit: '1',
});

/**
 * Custom span #1: 'validate-payment-method'
 * Wraps card validation logic (card type, expiry, Luhn check, etc).
 */
function tracedValidatePaymentMethod(creditCard, validateFn) {
  return tracer.startActiveSpan('validate-payment-method', (span) => {
    try {
      span.setAttribute('payment.card_type', creditCard.creditCardType || 'unknown');
      // last 4 digits only — never put full card numbers on a span
      const last4 = (creditCard.creditCardNumber || '').slice(-4);
      span.setAttribute('payment.card_last4', last4);

      const result = validateFn(creditCard);

      span.setAttribute('payment.validation.passed', true);
      span.end();
      return result;
    } catch (err) {
      span.recordException(err);
      span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
      span.setAttribute('payment.validation.passed', false);
      span.end();
      throw err;
    }
  });
}

/**
 * Custom span #2: 'process-charge'
 * Wraps the actual charge/transaction logic, records order context as span
 * attributes (requirement: business-context attributes like order.total),
 * and records the outcome metric.
 */
function tracedProcessCharge(amount, currency, userId, chargeFn) {
  return tracer.startActiveSpan('process-charge', (span) => {
    span.setAttribute('order.total', amount);
    span.setAttribute('order.currency', currency);
    if (userId) span.setAttribute('user.id', userId);

    try {
      const transactionId = chargeFn(amount, currency);

      span.setAttribute('payment.transaction_id', transactionId);
      span.addEvent('charge-succeeded', { transactionId });
      paymentAttemptsCounter.add(1, { outcome: 'success', currency });

      span.end();
      return transactionId;
    } catch (err) {
      // Requirement: error spans recorded with status code + exception details
      span.recordException(err);
      span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
      paymentAttemptsCounter.add(1, { outcome: 'failure', currency });

      span.end();
      throw err;
    }
  });
}

module.exports = { tracedValidatePaymentMethod, tracedProcessCharge };
