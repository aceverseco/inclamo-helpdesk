# Inclamo Helpdesk

An open-source, self-hosted helpdesk layer for e-commerce merchants, built
**around** [Chatwoot](https://github.com/chatwoot/chatwoot) Community Edition
without forking it.

Status: **development build**. [Behavior contracts](docs/behavior/README.md)
and tests ship with this source revision. See [Shopify setup](docs/connect-shopify.md)
and [workspace widgets and support](docs/workspace-widgets-and-support.md) for configuration.

## What it is

- Chatwoot CE at a pinned version, assembled with our backend overlay,
  dashboard components and versioned integration patches.
- A Shopify customer/order panel, store-aware templates and rules, workspace
  widgets and in-product support.
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

## Repository contents

The repository contains product source, tests, build tooling and documentation
for installing, operating and extending the product. Development plans,
internal reports and design prototypes are maintained separately.
Public builds and checks require no access to a private workspace.

Run `node scripts/check-repository-boundary.mjs` before publishing changes.
Generated review output belongs under ignored `build/`; test fixtures and
deliberately reviewed regression snapshots remain part of the test suite.

## Licence

AGPL-3.0, see `LICENSE`. Chatwoot itself is a separate project under its own
licence. "Chatwoot" is a trademark of Chatwoot Inc.; this project is not
affiliated with or endorsed by Chatwoot Inc.
