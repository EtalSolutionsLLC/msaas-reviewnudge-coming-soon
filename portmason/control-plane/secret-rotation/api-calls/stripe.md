# Stripe key and webhook rotation

Accepted secrets:

- `BILLING_API_KEY`
- runtime payment secret key
- runtime payment webhook signing secret

API key rotation status:

- Stripe documents API key management primarily through Dashboard/Workbench.
- Stripe recommends restricted API keys.
- No supported direct create/rotate API-key call is recorded here yet.

Dashboard path:

```text
Stripe Dashboard > API keys > Rotate key
```

Webhook replacement by creating a new endpoint:

```bash
curl -X POST "https://api.stripe.com/v1/webhook_endpoints" \
  -u "${STRIPE_ADMIN_SECRET_KEY}:" \
  -d "url=${APP_PAYMENTS_WEBHOOK_URL}" \
  -d "enabled_events[]=checkout.session.completed" \
  -d "enabled_events[]=checkout.session.expired" \
  -d "enabled_events[]=invoice.paid" \
  -d "enabled_events[]=invoice.payment_failed" \
  -d "enabled_events[]=customer.subscription.created" \
  -d "enabled_events[]=customer.subscription.updated" \
  -d "enabled_events[]=customer.subscription.deleted"
```

The webhook endpoint object returns `secret` only at creation.

Disable old webhook endpoint after smoke tests:

```bash
curl -X POST "https://api.stripe.com/v1/webhook_endpoints/${OLD_STRIPE_WEBHOOK_ENDPOINT_ID}" \
  -u "${STRIPE_ADMIN_SECRET_KEY}:" \
  -d "disabled=true"
```

Control-plane rule:

- Use dashboard/workbench rotation for payment API keys until a supported
  direct API-key adapter exists.
- Webhook endpoint replacement can be API-driven.
- Update environment only after the new endpoint/key is available.

Sources:

- https://docs.stripe.com/keys
- https://docs.stripe.com/api/webhook_endpoints/create
- https://docs.stripe.com/api/webhook_endpoints/object

