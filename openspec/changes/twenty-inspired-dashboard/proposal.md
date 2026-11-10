## Why

Inclamo's long-term product combines a helpdesk, Twenty CRM and the agent Builder. The helpdesk currently looks like stock Chatwoot while Builder already uses Twenty UI; establishing shared visual rules now will make the product more coherent before further operator features are added, while retaining Chatwoot CE's working interface and upgrade path.

## What Changes

- Give Inclamo Helpdesk one default visual theme based on Twenty's palette, typography, borders, spacing and control appearance, with light and dark modes using Chatwoot's existing appearance preference.
- Apply the foundation across the authenticated dashboard. Complete visual alignment on the operator workspace (navigation, conversation list, conversation and composer, customer/order sidebar and action dialogs) and the existing Inclamo order-permissions and preset-rules pages.
- Keep Chatwoot's Vue components and interaction model. Reuse its shared controls in our additions; introduce no React runtime, embedded second application or replacement helpdesk frontend.
- Keep the theme in owned assets and a small, documented set of build-time patches. Establish visual, interaction and asset-size checks on the pinned Chatwoot version.
- Update the release plan's instruction to keep Chatwoot's original appearance: native behavior and components remain the foundation, while the Inclamo dashboard follows the common visual standard.

Out of scope: changing screen layout or workflows to reproduce Twenty CRM, a full Vue port of Twenty UI, a selectable stock-Chatwoot theme, integration with third-party Chatwoot installations, voice integration, unified login/navigation across products, changes to CRM or Builder, widget/public help-centre/login/superadmin redesign, branding removal, and enterprise code.

## Capabilities

### New Capabilities

- `helpdesk-visual-theme`: the common appearance of the Inclamo dashboard, light/dark behavior, consistency of operator controls, isolation from other surfaces and preservation of existing interactions.

### Modified Capabilities

None. Order actions, reply variables, store rules, authentication and API contracts retain their existing requirements. Their screens participate in the new visual capability.

## Impact

- Dashboard assets and shared presentation: theme variables, typography, control styling and a dashboard-only stylesheet entry; a few existing Inclamo templates may adopt native shared controls.
- Packaging: owned assets under `shims/`, narrowly scoped patches under `patches/`, and the existing assembly/build process. No new runtime UI framework or server service.
- Validation: focused Playwright visual/interaction coverage, existing component and seam tests, dashboard production build and a before/after asset comparison using synthetic data.
- Documentation: a source/version and token mapping record, an inventory of presentation patches, and a focused update to `docs/spec-plan.md` during implementation.
- Initial integration target: the repository's pinned Chatwoot CE `v4.19.1`. Subsequent upstream upgrades re-run the same checks. This change does not require migrating data or deploying changes to other products.
