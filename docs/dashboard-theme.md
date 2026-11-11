> Historical Twenty-inspired implementation. The current staff design is documented in [Inclamo product design](inclamo-product-design.md); that change supersedes the palette, pane geometry, authentication and administration scope below.

# Dashboard appearance

The account workspace uses one Twenty-inspired theme with Chatwoot's existing light, dark and automatic appearance preference. Vue components, routes, API contracts, pane layout and editor behavior stay native. The theme is a local stylesheet, not a runtime dependency on Twenty or Builder.

## Implementation source

Chatwoot CE is pinned to **v4.19.1**, commit `caab07a8f00032d5205b5a5d7e2eb0ba2f3d2d82`. Paired local production builds use Node **26.7.0**, pnpm **10.2.0** and Vite **6.4.2**, with the same lockfile. The ordinary product Docker build uses the upstream-pinned Node **24.22.1** and Ruby **3.4.4**. These are separate records: the asset comparison uses the identical local toolchain for both builds; installation acceptance uses the usual image.

## Frozen visual reference

Reference: **twenty-ui 2.41.0**, the release already installed in the Sales Assistant panel. [Package release](https://www.npmjs.com/package/twenty-ui/v/2.41.0), [Twenty theming documentation](https://docs.twenty.com/ui/theming). The two distributed reference files have these SHA-256 checksums:

| File | SHA-256 |
| --- | --- |
| `dist/theme-light.css` | `eb7d4b698c679d39b11c8852e788efb899d28736c6efc4e1e941f50bd0f9097b` |
| `dist/theme-dark.css` | `cc5bf99b7ea1a584af88fc7521dee8af6e10768ccdb6c2903346abd7a9817e22` |

Neutral Display-P3 reference values are rounded to equivalent 8-bit sRGB grays. The accent is an adapted sRGB blue; it is not a direct conversion of Twenty's P3 accent. Only the selected values are reproduced. The package's global reset, inline noise textures, fonts, icons and JavaScript are not imported. Copyright (c) 2023-present Twenty.com, PBC; the MIT notice is retained in `shims/app/javascript/dashboard/inclamo/theme/LICENSE.twenty`.

| Purpose | Light | Dark | Application |
| --- | --- | --- | --- |
| Page | `#fcfcfc` | `#171717` | `background-color` |
| Main surface / card | `#ffffff` | `#1b1b1b` | `surface-1`, `card-color` |
| Secondary surface | `#fcfcfc` | `#1d1d1d` | `surface-2` |
| Selected / raised neutral | `#f1f1f1` | `#222222` | `surface-active` |
| Primary text | `#333333` | `#ebebeb` | `slate-12` |
| Secondary text | `#666666` | `#b3b3b3` | `slate-11` |
| Muted text | `#6c6c6c` | `#a0a0a0` | `slate-10`; adapted for legibility |
| Separator | `#ebebeb` | `#222222` | `border-weak`, `border-container`; decorative |
| Strong border | `#d6d6d6` | `#484848` | `border-strong` |
| Input boundary | `#858585` | `#818181` | Local field aliases for normal/hover; error boundary uses native ruby-11 |
| Primary action | `#3c61d8` / white text | Same | `inclamo-brand`; native loading/disabled behavior |
| Accent text | `#3554b1` | `#9eb1ff` | Separate from action fill for contrast |
| Keyboard focus | `#3e63dd` | `#9eb1ff` | 2px outline with 2px offset |
| Hover overlay | black 3.9% | white 5.9% | `alpha-2`; native component states |
| Field surface | black 2% | white 3.1% | `background-input-box` |
| Dialog surface | white 96% | `#1b1b1b` 96% | `alpha-3` |
| Destructive / warning / success | Native ruby / amber / teal | Native dark equivalents | Status meaning and text labels retained |
| Disabled / loading | Native 50% opacity / spinner | Same | No new state machine |
| Font | Local Inter; system fallback | Same | Existing 400/500/600 hierarchy; no root font-size reset |
| Spacing | Existing 4px-based scale | Same | Native pane widths, list rows and hit targets |
| Control / panel / dialog radius | 4 / 8 / 16px at default font size | Same | rem-based; user font preference remains effective |
| Control heights | Native 24 / 32 / 40 / 48px | Same | Retained rather than reproducing every Twenty size |

Chatwoot's `--slate-*` and solid color consumers expect space-separated RGB channels. Its alpha variables expect comma-separated RGBA. The owned stylesheet preserves these formats. Status colors remain Chatwoot's; the reference is deliberately not a pixel copy of Twenty CRM. Builder's orange accent and dark-only policy are not adopted, and this change does not upgrade either sibling product.

## Scope and patch inventory

`Dashboard.vue` owns `body.inclamo-dashboard-theme` through a mount/unmount composable. `body` includes native teleported dialogs and menus. The scope is removed when leaving the account workspace. Existing `body.dark` and `color_scheme` storage remain the only appearance state. There is no DOM observer, second preference, injected React runtime or theme service.

All changes below are in `patches/0009-dashboard-theme.patch`; they follow existing feature patches. Fallbacks preserve upstream appearance outside the workspace.

| Upstream file (under `app/javascript/dashboard` unless stated) | Purpose / reason a patch is needed | Fallback / covering check |
| --- | --- | --- |
| `App.vue` | Import the owned stylesheet into the dashboard asset | Selectors inactive without body class; public-surface test |
| `routes/dashboard/Dashboard.vue` | Own the theme lifetime | No routing/state change; navigation, reload and logout tests |
| `theme/colors.js` (repository root) | Expose hard-coded brand as a variable | Original `#2781f6`; public-surface and control-state checks |
| `tailwind.config.js` (repository root) | Select local Inter in the existing stack and separate accent text from the action fill | Original `-apple-system` and `#2781f6`; font-size, contrast and public-surface checks |
| `components-next/button/Button.vue` | Expose hard-coded control radius | Original 8px; reply/action/settings tests |
| `components-next/input/Input.vue` | Same for native input | Original 8px; settings and dialog validation |
| `assets/scss/_base.scss` | Same for legacy buttons and base HTML fields | Original 8px; composer, connection and public-surface checks |
| `components-next/tabbar/TabBar.vue` | Align all three tab layers | Original 8px; workspace screenshots |
| `components-next/dropdown-menu/base/DropdownItem.vue` | Align menu item hover/selected shape | Original 8px; profile menu and keyboard tests |
| `components-next/dropdown-menu/base/DropdownBody.vue` | Align menu surface and its blur pseudo-element | Original 12px; profile menu/logout test |
| `components-next/dialog/Dialog.vue` | Align outer dialog and form surface together | Original 12px; native focus/return, action tests |

The order action buttons reuse the existing native Button with slate/outline/xs options. Their handlers, restrictions and action identifiers are unchanged. Owned HTML fields use the same radius variable with their original 6px fallback. No new wrapper component is introduced.

## Acceptance and upgrades

`e2e/theme/run.sh` runs the assembled product against an isolated fixture-only Shopify service. The Docker network is internal: server and browser cannot reach a live store. Credentials are disposable examples. The normal live-store suite excludes this file and retains its existing screenshot/trace restrictions.

The theme configuration pins Chromium through Playwright **1.56.0** and its matching Noble image. It covers all twelve `helpdesk-visual-theme` scenarios. Screenshots use synthetic identities, 1440x900 light/dark workspace, dialog and settings views, plus 1024x768, 390x844 and RTL checks. Newly recorded snapshots must be inspected against the table above before being accepted. Visual review is required alongside snapshot regression checks.

The narrow-screen checks use the native contact drawer: inspect the customer, close it, then compose a reply. They verify the send button can receive a click. Pane widths, the drawer breakpoint, message bubbles, status colors, icons, shadows and the native sidebar layout intentionally remain Chatwoot's.

For an upstream upgrade: assemble the new pinned CE source, resolve each documented presentation patch explicitly, run the overlay and affected native component tests, build the normal image, then run the synthetic theme suite. Review any snapshot differences and check that no font, runtime or remote theme dependency appeared. Compare production gzip assets including lazy dialog/settings chunks: CSS growth must stay within 20 KiB and JavaScript within 10 KiB. The acceptance experiment records five warm conversation and dialog openings; investigate a median increase over the larger of 10% or 50ms.

Deployment uses the existing CE-plus-overlay image process. No database migration or preference reset is introduced. Rollback means redeploying the previously validated image.

## Future mobile clients

This presentation layer does not change the backend API and does not prevent a future iOS or Android client. Its visual values can inform mobile screens, but the Vue components are web components and are not automatically reusable as native screens. Choosing a mobile client, adding push/voice capabilities and publishing to stores remain separate work.
