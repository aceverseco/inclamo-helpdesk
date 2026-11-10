## Why

The user approved the interactive shadcn-vue operator prototype and its Inclamo logo, navy/sky/orange palette, white canvas and clearer layout. The live Helpdesk still uses the earlier, deliberately restrained Twenty theme; the approved design now needs to become a coherent product interface rather than a separate demo.

## What Changes

- Carry the approved brand assets and semantic colours into shared native Vue controls, fields, menus, tables and dialogs across the staff application.
- Give the real sidebar, conversation list, message area, composer and customer/order panel the approved visual hierarchy while preserving Chatwoot handlers, permissions, stores and routes.
- Apply the same identity to contacts, reports, settings, authentication/onboarding and installation administration, with readable responsive layouts and preserved keyboard/RTL support.
- Use white surfaces for the default light appearance; retain a compatible navy dark appearance for existing explicit dark/automatic preferences.
- Keep merchant-configured widget, help-centre and survey branding independent of staff-workspace styling.
- Validate the assembled CE application on synthetic data and provide reviewable screenshots from the real product. The accepted prototype remains a design reference.

## Capabilities

### New Capabilities

- `inclamo-product-design`: A consistent branded staff experience with native Chatwoot interactions and maintained public-surface boundaries.

### Modified Capabilities

None. The earlier completed `twenty-inspired-dashboard` change remains a historical acceptance record; this change supersedes its visual design.

## Impact

Changes live in owned frontend styles/components and public assets under `shims/`, with small documented presentation seams in `patches/`. Test fixtures, synthetic E2E coverage and appearance documentation expand to cover the product surfaces. No API contract, database migration, external AI call, React runtime, commerce authorization or customer workflow is replaced. This applies to Inclamo Helpdesk, not the separate CRM/Builder repositories. Production deployment is not assumed; validation uses an isolated installation.
