# Connecting an AI service

Implementation handoff, 2026-11-10. The wire contract is
[ai-connector.md](ai-connector.md); this guide explains the integration sequence
and its acceptance. The helpdesk side is implemented. The included simulator
is not a production AI service. Finished-call ingestion is still proposed in
[ai-connector-calls.md](ai-connector-calls.md).

## Ownership

| Helpdesk | AI service |
| --- | --- |
| Merchant channels, conversations, staff rights, AI action policy, Shopify connection, action journal | Merchant subscription, pairing codes, connection registry, durable event processing, model configuration and inference |
| Enforces the connected account and inbox on overlay endpoints | Holds one bot credential per connection; checks scope on every native Chatwoot call |
| Executes reviewed or explicitly authorized Shopify actions | Proposes actions, reads their outcome and explains that outcome to the customer |

Keep merchant credentials out of model prompts. The service's channel adapter
holds the helpdesk token; its model runtime receives only the bounded context
and scoped tools. Do not let the model select an arbitrary account, origin,
inbox, customer, or order. Resolve those from the authenticated connection.

## First connection

1. Deploy the checked helpdesk image with HTTPS, `FRONTEND_URL`, database,
   Redis, workers and persistent encryption keys. Connect a **development**
   Shopify store using [connect-shopify.md](connect-shopify.md). Create a web
   inbox and a regular staff user. Set per-operation staff rights under
   **Settings → Order actions**; leave AI operations at their default `propose`.
2. In the AI service, authenticate the merchant administrator. Bind an opaque,
   short-lived, single-use pairing token to that merchant, the intended
   helpdesk installation and its account. The account number alone is not a
   tenant identifier: independent installations both have account `1`.
3. Return `aic1.` plus base64url-encoded JSON containing `service_url` and
   `token`. The base64 is an encoding, not encryption. Do not log the code.
4. The administrator pastes it in **Settings → AI agent**, selects the intended
   inboxes and connects. Helpdesk calls `POST {service_url}/connections` as
   documented in contract §1.2. Implement this exact route; it is not present
   in an ordinary Chatwoot or AI deployment automatically.
5. Atomically consume the token and store the tenant binding, bot token and
   signing secret. Return `201` with `connection_id` and an HTTPS `webhook_url`
   in less than the helpdesk's 10-second registration timeout. Encrypt
   credentials at rest. Validate supplied origins and reject private addresses,
   unsafe redirects and cross-tenant rebinding before making outbound requests.
6. Implement authenticated, idempotent deletion of the connection. Helpdesk
   revokes the bot locally before its best-effort `DELETE`; it uses the former
   token. Keep a bounded revocation record so a repeated delete returns `2xx`.
   A new pairing produces a new connection generation and revokes old work.

Registration has no cross-service transaction. A timeout can leave an orphan
on the service even though the helpdesk removes the local bot. Store a pending
registration and reconcile it with a narrowly scoped authenticated helpdesk
read before processing work; expire unconfirmed registrations. Do not infer
success just because the service returned `201`, or treat every silent active
connection as an orphan. A retry with the same token must not bind a second
bot; after a failed setup, issue a fresh code and reconcile the old record.

## Processing a message

1. Select the connection by an opaque routing identifier, then verify the raw
   body HMAC, timestamp and account/inbox binding. Reject stale and excessively
   future timestamps. A public URL or a customer-supplied merchant ID is not
   authentication. Apply a bounded request body size before parsing.
2. Transactionally record the delivery and durable work reference before
   returning `200`. Deduplicate both delivery UUID and the shopper message ID
   within the connection generation. A duplicate already committed may get
   `200`; an uncommitted job may not. Avoid storing transcripts in queue rows:
   retain identifiers and fetch the authorized public history in the worker.
3. Only public, incoming `message_created` events in a pending, connected
   inbox create a turn. Outgoing messages, private staff notes and activity
   events are not model input. Process handover/status events as cancellation
   signals; do not filter them out of state handling.
4. Serialize turns per conversation across all worker replicas. Read current
   conversation status and connection generation before inference and again
   before any reply or tool side effect. If a staff member takes over, stop
   queued work. Native Chatwoot message creation has no documented atomic
   "only if still pending" condition: the remaining read/write race needs a
   guarded reply endpoint or equivalent server enforcement before claiming
   strict no-reply-after-takeover guarantees under concurrency.
5. Read bounded public history through the overlay. Treat attachments as
   untrusted URLs with byte/time/type limits. Send the model the shopper's
   message once; exclude that same ID from prior history. Preserve human-team
   authorship when adapting history to a model interface with fewer roles.
6. Record the turn outcome and an outbound intent before sending a reply.
   A timed-out `POST /messages` may already have succeeded: reconcile or hand
   over, rather than blindly sending it again. A local outbox alone does not
   make a remote message endpoint exactly-once.
7. If processing fails after `200`, the service owns recovery and handover.
   Persist and retry the handover with a deadline, alert if it cannot reach the
   helpdesk, and suppress late model/tool results. Merely returning `200` does
   not tell helpdesk that an answer was produced.

The current helpdesk retries only `429` and `500` (three attempts, three seconds
apart); a `503` or timeout opens the conversation immediately. Use the documented
statuses deliberately. See [scaling.md](scaling.md) for durable queue and overload
requirements; these are production integration requirements, not capabilities
of the in-memory test simulator.

## Order edits and cancellations

Use the governed endpoints under
`/api/v1/accounts/{account_id}/inclamo/ai/conversations/{display_id}`:

1. `GET /orders` for the matched customer, orders and current policy.
2. `POST /proposals` with the operation's exact parameters and a stable
   `request_id` (8–64 alphanumeric/hyphen characters). Persist the ID before
   the first request; never derive it from a new random value on each retry.
3. For `propose`, tell the customer the request awaits staff review. Staff
   approve in the helpdesk with their current operation rights.
4. For explicitly enabled autonomy, `POST /proposals/{id}/execute` still
   enforces verified identity, live policy, amount/fulfillment limits and
   human takeover. Read `GET /proposals/{id}` until a known outcome or the
   operation deadline. `busy` permits bounded retry of the same operation.
5. Report success only for `accepted`. `unknown`, `running` and `pending` do
   not establish completion. Preserve the action ID and reconcile unknown
   writes; a new proposal must not be used to repeat an uncertain refund.

Do not expose a second direct Shopify mutation tool that bypasses this
authority. Cancellation with refund needs both permissions. Policy limits
are per operation; daily monetary budgets need an additional service ledger.
Customer email/phone text is not identity verification. Current identity comes
from a correctly signed widget identity matched against Shopify, or explicit
administrator verification. Email/SMS/WhatsApp OTP is not implemented here.

## Acceptance with a real service

Use disposable accounts, synthetic customers and tagged orders in a development
store. Preserve before/after state, proposal/action IDs, outcome and cleanup.

| Gate | Evidence required |
| --- | --- |
| Pairing | Valid, expired, reused and wrong-tenant codes; timeouts before/after service commit; disconnect/reconnect with queued work |
| Message delivery | Invalid HMAC, replay, duplicates with different delivery IDs, out-of-order events, incoming attachment without text, private-note exclusion |
| Ownership | Human takeover before/during a turn, late tool/result after timeout, resolved conversation reopened by a shopper |
| Authority | Admin and each staff right; AI forbidden/propose/autonomous; unverified identity; changed customer; expired review; amount and fulfillment limits |
| Shopify writes | Address edit, item edit, cancellation, refund and refunding cancellation; independent Shopify Admin API readback plus shopper-facing state |
| Failure recovery | Receiver/worker restart after acknowledgement, duplicate execution, unknown remote outcome, revoked token, unavailable Shopify/model/helpdesk |
| Channels | Receive/reply from merchant mailbox; correct sender/thread; store transaction notices verified separately; no false claim that a Phone inbox enables voice |

The deterministic integration tests and real-service mode are described in
[ai-connector.md §8](ai-connector.md#8-testing-against-this-contract). Real-service
mode skips simulator-only controls: it is not a substitute for fault injection
or model-quality tests. The current acceptance scope and remaining gaps are in
[release-readiness.md](release-readiness.md).
