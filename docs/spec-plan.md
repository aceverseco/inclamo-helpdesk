# Spec plan for v1

What the first product specification will contain. Decided items are marked
**decided**; the rest is open and will be settled before the spec is written.

## 1. Goal and boundaries — decided

An open-source, self-hosted helpdesk for e-commerce merchants, built around
Chatwoot Community Edition. The AI agent (chat and voice) is a separate,
closed service that plugs in through Chatwoot's agent-bot mechanism.

Explicit non-goals for v1:

- forking Chatwoot, or depending on Chatwoot Enterprise features;
- a CRM layer (separate project);
- a public Shopify App Store app for the helpdesk;
- telephony providers other than Telnyx;
- marketplaces reachable only through an email relay (Amazon, Walmart, Etsy,
  bol.com) until the relay vendors answer whether they can target Chatwoot;
- marketplaces whose messaging APIs are gated (TikTok Shop, Zalando);
- a voice channel inside Chatwoot (voice arrives as an API inbox).

## 2. Architecture — decided

Only documented extension points are used ("option A"): webhooks, agent bots,
dashboard apps, API inboxes, Application and Platform APIs. A backend overlay
(`custom/` directory, the GitLab-style `prepend_mod_with` hook that Chatwoot
ships) is allowed only by a separate, recorded decision per feature.

Components:

- **Chatwoot CE**, official `chatwoot/chatwoot:vX.Y.Z-ce` image, pinned.
- **bridge** — marketplace connectors as API inboxes, Shopify connection via a
  merchant-created custom app token, ingress classifier, and a reconciliation
  poller (Chatwoot account webhooks are delivered once, with no retry).
- **agent connector** — agent-bot flow (`pending` ⇄ `open`) to the AI service,
  and call-to-conversation delivery for voice.
- **dashboard app** — the one UI surface Chatwoot allows: an iframe tab in the
  conversation with the order panel, SLA state, and a macro helper.
- **MCP server** over the Chatwoot Application API and the bridges.
- **installer** — compose, secrets, backups, upgrade guide, outbound-traffic
  notes (Chatwoot's hub sync is on by default).

Licence of this layer: AGPL-3.0.

## 3. Channels for v1 — decided

- Native Chatwoot channels, configuration only: email, web widget, WhatsApp,
  Instagram, Facebook Messenger.
- Bridges built here, all API-based and testable without partner status:
  eBay, Mirakl, Kaufland, Allegro.
- Shopify through a merchant-created custom app (token pasted into settings).
- Voice through the AI service with Telnyx as the SIP provider, landing in
  Chatwoot as an API inbox conversation with recording, transcript and outcome.

Per bridge the spec defines: what is pulled in, what is sent back, customer
matching, reply-window rules, attachments, and failure handling.

## 4. In-ticket features

- Order panel with actions (refund, cancel, address change).
- Classification on ingress: type, language, sentiment, priority → labels and
  custom attributes.
- SLA: own timers and alerts, surfaced in the dashboard app.
- Macro helper with order variables, in the dashboard app.
- AI summary of the conversation.
- Left to Chatwoot as is: automation rules, macros, teams, help center, CSAT,
  reports.

## 5. AI agent behaviour

Agent-bot flow, handoff rules, rate caps, per-intent coverage (AI vs human),
guardrails (refund limits, approval mode), mandatory AI disclosure at first
contact, and the contract between the connector and the AI service.

## 6. MCP server

Tool list, authentication, scopes, intended clients.

## 7. Installation and tenancy

One Chatwoot instance per merchant for self-hosting; accounts provisioned via
the Platform API for a hosted deployment. Secrets, backups, upgrades.

## 8. Business model and metering — open

Unit definitions, where counters live, hosted-service fees, billing rails.

## 9. Compliance — open

EU hosting and LLM endpoints, non-removable AI disclosure, security
disclosure policy and SBOM, marketplace data-protection obligations.

## 10. Agent builder — open

Whether the agent-builder API is exposed through the helpdesk in v1.

## 11. Slices and first pilot — open

Each slice is one behaviour contract, one to two days of work.

## 12. Risks and open items

- Relay vendors' answers on Chatwoot support.
- Developer registrations at eBay and Mirakl.
- Chat-widget cookies under ePrivacy.
- Webhooks without retry on both sides of every integration.
