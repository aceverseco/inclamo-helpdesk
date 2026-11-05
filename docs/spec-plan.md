# Release 1: a Shopify helpdesk

What the first release is, how it is packaged, what is settled and what is
still open. Each slice below becomes its own OpenSpec change under
`openspec/changes/`; decisions about mechanics (where code lives, which
Chatwoot seam a feature takes) are made per slice, in that slice's design.

## 1. Goal

A helpdesk for a Shopify merchant that installs in minutes, looks like one
product, and reaches parity with the established e-commerce helpdesks on the
agent's daily work: order panel with actions, macros with order variables,
preset rules, assignment and SLA, and an AI agent that answers first and hands
over. The AI agent is a separate, subscription service; the helpdesk is its
front door.

The open-source edition and the hosted edition are the same code. They differ
only in who hosts it and how the store is connected.

Non-goals for release 1: marketplaces, CRM, a public Shopify App Store app,
telephony providers other than Telnyx, Chatwoot Enterprise features.

## 2. How it is built

- Chatwoot Community Edition, official `-ce` image, pinned by tag, as the base.
- Our backend lives in Chatwoot's `custom/` overlay, the same hook mechanism
  Chatwoot's own editions use (`prepend_mod_with` and friends). Chatwoot's core
  files are not edited for features.
- Our UI lives in our own components. Where Chatwoot's dashboard has no hook
  for a surface, a slice may take a small seam in the core UI; each seam is
  recorded in that slice's design and proposed upstream.
- We ship our own image: the official CE tag plus `custom/` plus built assets.
- Everything else (Shopify access, classifier, AI connector, MCP server,
  installer) runs next to Chatwoot as our services and talks to it over its
  APIs and webhooks.
- The `enterprise/` directory of Chatwoot is never used, patched or shipped.
  Features that Chatwoot sells in its paid editions (SLA, fine-grained roles,
  audit log, branding removal, AI assistant) are written by us, in our code,
  when a slice needs them.

## 3. What the merchant gets

1. **Install.** One compose file, our image. First login opens a setup wizard:
   store name, connect Shopify, connect channels, enable AI.
2. **Store connection.** Open-source edition: the merchant pastes the
   credentials of their own custom app; we verify them and show which actions
   the granted scopes allow. Hosted
   edition: OAuth from our Shopify app. One connection abstraction, two entry
   paths.
3. **Channels.** Website widget, email, WhatsApp, Instagram, Facebook
   Messenger: Chatwoot's own channels, configured, not rebuilt.
4. **Inbox.** One conversation list. With the AI subscription, every
   conversation is labelled on arrival by our classifier: type (where is my
   order, return, address, damage, …), language, priority. Without it, the
   inbox is Chatwoot's, with the merchant's own rules and labels.
5. **Conversation.** Messages on the left; on the right the customer, their
   orders with items, payment and fulfilment status, tracking, address, and
   actions (the exact action set is decided in the order-panel slice). Macros
   with order variables. "Summarise" and "Draft reply" in the header.
6. **Rules and team.** Preset automation rules switched on with one toggle;
   teams and assignment; SLA timer on the conversation; reports.
7. **AI.** One settings page: what the agent does, how usage is counted, how
   to enable it. Enabled, the agent answers first in the widget and email,
   hands over by rules, asks for approval above the merchant's limits, and the
   usage counter is visible on that page.
8. **Voice.** A phone number through Telnyx; calls land as conversations on
   the same customer. Subscription only.

## 4. Packaging rules

- Outside, it is our product: name, logo, colours, widget without third-party
  branding (branding removal is our code, not a Chatwoot edition flag).
- Inside, it stays Chatwoot: our sections go where an agent expects them, in
  Chatwoot's own look. The closer to native, the cheaper every upstream
  release.
- Without a subscription the AI does nothing at all: no classifier, no
  summaries, no drafts, no replies. It stays visible as a door: a wizard step,
  greyed "Summarise" and "Draft reply" buttons, and the AI settings page that
  explains what it does and how to enable it.
- Settings in one place: store connection, action permissions by role, AI
  limits, subscription and usage.

## 5. Provisions

For the hosted edition:
- everything configurable per Chatwoot account, never per instance;
- store connection behind one interface (custom app credentials today, OAuth later);
- billing and metering outside Chatwoot, in the AI service; Chatwoot only
  emits events;
- setup wizard and per-account feature flags, so plans can gate features;
- EU hosting and EU LLM endpoints.

For selling the AI:
- the helpdesk ↔ AI connector contract is its own slice: events, actions,
  approvals, counters; it is the boundary between open and closed code;
- every AI-driven feature, the ingress classifier included, is part of the
  subscription; the open-source edition contains the surfaces and the
  connector, not the intelligence.

For the open-source edition:
- **No external code for now.** Our code is AGPL-3.0 and we also run it as a
  hosted service with private changes, which is possible only while we hold
  the copyright. External pull requests are not accepted; the question of a
  contributor agreement is deferred until that changes. See `CONTRIBUTING.md`.
- **Paid-edition features are our work.** Anything Chatwoot sells in its paid
  editions and the product needs is written by us; each slice names what it
  builds instead of assuming Chatwoot has it.
- **Upstream releases are part of the product.** Chatwoot releases every few
  weeks, security fixes included. For each release: merge the tag, run the
  tests, build the image, publish a changelog and an upgrade note. A merchant
  on the open-source edition must never be left behind on a vulnerable core.

## 6. Slices

One behaviour contract per slice, one to two days of work each. Order is a
proposal and will move as the first slices land.

1. `shopify-order-panel` (started): store connection by custom app credentials, the
   order panel in the conversation, order actions, order attributes on the
   conversation.
2. Ingress classifier (subscription): labels and attributes on every new
   conversation through the AI connector.
3. Macros with order variables and preset automation rules.
4. SLA timers and alerts on the conversation.
5. AI connector contract: agent-bot flow, handover, approvals, counters.
6. AI surfaces: settings page, header buttons, usage counter.
7. Setup wizard and branding.
8. Voice calls as conversations (Telnyx through the AI service).
9. Installer, image build and the upstream-release routine.
10. MCP server over the helpdesk and the store.

## 7. Open items

- Unit definitions for metering (ticket, minute) and the billing rails.
- Action set and placement of the order panel (settled in slice 1).
- Hosted edition fees and onboarding.
- Whether the agent-builder is exposed through the helpdesk.
