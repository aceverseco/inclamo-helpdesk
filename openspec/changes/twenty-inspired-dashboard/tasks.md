## 1. Reference and baseline

- [x] 1.1 Prepare an isolated implementation checkout containing the current helpdesk source, including the existing feature work; record the source snapshot, Chatwoot pin and toolchain, and verify the baseline assembles without altering the original working tree.
- [x] 1.2 Freeze one exact Twenty reference revision and create the palette/typography/spacing/control-state table in `docs/dashboard-theme.md`; verify it covers both palettes, names source URLs and attribution, and identifies deliberate differences from Builder and native Chatwoot.
- [x] 1.3 Prepare synthetic accounts, conversations and fixture-backed order states using the existing test helpers where suitable; record baseline screenshots and production asset sizes, and verify the theme-test execution path makes no live Shopify requests and contains no real credentials.

## 2. Scoped theme foundation

- [x] 2.1 Add owned static theme assets under `shims/app/javascript/dashboard/inclamo/theme/` and a dashboard-only import patch; verify a production build resolves them without new runtime packages, Twenty's global stylesheet/reset or external font requests.
- [x] 2.2 Add the workspace-owned body class with mount/unmount cleanup and use the existing light/dark/auto state; verify navigation, reload, teleported menus/dialogs and same-session logout activate and remove the correct appearance.
- [x] 2.3 Map the reference palette and typography to native dashboard values, respecting their RGB/alpha formats and the user's font-size preference; verify computed values and changed color-pair contrast in both palettes, with local Inter fonts and usable fallbacks.

## 3. Native controls and operator workspace

- [x] 3.1 Adapt the shared button, field, menu/tab and dialog presentation used by the in-scope screens, using existing options first and minimal presentation-variable patches where needed; verify normal, hover, focus, selected, loading, disabled and error states, with upstream fallbacks outside the theme scope.
- [x] 3.2 Apply the foundation to navigation, conversation list/header and composer framing; verify before/after screenshots against the reference table and check that pane structure, conversation selection, list behavior and editor shortcuts remain intact.
- [x] 3.3 Align the customer/order sidebar and normalize its controls onto native components where appropriate; verify all existing OrdersSection and OrderCard tests pass and that selected-order state still feeds reply variables.
- [x] 3.4 Align connection and order-action dialogs using the native modal implementation; verify existing dialog tests, keyboard focus/return, validation, unavailable actions and pending/refused feedback, while retaining action identifiers and duplicate-submission protection.

## 4. Settings and surface isolation

- [x] 4.1 Align the order-permissions and preset-rules pages with the same header/row/control rules; verify administrator access, switch rollback on refusal, input errors and existing settings component tests.
- [x] 4.2 Check contacts, inbox settings and the automation editor under the inherited foundation; verify primary controls remain reachable and resolve regressions centrally without introducing page-specific redesigns.
- [x] 4.3 Check widget, public help centre, survey, sign-in and superadmin against the baseline, including sign-in reached by logout; verify theme styles do not leak and shared components keep their original presentation outside the workspace.

## 5. Visual and behavior acceptance

- [x] 5.1 Add `e2e/tests/dashboard-theme.spec.mjs` with tests named after all twelve `helpdesk-visual-theme` scenarios and register the capability in `scripts/check-e2e-coverage.mjs`; verify every scenario maps to a test and preserve existing capability mappings.
- [x] 5.2 Add a dedicated synthetic-data Playwright configuration/CI run for theme snapshots using a pinned browser; verify screenshots can be retained there while the existing live-store suite's screenshot/trace restrictions remain unchanged.
- [x] 5.3 Run the workspace, open-dialog and Inclamo-settings snapshots in light and dark modes at 1440x900, plus 1024x768 and 390x844 usability checks with long content and an RTL case; inspect images against the reference table and record intentional differences rather than accepting baselines blindly.
- [x] 5.4 Run the theme behavior scenarios and existing overlay/affected seam tests; verify reply modes, variables, attachments, unsent drafts, action feedback, keyboard navigation, stored/auto appearance and operation with external theme hosts blocked.
- [x] 5.5 Compare paired production builds and five repeated conversation/dialog interactions against design D7; verify the additional gzip CSS/JavaScript stays within 20/10 KiB, no new font/runtime/service is loaded, and investigate any repeatable timing regression above the specified threshold.

## 6. Upgrade record and completion

- [x] 6.1 Complete the presentation-patch inventory with each file, purpose, fallback and covering check; verify a fresh assembly of the pinned CE source applies all patches, preserves other feature patches and builds the dashboard.
- [x] 6.2 Update only the relevant appearance clause and slice description in `docs/spec-plan.md`, and document the theme reference, known differences and upgrade/rollback procedure; verify no new promise of third-party integration, voice work or a second product theme is introduced.
- [x] 6.3 Build the usual CE-plus-overlay image and run the focused acceptance checks on a test installation; attach the visual and performance evidence to the change and verify `openspec validate twenty-inspired-dashboard --strict --no-interactive` passes before marking the implementation complete.
