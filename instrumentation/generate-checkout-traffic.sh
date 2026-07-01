#!/usr/bin/env bash
#
# instrumentation/generate-checkout-traffic.sh
#
# Section 1.3 — generates a full browse -> add-to-cart -> checkout user
# journey against the Online Boutique frontend, to produce a distributed
# trace spanning frontend -> productcatalogservice -> cartservice ->
# checkoutservice -> paymentservice (-> shippingservice, currencyservice,
# emailservice depending on checkout flow implementation).
#
# Usage:
#   FRONTEND_URL=http://<frontend-external-ip> ./generate-checkout-traffic.sh
#
# After running, go to Kibana -> Observability -> APM -> Traces, find the
# most recent trace for service "frontend", and screenshot the waterfall
# (requirement 1.3.2) and Service Map (requirement 1.3.3).

set -euo pipefail

FRONTEND_URL="${FRONTEND_URL:-http://localhost:8080}"
COOKIE_JAR="$(mktemp)"
trap 'rm -f "$COOKIE_JAR"' EXIT

echo "==> Using frontend at: $FRONTEND_URL"
echo "==> Cookie jar: $COOKIE_JAR"

echo "==> Step 1: Load homepage (establishes session, exercises page-load / product list span)"
curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -H "traceparent: 00-$(openssl rand -hex 16)-$(openssl rand -hex 8)-01" \
  "$FRONTEND_URL/" -o /dev/null -w "  status: %{http_code}, time: %{time_total}s\n"

echo "==> Step 2: View a product (exercises productcatalogservice GetProduct span)"
PRODUCT_ID="OLJCESPC7Z" # sunglasses, a known seed product ID in Online Boutique
curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  "$FRONTEND_URL/product/$PRODUCT_ID" -o /dev/null -w "  status: %{http_code}, time: %{time_total}s\n"

echo "==> Step 3: Add product to cart (exercises cartservice AddItem span + custom add-to-cart metric)"
curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -X POST \
  --data "product_id=$PRODUCT_ID&quantity=1" \
  "$FRONTEND_URL/cart" -o /dev/null -w "  status: %{http_code}, time: %{time_total}s\n"

echo "==> Step 4: View cart (exercises cartservice GetCart span)"
curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  "$FRONTEND_URL/cart" -o /dev/null -w "  status: %{http_code}, time: %{time_total}s\n"

echo "==> Step 5: Checkout (exercises checkoutservice -> paymentservice, shippingservice, currencyservice, emailservice)"
curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -X POST \
  --data "email=test%40example.com&street_address=123+Test+St&zip_code=94043&city=Mountain+View&state=CA&country=US&credit_card_number=4432801561520454&credit_card_expiration_month=1&credit_card_expiration_year=2028&credit_card_cvv=672" \
  "$FRONTEND_URL/cart/checkout" -o /dev/null -w "  status: %{http_code}, time: %{time_total}s\n"

echo "==> Done. Full journey submitted."
echo "==> Now check Kibana -> Observability -> APM -> Traces (filter service.name: frontend, recent)"
echo "==> Then check Kibana -> Observability -> APM -> Service Map for the call graph."
echo ""
echo "==> Bonus: generate an ERROR trace for requirement 1.3.5 (invalid card -> payment failure)"
curl -sS -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -X POST \
  --data "email=test%40example.com&street_address=123+Test+St&zip_code=94043&city=Mountain+View&state=CA&country=US&credit_card_number=0000000000000000&credit_card_expiration_month=1&credit_card_expiration_year=2020&credit_card_cvv=000" \
  "$FRONTEND_URL/cart/checkout" -o /dev/null -w "  status: %{http_code} (expected non-2xx), time: %{time_total}s\n" || true

echo "==> Look for this failed transaction in APM -> Traces, open its Error tab for the stack trace (requirement 1.3.5)."
