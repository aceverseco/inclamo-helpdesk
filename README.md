# Inclamo Helpdesk

An open-source, self-hosted helpdesk layer for e-commerce merchants, built
**around** [Chatwoot](https://github.com/chatwoot/chatwoot) Community Edition
without forking it.

Status: **development build with integrated tests**. [Behavior contracts](docs/behavior/README.md)
ship with the source. Validate real-model quality and external email delivery
with the services configured for your installation.

## What it is

- Chatwoot CE v4.19.1, assembled with our backend overlay, dashboard components
  and small versioned patches at the integration points.
- A Shopify order panel with address/item changes, cancellation, refunds,
  replacements, new orders, payment links, discounts, tags and notes.
- Separate staff rights per operation, reviewed AI proposals and explicitly
  bounded autonomous actions, with an action journal and recovery behavior.
- A setup flow, order-aware templates/macros/rules and SLA timers.
- An AI agent for chat and voice provided as a separate service. The agent
  itself is not part of this repository.

## What it is not

- Our backend lives in `custom/`, our UI in `shims/`, and integration-point
  changes in `patches/`. `scripts/assemble.sh` applies them to the pinned
  upstream source; feature implementations stay in the overlay.
- Not dependent on Chatwoot Enterprise. Everything here runs on Community
  Edition, which is MIT-licensed. The `enterprise/` directory of Chatwoot is
  under a separate licence and is never used, patched or shipped.
- The open-source edition runs on the merchant's own infrastructure. A hosted
  edition by the authors uses the same code.

## Setup and authority

Administrators start at **Settings → Helpdesk setup**. Store/channel checks,
staff permissions and AI policy share the same settings used by the regular
account pages. Human-operated accounts can complete setup without connecting AI.

**Order actions** assigns each staff operation separately. **AI agent** configures
each AI operation as forbidden, proposed for staff approval (the default), or
autonomous with explicit limits. A cancellation with a refund needs both rights;
a discounted new order also needs discount permission. The connector contract,
identity checks and outcome handling are documented in [docs/ai-connector.md](docs/ai-connector.md).

Service builders start with [the integration handoff](docs/service-integration.md).
[Scaling guidance](docs/scaling.md) describes storage, worker and integration
constraints. See [release capabilities and limitations](docs/release-readiness.md)
before configuring a production installation.

## Build and verify

Build the assembled image with `sh scripts/build-image.sh <image-tag>`.
[CI](.github/workflows/ci.yml) runs backend/frontend regressions, schema and fixture
validation. [End-to-end tests](.github/workflows/e2e.yml) drive an isolated helpdesk
and a development Shopify store through `e2e/run.sh`; they create and remove
tagged test data. The included AI simulator verifies the integration contract,
not the behavior of a real language model.

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
