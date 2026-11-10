# Twenty-inspired dashboard acceptance

Date: 2026-11-09. Implementation and acceptance complete: **21/21 tasks**.

## Source and installation

The source snapshot, upstream pin, reference hashes, palette and all eleven upstream presentation seams are recorded in [dashboard-theme.md](../../../docs/dashboard-theme.md). The existing uncommitted feature work was included in the baseline snapshot and preserved.

The product image was built with `scripts/build-image.sh inclamo-helpdesk:theme-20261109`, using the normal assembled CE Dockerfile. Image ID: `sha256:f45f6db534a6679f8862ccf64c6807eff27c86c242aa07388eea8cb4cab12c1d`. Acceptance uses a separate synthetic installation, PostgreSQL, Redis and an internal Docker network. The fixture server only reads sanitized repository fixtures; it has no request-forwarding path. No production deployment is part of this change.

Baseline and themed assets use the same source snapshot, upstream pin, lockfile and local Node/pnpm/Vite versions. The baseline test image carries those baseline assets and the same overlay on the official pinned CE image; the themed installation uses the normal product image. Browser: Playwright 1.56.0 / matching Noble Chromium image, one worker, en-US, UTC, reduced motion.

## Visual evidence

Every image below uses synthetic identities. Reference review covers neutral surfaces, text hierarchy, blue actions, field boundaries, radii and native control states. Fixed, distinct conversation timestamps avoid ambiguous native list sorting. Behavior checks use real time; only screenshot scenarios fix the browser date.

| Surface | Before | After |
| --- | --- | --- |
| Workspace, light | [PNG](../../../docs/evidence/dashboard-theme/baseline-workspace-light.png) | [PNG](../../../e2e/theme/snapshots/workspace-light.png) |
| Workspace, dark | [PNG](../../../docs/evidence/dashboard-theme/baseline-workspace-dark.png) | [PNG](../../../e2e/theme/snapshots/workspace-dark.png) |
| Dialog, light | [PNG](../../../docs/evidence/dashboard-theme/baseline-dialog-light.png) | [PNG](../../../e2e/theme/snapshots/dialog-light.png) |
| Dialog, dark | [PNG](../../../docs/evidence/dashboard-theme/baseline-dialog-dark.png) | [PNG](../../../e2e/theme/snapshots/dialog-dark.png) |
| Order permissions, light | [PNG](../../../docs/evidence/dashboard-theme/baseline-order-actions-light.png) | [PNG](../../../e2e/theme/snapshots/order-actions-light.png) |
| Order permissions, dark | [PNG](../../../docs/evidence/dashboard-theme/baseline-order-actions-dark.png) | [PNG](../../../e2e/theme/snapshots/order-actions-dark.png) |
| Preset rules, light | [PNG](../../../docs/evidence/dashboard-theme/baseline-preset-rules-light.png) | [PNG](../../../e2e/theme/snapshots/preset-rules-light.png) |
| Preset rules, dark | [PNG](../../../docs/evidence/dashboard-theme/baseline-preset-rules-dark.png) | [PNG](../../../e2e/theme/snapshots/preset-rules-dark.png) |
| Workspace, 1024×768 | [PNG](../../../docs/evidence/dashboard-theme/baseline-workspace-1024.png) | [PNG](../../../e2e/theme/snapshots/workspace-1024.png) |
| Contact drawer, 390×844 | [PNG](../../../docs/evidence/dashboard-theme/baseline-contact-390.png) | [PNG](../../../e2e/theme/snapshots/contact-390.png) |
| Composer, 390×844 | [PNG](../../../docs/evidence/dashboard-theme/baseline-workspace-390.png) | [PNG](../../../e2e/theme/snapshots/workspace-390.png) |
| RTL, 1024×768 | [PNG](../../../docs/evidence/dashboard-theme/baseline-workspace-rtl.png) | [PNG](../../../e2e/theme/snapshots/workspace-rtl.png) |
| Sign-in after logout | [PNG](../../../docs/evidence/dashboard-theme/baseline-login.png) | [PNG](../../../e2e/theme/snapshots/login.png) |
| Superadmin sign-in | [PNG](../../../docs/evidence/dashboard-theme/baseline-superadmin.png) | [PNG](../../../e2e/theme/snapshots/superadmin.png) |
| Help centre | [PNG](../../../docs/evidence/dashboard-theme/baseline-help-centre.png) | [PNG](../../../e2e/theme/snapshots/help-centre.png) |
| Widget | [PNG](../../../docs/evidence/dashboard-theme/baseline-widget.png) | [PNG](../../../e2e/theme/snapshots/widget.png) |
| Survey | [PNG](../../../docs/evidence/dashboard-theme/baseline-survey.png) | [PNG](../../../e2e/theme/snapshots/survey.png) |

Deliberate differences from Twenty: Chatwoot's pane geometry, responsive drawer, message bubbles, icons, shadows, semantic status colors and control heights remain native. Text, focus and input-boundary colors are adapted for contrast rather than copied literally. The mobile check follows the existing drawer workflow and does not introduce a new mobile layout.

All seventeen themed images were visually inspected against the reference table and their baseline counterparts. The five excluded surfaces match their baseline pixels exactly: [comparison](../../../docs/evidence/dashboard-theme/public-surface-comparison.json). Same-session logout also removes the theme scope and its font/brand variables.

Measured minimum contrast across the changed text pairs is **4.65:1 light / 6.45:1 dark**; focus is **4.61:1 / 8.18:1** and meaningful field boundaries **3.27:1 / 4.33:1**. Primary actions pass 4.5:1 with white text. Native status colors and disabled-state opacity remain unchanged. The font preference was changed through the native profile UI to 20px, persisted across reload, applied to the workspace and its 20px dialog radius, then restored to 16px. [Computed contrast pairs](../../../docs/evidence/dashboard-theme/theme-contrast.json).

## Production assets

The comparison includes all manifest-referenced JS, CSS and woff2 assets from both Vite manifests, including lazy chunks. Old hashed build leftovers and source maps are excluded. Both sides contain 59 JS, 15 CSS and 18 font assets. Gzip uses the same compressor on both sets.

| Asset | Baseline gzip bytes | Theme gzip bytes | Change | Budget |
| --- | ---: | ---: | ---: | ---: |
| CSS | 1,153,027 | 1,154,490 | +1,463 | +20,480 |
| JavaScript | 6,815,774 | 6,815,995 | +221 | +10,240 |
| Fonts | 2,475,876 | 2,475,876 | 0 | No new files |

Evidence: [totals](../../../docs/evidence/dashboard-theme/asset-comparison.json), [baseline assets and hashes](../../../docs/evidence/dashboard-theme/baseline-reachable-assets.json), [theme assets and hashes](../../../docs/evidence/dashboard-theme/themed-reachable-assets.json). No package/lockfile changes, React runtime, Twenty runtime, external font request or theme service were added.

Initial workspace, first dialog and Inclamo settings each reach the same set of 29 script/style/font resources in this pinned build. The loaded subset changes from 402,641 to 403,604 gzip CSS bytes and 6,522,486 to 6,522,730 gzip JS bytes. Both versions request only the existing local `InterVariable-CWi-zmRD.woff2`; all eighteen packaged font files are byte-identical. Resource inventories: [workspace before](../../../docs/evidence/dashboard-theme/baseline-workspace-resources.json), [after](../../../docs/evidence/dashboard-theme/theme-workspace-resources.json), [dialog before](../../../docs/evidence/dashboard-theme/baseline-performance.json), [after](../../../docs/evidence/dashboard-theme/theme-performance.json), [settings before](../../../docs/evidence/dashboard-theme/baseline-settings-resources.json), [after](../../../docs/evidence/dashboard-theme/theme-settings-resources.json).

## Interaction measurements

Five warm interactions follow one discarded warm-up on the same host/browser/data. Conversation measurement covers selecting Maya from Alex through the native list, the order-panel response and matched state. Dialog measurement covers expanding the order and opening its native action modal. Baseline and theme runs execute sequentially, with no image build running during measurement.

| Interaction | Baseline median | Theme median | Change | Investigation threshold |
| --- | ---: | ---: | ---: | ---: |
| Conversation | 258.99ms | 261.77ms | +2.78ms | +50ms |
| Dialog | 210.60ms | 200.04ms | −10.56ms | +50ms |

Both are within D7. These are bounded acceptance measurements, not a claim that every deployment will have these latencies. [Samples, medians and loaded asset totals](../../../docs/evidence/dashboard-theme/performance-comparison.json).

## Validation commands

Fresh pinned-source assembly and the local production build passed. Existing overlay and affected native seam tests passed: **13 files, 365 tests**.

The complete browser suite passed **12/12** on both [baseline](../../../docs/evidence/dashboard-theme/baseline-tests.json) and [theme](../../../docs/evidence/dashboard-theme/theme-tests.json), with retries disabled. It exercises selected-order reply variables, sending, private notes and attachments, preserved drafts, pending/refused actions, agent restrictions, native dialog focus/return, stored/auto appearance, contacts, inbox creation controls and the automation editor. The isolated network and explicit browser request blocking verify that external products are not required.

A separate run with snapshot updates disabled passed **5/5**: all seventeen saved images plus another font-size/contrast check. [Repeat-run results](../../../docs/evidence/dashboard-theme/verify-tests.json). The reviewed snapshots therefore also pass an independent comparison run. Source checksums are retained in [theme-source-hashes.json](../../../docs/evidence/dashboard-theme/theme-source-hashes.json).

```sh
scripts/assemble.sh build/chatwoot
# In build/chatwoot:
pnpm exec vitest --no-watch --no-cache --no-coverage \
  app/javascript/dashboard/inclamo \
  app/javascript/dashboard/composables/spec/useUISettings.spec.js \
  app/javascript/dashboard/components-next/sidebar/specs \
  app/javascript/dashboard/helper/specs/editorHelper.spec.js \
  app/javascript/dashboard/components/widgets/conversation/specs/ReplyBox.spec.js \
  app/javascript/dashboard/helper/specs/automationHelper.spec.js
# In the overlay repository:
scripts/build-image.sh inclamo-helpdesk:theme-20261109
HELPDESK_IMAGE=inclamo-helpdesk:theme-20261109 sh e2e/theme/run.sh
node scripts/check-ui-strings.mjs
node scripts/check-e2e-coverage.mjs
openspec validate twenty-inspired-dashboard --strict --no-interactive
```

The coverage checker maps all twelve theme scenarios and preserves existing mappings: 88 of 89 repository scenarios have E2E tests, with one pre-existing documented exception. The dedicated workflow uses the same synthetic runner. The live-store suite continues to exclude theme screenshots and retains its previous screenshot/trace restrictions.
