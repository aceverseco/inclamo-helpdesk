## Context

See `proposal.md` for motivation and the settled items (action set, native sidebar section, no reuse of Chatwoot's own Shopify integration, a role for order actions). Facts that shape the approach, checked against Chatwoot v4.19.1 and the Shopify Admin GraphQL API 2026-10:

- Chatwoot looks up `Custom::<Class>` modules through `prepend_mod_with` / `include_mod_with` when a `custom/` directory exists (`lib/chatwoot_app.rb`, `config/initializers/01_inject_enterprise_edition_module.rb`). `config/application.rb` adds only `enterprise/` to the load paths, so `custom/` needs an initializer of its own.
- The conversation sidebar is assembled in `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue` as a draggable list of named sections; the default list and order live in `app/javascript/dashboard/composables/useUISettings.js`. There is no hook for adding a section.
- Chatwoot CE has two roles: administrator and agent. Finer roles are a paid-edition feature and are not used.
- Chatwoot's own Shopify integration is invisible unless its account feature flag and the operator's OAuth client are set. It stays off.
- Shopify custom apps: since 1 January 2026 a merchant creates a custom app in the Dev Dashboard, not in the store's admin. Such an app has no static token: the server exchanges the client ID and secret for an access token that lives 24 hours (client credentials grant), which works only when the app and the store belong to the same Shopify organisation. Legacy admin-created apps keep their static `shpat_` tokens.
- Shopify protected customer data: a merchant's own custom app gets customers' names, emails, phones and addresses only on the Grow plan or higher; on Basic the API refuses them (Shopify Help Center, "Custom apps"). To be confirmed on a live Basic store.
- Shopify gives an app the last 60 days of orders unless it holds `read_all_orders`; whether a Dev Dashboard custom app can take that scope without review is to be confirmed.
- Shopify: order editing exists (`orderEditBegin` … `orderEditCommit`, scope `write_order_edits`, unfulfilled items only, store-currency orders only).
- Shopify: `orderCancel` needs `write_orders`, takes reason, restock, refund method and notify, and is asynchronous (returns a job). `refundCreate` needs `write_orders` and requires an idempotency key from API version 2026-04. `orderUpdate` with `shippingAddress` needs `write_orders`. `draftOrderCreateFromOrder(orderId)` needs `write_draft_orders` and `write_orders`; `draftOrderUpdate`, `draftOrderComplete` and `draftOrderDelete` need `write_draft_orders`. `draftOrderComplete` turns the draft into a regular order and commits inventory.

## Goals / Non-Goals

**Goals:**
- The whole backend of this change in `custom/`, with no edit to a Chatwoot core Ruby file.
- One seam in the dashboard, generic enough to carry later sections, proposed upstream.
- A store connection that the hosted edition can later satisfy with OAuth without touching the panel.
- No order or customer data at rest in the helpdesk beyond the conversation attributes named in the spec.

**Non-Goals:**
- More than one store per account.
- Shopify webhooks; the panel reads on demand.
- A settings page; the connection form lives in the panel's "not connected" state until the settings slice.
- Order editing (adding or removing line items of an existing order): possible in Shopify, planned for release 0.2, not this change.
- Creating a new order from scratch (catalogue search, custom lines, invoice): planned for release 0.2. This change has only the duplicate as a free replacement.
- Roles finer than one order-actions role (per action, per amount).
- Amount limits for human agents. Limits belong to the AI slice.
- Returns, exchanges, subscriptions, gift cards, store credit.

## Decisions

**D1. Backend as a `custom/` overlay with its own load path, routes and migrations.** An initializer adds `custom/app/**` and `custom/lib` to the autoload and eager-load paths, draws `custom/config/routes.rb`, and appends `custom/db/migrate` to the migration paths. Our tables are prefixed `inclamo_`. Alternative: put migrations and routes into Chatwoot's own `db/migrate` and `config/routes.rb` as its paid editions do; rejected because every such file is a merge conflict waiting for the next upstream release.

**D2. Our own API namespace.** `/api/v1/accounts/:account_id/inclamo/shopify/...`: `connection` (show, create, recheck, destroy), `customers` (match, choose), `orders` (list, show, lookup by number), `orders/:id/cancel|refund|address|replacement`, `conversations/:id/order` (mark, clear), `order_roles` (list, give, take). Authentication and account scoping reuse Chatwoot's base controllers by inheritance, not by editing them.

**D3. Connection record behind an interface.** Table `inclamo_shopify_connections`: account (unique), shop domain, auth kind (`client_credentials`, `legacy_token`; `oauth` later for the hosted edition), encrypted client secret and access token, token expiry, scopes, API version, store name, customer-data mode (`full`, `limited`), status (`working`, `broken`), last checked at. The panel and the actions talk to a `StoreConnection` object that hands out a valid token and renews it five minutes before expiry; nothing else sees the credentials. Encryption uses Rails Active Record encryption; Chatwoot treats those keys as optional, so connecting is refused when they are absent (spec: "The token is a secret").

**D4. Verification on connect.** For `client_credentials`, first the token exchange; then one GraphQL call for `shop { name myshopifyDomain plan }` and `currentAppInstallation { accessScopes { handle } }`, and one probe query for a customer field to learn whether personal data is given (`full`) or refused (`limited`). The same sequence serves "check again".

**D5. Shopify Admin GraphQL, version pinned.** Version `2026-10` in one constant; bumping it is part of the upstream-release routine. Throttled answers are retried with the wait Shopify states, within the request's time limit. No REST.

**D6. Read on demand, 60-second cache, nothing at rest.** Orders are fetched by our backend per panel load and cached in Redis for 60 s keyed by account and customer. The only persisted order data are the conversation attributes of the marked order (number, statuses, first tracking number and link, admin link). The chosen customer for an ambiguous match is kept as a contact attribute holding the Shopify customer id.

**D7. Idempotent actions.** The dialog creates an action id when it opens; the backend writes the action record with that id before calling Shopify and passes it as the idempotency key of `refundCreate`. A repeated request with the same id returns the recorded outcome. `orderCancel` is polled for up to 10 s; after that the order is shown as "cancelling" and re-read on the next load. An action whose answer was lost is recorded as `unknown` and resolved by reading the order.

**D8. Record of actions.** Table `inclamo_order_actions`: account, conversation, agent, order id and number, action, parameters without personal data (amounts, reason, flags; never the address), outcome (`accepted`, `refused`, `unknown`), Shopify's message, timestamps. The private note is created through Chatwoot's own message builder as the acting agent, so it appears in the timeline like any note. Chatwoot CE has no audit log; this table is ours.

**D9. One dashboard seam: a registry of sidebar sections.** `ContactPanel.vue` gets one extra branch that renders any section found in a registry, inside the same accordion wrapper as the built-in sections; `useUISettings.js` appends the registry's names to the default order. Our components, store module, API client and locale strings live in a directory of our own and are reached only through the registry file. Two core files touched, both by a few lines. Alternative: a Dashboard App iframe; rejected for this feature (orders and messages must be visible together).

**D10. The connection form lives in the panel for now.** Not connected: administrators see "Connect Shopify" in the section, which opens a dialog with the domain, the credentials (client ID and secret, or a legacy token) and the list of scopes to grant. This avoids a second seam (settings navigation) in this slice.

**D11. Own image.** Dockerfile: official `chatwoot/chatwoot:<tag>-ce` source at the same tag, plus `custom/`, plus the two seam patches, assets built. CI fails the build when a seam patch does not apply.

**D12. Three layers of tests, the top one end to end on a live store.**
- Backend specs run against recorded Shopify answers; every GraphQL document is validated against the published schema of the pinned version. They run on every push.
- End-to-end tests (Playwright, in `e2e/`) drive the real dashboard of our image, started by compose with Postgres and Redis and a seeded account (one administrator, one agent with the order-actions role, one without), connected to a dedicated development store. Every scenario of both specs has an end-to-end test named after it; a scenario without one fails a coverage check in CI.
- Store state for each test is created through the Admin API by a separate seeding app with wider scopes (customers, products, orders), tagged per run and removed afterwards, so the app the helpdesk connects with keeps exactly the scopes the merchant guide asks for.
- Failure scenarios (store does not answer, throttling, lost answer, authentication error) are produced by a proxy between the helpdesk and Shopify that the test controls; the Shopify base URL of the backend is configurable for this only in the test environment.
- The limited mode is exercised with a third app that has no access to protected customer data, if Shopify allows such an app on a development store; otherwise by the proxy stripping those fields. A real Basic-plan store stays a manual check.
- End-to-end tests run on the main branch, before every release and on demand; credentials of the development store live in CI secrets and are never printed.

**D13. The order-actions role is our own record.** Table `inclamo_order_roles`: account, user, given by, given at; one row means the agent holds the role. Administrators need no row. Every action endpoint checks it on the server before anything else; the panel reads it together with the scopes to decide what to show. Chatwoot's `custom_roles` tables and `custom_role_id` column belong to its paid edition and are not read or written. Alternative: a conversation or agent custom attribute; rejected because any agent could edit it through Chatwoot's API. The list of agents with a switch per agent lives in the panel's administrator menu, next to the connection (same reasoning as D10: no second seam in this slice).

**D14. The free replacement goes through a draft order.** Three steps under one action id: `draftOrderCreateFromOrder` (the store copies items, customer and addresses itself, so the address never passes through us), `draftOrderUpdate` (the items the agent kept, a 100 % order discount, a free shipping line, a tag and a note naming the original order), `draftOrderComplete`. The draft id is written to the action record after step one, so a repeated request continues from the recorded step instead of creating a second draft. When step two or three is refused, the draft is deleted; when the deletion fails, the message names the draft with a link. Alternative: `draftOrderCreate` with lines built by us; rejected because it needs the address and customer on our side and breaks in the limited mode.

## Risks / Trade-offs

- [Upstream rewrites `ContactPanel.vue`] → the seam is two small patches; CI catches a failed apply at build time; the registry is proposed upstream so the patch can disappear.
- [Upstream removes or renames a hook our overlay relies on] → this slice prepends nothing in core classes (own controllers, own tables, Chatwoot's public builders), so its exposure is the base controller and the message builder interfaces; covered by tests on every upstream tag.
- [A wrong refund is money gone] → confirmation with amount and destination, refusal above the refundable, idempotency, action record. No amount limit for humans in this slice is a deliberate non-goal.
- [Token leak] → encrypted at rest, never returned, never logged; connection refused without encryption keys.
- [Shopify throttling on busy accounts] → 60-second cache, cost-aware queries (ten orders per page), stated wait honoured.
- [Most small stores are on the Basic plan, where a merchant's own custom app gets no customer data] → the limited mode keeps lookup by order number, statuses, tracking, cancel and refund working; the full panel on Basic needs another way of connecting (a custom-distribution app or the public app of the hosted edition), which is a product decision outside this slice.
- [A replacement takes stock and creates a real order] → confirmation states it; the role gates who can do it; the order is tagged and names the original, so the merchant can find every replacement.
- [A half-done replacement leaves a draft behind] → draft id recorded after the first step, delete on failure, named in the message when deletion fails.
- [End-to-end tests depend on a live development store and Shopify's limits] → one dedicated store, data tagged per run and cleaned up, tests serial against the store, backend specs on recorded answers keep every push fast.
- [Something only a real Basic-plan store shows] → one manual check before release, recorded in the design.
- [Personal data] → address and customer details pass through memory and a 60-second cache only; attributes and records are free of them by spec.

## Migration Plan

New tables and a new image; nothing existing changes. Rollback: run the official image, the `inclamo_` tables stay unused. Removing `custom/` returns a stock Chatwoot.

## Open Questions

None that block the task list. To be confirmed on a live store, each with a task:

1. Customer data on a real Basic-plan store (limited mode), and whether `draftOrderCreateFromOrder` works there. Manual check; everything else below is settled by the end-to-end tests.
2. Whether a Dev Dashboard custom app can take `read_all_orders` without review.
3. Completion of a zero-total draft order and which notification, if any, the store sends for it.
