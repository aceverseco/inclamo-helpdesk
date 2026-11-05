# Inclamo Helpdesk

An open-source, self-hosted helpdesk layer for e-commerce merchants, built
**around** [Chatwoot](https://github.com/chatwoot/chatwoot) Community Edition
without forking it.

Status: **planning**. No code yet. The plan for the first release is in
`docs/spec-plan.md`; the first change is being specified in `openspec/`.

## What it is

- Chatwoot CE as the inbox, unchanged: the official `-ce` image, pinned by tag.
- Our services next to it: marketplace bridges, a Shopify connection, a
  conversation sidebar app, a classifier on ingress, an MCP server, and an
  installer with an upgrade path.
- An AI agent for chat and voice provided as a separate service. The agent
  itself is not part of this repository.

## What it is not

- Not a fork of Chatwoot. Our backend uses the `custom/` overlay hook that
  Chatwoot ships for exactly this purpose, our UI lives in our own components,
  and everything else goes through Chatwoot's APIs and webhooks. Chatwoot's
  core files are not edited for features.
- Not dependent on Chatwoot Enterprise. Everything here runs on Community
  Edition, which is MIT-licensed. The `enterprise/` directory of Chatwoot is
  under a separate licence and is never used, patched or shipped.
- The open-source edition runs on the merchant's own infrastructure. A hosted
  edition by the authors uses the same code.

## Licence

AGPL-3.0, see `LICENSE`. Chatwoot itself is a separate project under its own
licence. "Chatwoot" is a trademark of Chatwoot Inc.; this project is not
affiliated with or endorsed by Chatwoot Inc.
