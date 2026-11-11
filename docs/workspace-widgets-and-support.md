# Workspace widgets and Inclamo support

This overlay targets the pinned Chatwoot Community Edition in `custom/CHATWOOT_VERSION`. The four initial widgets are Customer, Purchase statistics, Orders and Notifications. Support is a permanent header/profile action, independent of which widgets an agent keeps.

## Personal and administrator layouts

Open **Customize widgets** beside either surface or in the customer pane header. Add or remove cards, drag them or use Move up/Move down, and choose collapsed state. Save commits the preview; closing it discards unsaved layout edits. Conversation drafts are separate. Reset returns to the current account default.

Under **Settings → Workspace widgets**, an administrator can change the default, assign a layout to one current member or replace all members' layouts. The last operation explicitly confirms the affected membership count. Defaults preserve personal overrides. After an administrator replacement, members can personalize again. Concurrent changes require reloading the editor; an old editor cannot silently restore overwritten settings. Layouts belong to an account membership, not the user's global profile.

Removing Customer or Orders retains permitted access through Manage. Conversation labels remain available. Commerce cards and the composer share one account/conversation/contact provider; cached data expires after 60 seconds and mutations refresh it. Header Notifications uses Chatwoot's existing store and destination.

## Adding or retiring a widget

1. Add its stable ID and supported placement to `custom/config/workspace_widgets.json`.
2. Add a descriptor in `shims/app/javascript/dashboard/inclamo/widgets/registry.js`: localized title/description, lazy component loader, availability check and context requirements. Add strings to `inclamo/locale/en.json`.
3. Implement the owned Vue component and reuse an existing provider where possible. Availability never replaces server authorization. Failures stay within the widget boundary.
4. Add behavior tests, including account changes and stale asynchronous responses. Neither WidgetHost needs a new conditional branch.

Schema version 1 permits ordered `{id, collapsed}` entries in `conversation-sidebar` and `workspace-header`, with no arbitrary scripts, URLs or widget options. Duplicate IDs and unsupported placements are refused. New catalog items do not repin saved personal layouts. Retired IDs are skipped at runtime, identified in the editor and can be removed without discarding other choices. Keep stable IDs when upgrading; introduce a normalization/migration when changing the schema.

## Support deployment configuration

Install the same overlay on the customer installations and the central support Chatwoot. A stock third-party Chatwoot without the central intake is insufficient. No central API token is shipped to browsers or client installations.

| Setting | Client installations | Central support |
| --- | --- | --- |
| `FRONTEND_URL` | Required public HTTPS origin used for authenticated email links; keep stable for this identity | Central Chatwoot public HTTPS origin |
| `INCLAMO_SUPPORT_ENDPOINT` | Required release/deployment configuration: central HTTPS origin plus `/inclamo/support/v1`; no query, credentials or fragment | Only needed if central staff use the local reporting feature themselves |
| `INCLAMO_SUPPORT_CENTRAL` | Unset or `false` | `true` |
| `INCLAMO_SUPPORT_ACCOUNT_ID` | Unset | Dedicated support account ID |
| `INCLAMO_SUPPORT_INBOX_ID` | Unset | API inbox ID belonging to that account, with `lock_to_single_conversation` disabled |
| `SECRET_KEY_BASE` | Existing stable Rails secret; encrypts the local signing key | Existing stable Rails secret |
| Active Storage settings | Durable storage for approved local attachments/outbox retries | Durable storage for received attachments and native replies |
| SMTP settings | Existing application mail configuration | `MAILER_SENDER_EMAIL`, `SMTP_ADDRESS`, `SMTP_PORT`, authentication/domain/TLS settings required by the chosen mail service |

Keep Rails, Redis, PostgreSQL, Active Storage and Sidekiq configured as for Chatwoot. Include the normal `low` and `scheduled_jobs` queues and the patched schedule. Run the normal deployment migration command, which invokes the overlay migrations. There is no Enterprise or paid-plan requirement.

`INCLAMO_SUPPORT_TEST_NETWORK=true` permits HTTP only for the isolated fixture. Never enable it for a public deployment. Production endpoint, inbox and SMTP provisioning are separate deployment work; this change does not provision a public service or invent a production address. Ship the actual public endpoint in the release configuration before enabling the feature for customers. If it is absent/unreachable, approved requests remain in the local durable outbox with a visible delivery problem.

The central routes return 404 unless central intake is explicitly enabled. Configure the ingress to allow the authenticated versioned routes, cap request bodies (at least 14 MiB for a base64 file), and retain normal connection/rate protections. The application also bounds input before Rails parses it, validates content and rate-limits enrollment, uploads, source traffic and verification codes.

## Identity, hosting and authorization

The first explicit request creates an Ed25519 key pair locally. Its private key is encrypted with a purpose-specific key derived from `SECRET_KEY_BASE`. Enrollment proves possession; subsequent calls sign method, path, timestamp and body digest. Repeating enrollment with the same key recovers the same source. The source's registered link origin and endpoint are stable; changing them requires an intentional operational migration, not an ordinary settings edit.

Self-enrolled sources are always `self_hosted`, regardless of submitted claims. To trust a hosted installation, obtain its **public** source ID/fingerprint from that installation and verify it against the managed deployment:

```sh
bundle exec rake inclamo:support:identity
# On central support, after checking both public values:
bundle exec rake 'inclamo:support:trust_hosted[SOURCE_ID,FINGERPRINT]'
```

Hosted trust applies to new requests. Existing tickets retain their original source classification. Central tickets show the origin, source/account references, category, app version, approved technical context and actual author/admin actor. The corresponding custom attributes and labels support native assignment, filtering and triage.

Each request is bound to source, local account and immutable author ID. Identical emails across installations do not merge this boundary. Local access requires current account membership and either authorship or the current administrator role; another agent cannot read/reply/download by guessing a reference. An administrator follow-up records the administrator as sender. Removed members and revoked sources cannot continue sending. Never grant permissions by changing a support contact's email or merging native contacts.

Back up the installation identity, support records, attachment storage and the same `SECRET_KEY_BASE` together. A restore of the same installation keeps its identity. A distinct clone must not use the original support identity/history. Create it without the `inclamo_support_*` data, then run `inclamo:support:new_clone_identity` before enrollment. The task refuses to orphan existing local request history. For a compromised source, run centrally:

```sh
bundle exec rake 'inclamo:support:revoke_source[SOURCE_ID,FINGERPRINT]'
```

Revocation retains central conversations and disables recipients. A replacement installation enrolls a new identity. Historical references remain attached to their old source; key rotation is an explicit migration/incident procedure, not a silent remapping of history.

## Screenshot and attachment behavior

Capture runs only after **Take screenshot** is clicked, using the browser's native screen/tab/window chooser. It requires a secure context and browser support. The app cannot silently grant or remember capture permission. Unsupported or denied capture leaves the description intact; attach an image/PDF/plain text file or paste an image instead. Mobile uses this upload/text path.

Screen capture depends on browser and operating-system permissions. Safari
screen capture on macOS is not verified; image upload and text submission
remain the fallback when capture is unavailable or denied.

The editor is a lazy local Canvas component with crop, arrow, rectangle, undo and opaque black redaction; no screenshot SDK, DOM renderer or replay recorder is added. Capture stops its media tracks after taking one frame, including failures/timeouts. Only the final flattened PNG is uploaded after Send. Temporary original image/editor references are released when editing ends; draft attachments are cleared on submission, account/user change or component teardown. Closing a support dialog retains an unsent draft in that browser tab.

Defaults: at most five files per submission, 10 MiB each; PNG/JPEG/WebP, PDF and UTF-8 plain text only. Both servers inspect actual content, reject HTML/SVG, decode/re-encode images without metadata and bound dimensions. Uploading does not happen during capture/annotation/cancellation. Image dimensions are capped at 40 million input pixels and 16 million browser output pixels. Downloads pass through authenticated local and source-scoped central endpoints; thread JSON contains no reusable public blob URLs.

Unattached staging expires after 24 hours and is cleaned by the dispatcher. Attachments already associated with an outbox submission or central receipt are retained for delivery/recovery and follow the deployment's retention policy, backups and native conversation lifecycle. **No automatic permanent-ticket deletion interval is imposed by this release.** Operators must set/document the intended retention, archive and backup policy; do not expire blobs independently while retaining live receipt references.

## Delivery, replies and email

A submission UUID identifies both initial requests and follow-ups. The local transaction saves approved content and an outbox item before returning. Central receipt/message creation is atomic. Retrying a lost acknowledgement uses the same UUID, refuses changed content and repairs attachments on the same message. Queue outages recover through the minute dispatcher. Delivery state (queued/delivered/failed/incomplete attachments) is distinct from Chatwoot conversation status.

Clients synchronize public messages/statuses outbound, so a self-hosted instance needs no inbound callback. The visible support view refreshes about every ten seconds; one installation lease/cursor coalesces remote work, with background recovery each minute and backoff during outages. Opening a thread requests reconciliation. Notes and private attachments never enter the public cache; visibility is rechecked on retrieval and deleted/private messages emit tombstones. Author and administrator have independent read cursors. Support work does not block the customer composer.

Email is optional notification only: a generic notice and authenticated link containing an opaque request reference. It contains no reply body, screenshot, order data or login token. Hosted sources use verified local email. Self-hosted authors explicitly verify their address with a short-lived code; an installation's claim alone is insufficient. Verification/enrollment, opt-out and revocation are separate from thread access. Repeated public events/job retries share a unique notification record; SMTP failure retries independently of in-product replies. SMTP is not a transactional delivery system: a crash after the provider accepts mail and before the local acknowledgment can still cause a repeat, as with ordinary transactional mail.

## Validation and isolated setup

All fixture data is synthetic. The compose network is internal, has its own databases/storage/Redis, a mail sink that never forwards, and a fixed-destination fault proxy. It cannot reach production support. Use a unique compose project and a dedicated assembled checkout:

```sh
scripts/assemble.sh build/workspace-widgets-and-support/app
export HELPDESK_IMAGE=inclamo-helpdesk:workspace-support-test
docker build -f build/workspace-widgets-and-support/app/docker/Dockerfile \
  -t "$HELPDESK_IMAGE" build/workspace-widgets-and-support/app
e2e/workspace-support/prepare.sh
e2e/workspace-support/run.sh
```

`prepare.sh` seeds two client accounts and distinct author/other-agent/admin memberships, a second hosted installation, a central API inbox and centrally verifies the hosted source fingerprint. `run.sh` builds the Playwright runner and writes reports/screenshots under `workspace-support-output` (or `E2E_OUTPUT`). Fault injection covers unavailable upload/intake and a central commit followed by a lost acknowledgment. Mail verification reads the isolated sink.

Additional fixture probes run inside the browser image on the same internal network: `node workspace-support/workflow-probe.mjs` checks native replies/notes/marked orders and appearance, `xvfb-run -a node workspace-support/capture-probe.mjs` records the actual capture matrix, and `node workspace-support/performance-probe.mjs` compares warm conversation interactions against a prior image exposed as `baseline:3000`. Give that baseline the same synthetic database/configuration and a separate Redis database. Do not point a probe at a live customer deployment. `e2e/workspace-support/audit.rb`, run with the central Rails runner, checks native conversation/message counts and deduplication without printing keys or mail bodies.

Backend checks: `bundle exec rspec custom/spec`; frontend: `pnpm exec vitest run app/javascript/dashboard/inclamo/specs`, plus the native seams listed in CI. Ordinary assembly, production asset compilation, locale/fixture/GraphQL checks and behavior-contract coverage checks remain required.

## Rollout and rollback

Deploy/validate central intake and its API inbox/mail/storage first. Configure the release endpoint on clients, then release the client image and run migrations. Monitor durable pending submissions, next-attempt times, synchronization cursor age, source enrollment failures and independent mail deliveries; log errors omit signing keys and verification codes. Expand from synthetic verification to an internal pilot before general rollout.

An account can hide optional widgets with an empty layout without removing native Manage access. To halt intake, unset `INCLAMO_SUPPORT_CENTRAL` centrally; client outboxes remain queued. To roll back the UI/client implementation, deploy the previous application image while retaining the additive `inclamo_*` tables and storage. Resume on the compatible image to recover queued work. Do not drop support tables or regenerate secrets as a rollback shortcut.
