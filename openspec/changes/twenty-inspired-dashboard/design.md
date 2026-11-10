## Context

See `proposal.md` for the product motivation and scope. This design is needed because presentation changes cross shared components, asset entry points and the upstream assembly process.

Inspected on 2026-11-09:

- `custom/CHATWOOT_VERSION` pins CE `v4.19.1`. `scripts/assemble.sh` applies the patches and then copies `custom/` and `shims/`; a patch that does not apply stops assembly. Existing feature work and uncommitted changes must be retained.
- The dashboard uses Vue 3, Tailwind 3 and Vite. Its palette is largely centralized in `dashboard/assets/scss/_next-colors.scss` and `theme/colors.js`; typography and base fields are defined in `_typography.scss` and `_base.scss`. Control dimensions and some radii are still literals inside components, including `components-next/button/Button.vue` and `dialog/Dialog.vue`.
- `dashboard/App.vue` loads the dashboard styles but also participates in routes outside the authenticated workspace. `routes/dashboard/Dashboard.vue` is the account-workspace container. Dialogs teleport to `body`; scoping only to a sidebar or workspace div would miss them. `helper/themeHelper.js` already owns the `body.dark` class and the stored light/dark/auto preference.
- Our own UI has ten Vue components, approximately 1,060 lines. It reuses native dialogs/settings layouts and also contains directly styled HTML controls. Order state is shared with reply variables, so these components cannot be replaced without considering their behavior.
- Builder in the sibling `inclamo-app/voicebuilder/ui` already consumes Twenty UI `1.0.0-alpha.2` and currently uses a dark theme. The Sales Assistant panel uses `2.41.0`. Their versions differ; installing the same package name would not by itself produce one visual standard.
- Existing E2E tests use a live development store and suppress screenshots in CI because they can contain credentials. Theme screenshots must use a separate synthetic-data execution path and must not change those protections.

## Goals / Non-Goals

**Goals:** Keep the frontend on Vue; make appearance follow a small set of owned semantic values; keep the changes reproducible against the pinned CE source; preserve native behavior, accessibility and user font-size preferences; and make visual changes assessable alongside their maintenance cost.

**Non-Goals:** See the proposal for product exclusions. Architecturally, this change does not create a second component framework, a generic theming platform, a complete Twenty-to-Vue component port, a shared package spanning multiple repositories, or automatic synchronization with every Twenty release.

## Decisions

### D1. Use Twenty as the visual reference and retain native Vue controls

Use the existing Vue implementations for controls and their interaction/accessibility behavior. Normalize our directly styled controls onto existing native components where that reduces duplication without changing events, disabled states or labels. Where no suitable native component exists, style the existing element with the common values; do not build an abstraction solely to wrap one element.

React components embedded in Vue would add runtime and lifecycle coordination without a functional need. A new frontend would duplicate the inbox/editor/state work. Porting all of Twenty UI would create another library to maintain. None is justified by this presentation change.

### D2. Freeze a small visual reference and keep the mapping local

Create `docs/dashboard-theme.md` during implementation. Record one exact Twenty UI release or source commit, its source URL, attribution for any copied material, and a compact table of the actual values selected for both palettes. Freeze that source before styling; never derive production styles from a moving branch or runtime network request. Start the comparison with the versions already used in Builder and Sales Assistant. Choose a reference that provides both palettes; no upgrade of either product is included.

The table covers page/sidebar/card backgrounds, primary and secondary text, separators, focus/selection, primary and destructive actions, status colors, font family/weights, spacing, radius and the sizes of controls used by this change. Use Twenty's neutral surfaces and restrained borders as the default. Do not copy CRM-specific layout or Builder's separate orange accent and dark-only policy by accident.

Translate this table into an owned static stylesheet under `shims/app/javascript/dashboard/inclamo/theme/`. Prefer CSS variables and the existing Chatwoot semantic colors. Chatwoot variables sometimes hold RGB channels and sometimes comma-separated alpha values; convert the source values into the format each consumer expects. Simply aliasing a full Twenty color expression into every Chatwoot variable would be invalid.

Import only the values and rules we use. Do not add `twenty-ui`, its full stylesheet/reset, its React icon catalog or Monaco to the helpdesk dependency tree. Reuse Chatwoot's locally bundled Inter fonts and existing icons. This is a small local mapping; a generator/shared package is deferred until actual duplication justifies one.

### D3. Scope the theme to the authenticated workspace, including teleported controls

Add one stylesheet import in the dashboard asset path. All added selectors are gated by an owned `inclamo-dashboard-theme` class on `body`. The authenticated workspace container adds the class on mount and removes it on unmount/logout. This small lifecycle hook only establishes the presentation scope; it does not observe the DOM, replace elements or create another preference system.

Use Chatwoot's existing `body.dark` state to select the dark values. Do not alter its appearance helper or store a second preference. Scope on `body` lets native dialogs and menus teleported there inherit the same values. Also verify that returning to sign-in in the same browser session removes the theme; checking a fresh sign-in tab alone would miss this failure.

Do not change shared global font/color definitions in a way that affects the widget, survey, public help centre or superadmin. A shared component used outside the workspace must retain its original fallback values when the theme class is absent. Preserve the existing font-size setting; token dimensions should scale in rem where appropriate.

### D4. Centralize presentation changes and make every upstream patch explainable

The baseline changes are the stylesheet import and workspace lifecycle hook. Additional patches may expose presentation variables in shared dashboard controls when the existing palette/configuration cannot express the desired result. Keep fallbacks equal to upstream defaults.

Each patch entry in `docs/dashboard-theme.md` records the file, visual purpose, why existing variables were insufficient and the check covering it. Use the next available patch number at implementation time; current feature branches already carry other numbered patches. Never edit the assembled `build/chatwoot` tree as the source of truth.

Use this order: existing variable override, existing component option, then a small presentation-only shared-component patch. Do not replace shared component implementations or scatter overrides based on generated classes, deep DOM ancestry or `nth-child`. Avoid new `!important` rules and JS-driven restyling. Do not change handlers, routes, state or permission logic for visual matching.

If a visual detail requires editor logic changes, list virtualization changes, many page-specific fixes or structural layout changes, leave that detail at its native appearance and record it as an intentional difference. A requirement for that detail would need a separately revised scope; it is not implicit permission to expand this change.

### D5. Complete a defined set of surfaces and smoke-check the rest

| Surface | Work in this change |
| --- | --- |
| Navigation, conversation list/header, composer frame | Apply the shared palette, typography, separators and existing control sizing; keep routing, pane structure and list behavior |
| Customer and Shopify order sidebar | Use the same text hierarchy, spacing, borders and native controls; retain customer/order state and permissions |
| Order dialogs | Align dialog surface and controls; retain native modal behavior, validation and action identifiers |
| Order permissions and preset rules | Apply the same page/header/row/control rules through the existing settings layout |
| Other authenticated pages | Inherit foundation; smoke-check contacts, inbox settings and automation editor for regressions; no bespoke redesign |
| Widget, public help centre, survey, sign-in, superadmin | No theme activation; regression-check isolation |

Start with the conversation workspace because it exposes most of the reusable parts. Check it in both palettes before extending adjustments to settings. This is an implementation sequence, not an additional approval gate or a separate mock-only deliverable.

### D6. Use visual references and existing workflow tests together

Add a focused `e2e/tests/dashboard-theme.spec.mjs` suite mapped to `helpdesk-visual-theme` in the existing coverage checker. Use the assembled dashboard with synthetic accounts/conversations and fixture-backed Shopify answers. No live store calls or real credentials are needed for this suite. Keep the live-store suite's screenshot/trace policy unchanged; run theme snapshots through an explicitly separate synthetic-data configuration/job.

Record before/after screenshots at 1440x900 in both palettes for the workspace with an order panel, one open action dialog and the two Inclamo settings pages. Check 1024x768 and a narrow 390x844 viewport using the existing responsive behavior; include long content and one RTL case. Do not require pixel equality with Twenty CRM or screenshots across different browsers/OSs. Pin the browser/environment for regression baselines, await fonts and mask only nondeterministic data.

The visual reference checklist from D2 is the acceptance baseline for colors, typography, control sizes, borders and states. Inspect newly recorded images against that checklist; a snapshot test passing against its own newly recorded image is not sufficient acceptance. Record deliberate differences. For changed color pairs use at least 4.5:1 for normal text, 3:1 for large text and meaningful non-text control/focus indicators; do not weaken disabled-state semantics or signal errors by color alone. This checks the changed surfaces, not a certification of all upstream pages.

Cover the twelve spec scenarios with named tests, grouping multiple related screenshots/assertions in each where useful. Exercise native keyboard focus/modal return, light/dark/auto preferences, a preserved unsent draft, messages/variables/attachments, unavailable/refused actions, and theme removal on logout. Existing action tests retain coverage of idempotency; extend them only if the control refactor changes a relevant path. Run the existing overlay and affected seam/component tests, without adding Ruby tests for a presentation-only change.

### D7. Keep performance checks proportionate and measurable

Compare the baseline and themed production builds from the same working-source snapshot, Chatwoot pin, lockfile and toolchain. Exclude unrelated working-tree changes from the comparison. Record initial dashboard assets and the assets fetched when first opening an action dialog/settings page, so lazy-loading cannot conceal added weight.

Engineering budgets for this change, not measurements: no new UI runtime, remote theme/font requests or new font files; at most 20 KiB additional gzip CSS and 10 KiB additional gzip JavaScript over the paired baseline. CSS-based token adaptation should fit comfortably; an excess requires reducing the implementation or explicitly revising the design before calling it complete.

Use five repeated warm conversation-open and dialog-open interactions on the same synthetic dataset/browser. Record medians with the before/after evidence. A repeatable increase above the greater of 10% or 50 ms requires investigation and correction or a documented measurement explanation. This is a bounded acceptance experiment, not a new benchmarking service or a noisy timing assertion on every CI run.

### D8. Preserve the current product and integration scope

The own-product build has one visual theme with light/dark palettes. No stock-theme selector or third-party compatibility mode is added. Existing bot-token/overlay integration decisions remain unchanged. Adjust only the original-appearance clause and slice description in `docs/spec-plan.md` during implementation; keep its native behavior and upstream-maintenance commitments. Do not edit sibling product repositories or old change artifacts as part of this proposal.

## Risks / Trade-offs

- [Some appearance is hard-coded outside the common controls] → Use the D4 order and record intentional differences; do not promise a pixel-identical Twenty interface.
- [Native controls have different dimensions or interaction details] → Preserve behavior and focus targets, verify long content and existing font-size preferences, and avoid list-layout/virtualization changes.
- [Portals or logout escape theme scope] → Use the workspace-owned body class and test teleported controls plus same-session logout.
- [Global style changes affect unthemed surfaces] → Gate selectors and defaults; verify public entry points and shared-component consumers.
- [Upstream patch conflicts and silent visual drift] → Maintain the patch inventory, fail assembly on conflicts, run the visual suite and affected component tests on each supported upgrade.
- [Twenty/Builder versions diverge] → Freeze and document the chosen reference; update deliberately as a separate change when needed.
- [Screenshots expose real data or tests depend on Shopify availability] → Use synthetic fixtures in a separate theme run and retain the existing live-store evidence policy.

## Migration Plan

1. Record the current source snapshot, reference values and baseline measurements. Implement in an isolated working checkout so existing unrelated work is preserved.
2. Add the scoped foundation and central control adjustments; validate the workspace, then the settings pages and isolation checks.
3. Build the usual CE-plus-overlay image and verify it on a test installation. Update the theme documentation and the focused release-plan clause. Production publication/deployment is outside this planning request.
4. When a release is authorized, deploy the validated image through the existing process. No data migration or user preference reset is needed. Roll back to the previously validated image if a regression is found; no reverse database migration is involved.

## References

- [Twenty UI setup](https://docs.twenty.com/ui/getting-started) and [theming](https://docs.twenty.com/ui/theming): components require React, while semantic values are available as CSS variables. The implementation record must pin the actual source revision used.
- Repository evidence: `custom/CHATWOOT_VERSION`, `scripts/assemble.sh`, `docs/spec-plan.md`, `patches/`, the dashboard files named in Context, `shims/app/javascript/dashboard/inclamo/`, `scripts/check-e2e-coverage.mjs`, and `e2e/playwright.config.mjs`.
