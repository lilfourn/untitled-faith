export const STRIPE_EVENT_TYPES = [
  'checkout.session.completed', 'checkout.session.async_payment_succeeded', 'checkout.session.expired',
  'payment_intent.succeeded', 'charge.updated', 'charge.refunded', 'charge.dispute.created',
  'charge.dispute.updated', 'charge.dispute.closed', 'charge.dispute.funds_withdrawn', 'charge.dispute.funds_reinstated',
  'refund.created', 'refund.updated', 'refund.failed',
] as const;
