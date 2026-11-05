## Why

An agent answering a Shopify merchant's ticket today has to open the Shopify admin in a second tab to see the order and act on it. Chatwoot's own Shopify integration (CE, 4.19.1) lists a contact's orders with totals and statuses only: no items, no tracking, no address, no actions, and it requires the operator to register a Shopify app and go through OAuth. The e-commerce helpdesks this project is measured against (sidebar with order details and refund / cancel / edit actions, order variables in macros, AI actions on orders) all start from this panel. It is the first slice of the Shopify helpdesk and the surface every later slice (AI approvals, macros, SLA) hangs on.

## What Changes

- A **Shopify connection** per Chatwoot account that takes the credentials of a custom app the merchant created for their own store (client ID and secret of a Dev Dashboard app, or the admin token of an app created before 2026; no OAuth, no Partner app on the operator's side), verifies them, renews short-lived tokens itself, records the shop domain and the granted scopes, and exposes which actions are available with those scopes. A store whose plan hides customer data from custom apps is connected in a limited mode: lookup by order number only.
- An **order panel** in the conversation sidebar that shows, for the conversation's contact: the matched Shopify customer, their recent orders with items, prices, payment and fulfillment status, shipping address and tracking, and a link to the order in the admin.
- **Order actions** from the panel: cancel the order, refund (full or partial), change the shipping address, and duplicate an order as a free replacement (a reship). Every action asks for confirmation and leaves a private note in the conversation naming the agent and the result.
- **A role for order actions**: administrators can always act; an agent can act only after an administrator gave them the order-actions role. Chatwoot CE has two fixed roles, so this role is ours.
- **Order context on the conversation**: the order number, status and tracking of the order the conversation is about, written as conversation custom attributes so that macros, automation rules, labels and the AI connector can use them.
- Customer matching by the contact's email, then phone; when no customer matches, the panel offers lookup by order number.

Not in this change: the AI agent's use of the panel (approval cards), SLA, marketplaces, the public Shopify app. Planned for release 0.2: editing the items of an existing order, and creating a new order from scratch with catalogue search and an invoice.

## Capabilities

### New Capabilities
- `shopify-connection`: how a merchant connects a store with custom app credentials, what is verified and stored, the limited mode, how scopes gate actions, how the connection is removed.
- `conversation-order-panel`: what the agent sees for the contact's orders, how the customer is matched, which actions exist, who may perform them, confirmation and audit, failure handling, and the order attributes written on the conversation.

### Modified Capabilities
- none (first change in this repository).

## Settled items

1. ~~Action set for v1~~ settled: cancel, refund, address change, and duplicating an order as a free replacement. Order editing and order creation from scratch move to release 0.2.
2. ~~Where the panel lives~~ settled: a native section in the conversation sidebar, next to Chatwoot's own sections, via one seam in the sidebar plus our components, shipped in our image.
3. ~~Reuse of Chatwoot's own Shopify integration~~ settled: not reused. Our own connection record and our own panel; Chatwoot's integration stays switched off (it is invisible without its feature flag and the operator's OAuth client).
4. ~~Who may act~~ settled: administrators always; agents only with the order-actions role given by an administrator; one role for all actions; a new agent does not have it.

## Impact

- New code: a backend module for the Shopify connection and order read/write (Admin GraphQL API, custom app credentials), a sidebar UI, conversation custom attributes, and private-note audit entries.
- Chatwoot: one seam in the conversation sidebar (the file that lists the sidebar sections), recorded in the design and proposed upstream; no change to Chatwoot's data model beyond custom attributes.
- Shopify scopes required by the merchant's custom app: `read_customers`, `read_orders` at minimum; `write_orders` for cancel / refund / address; `write_orders` together with `write_draft_orders` and `read_products` for the replacement order. The panel must degrade cleanly when a scope is missing.
- Security: the credentials are a secret stored encrypted at rest; actions are limited to administrators and to agents holding the order-actions role; every action is logged.
- Tests: backend specs on recorded answers, and end-to-end tests that drive the dashboard against a dedicated development store for every scenario of the specs.
- Depends on: a dedicated development store with the custom apps the tests use, and a development instance of the helpdesk.
