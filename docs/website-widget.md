# Website widget customization

Implemented on the pinned Chatwoot CE v4.19.1. Source lives in `custom/`, `shims/` and `patches/0014-website-widget.patch`; `build/website-widget-workspace/chatwoot` is a disposable assembled checkout.

## Administration

Administrators open **Workspace tools → Website widget**, or the **Website widget** entry in account settings. The native website inbox page also links to it. The selected website remains in the URL: `/app/accounts/:accountId/settings/website-widget?inbox=:inboxId`. Accounts without a website channel link to `/settings/inboxes/new/website`.

| Section | What is saved here |
| --- | --- |
| Appearance | Native header logo/color; launcher choice or upload, icon/expanded button, label, position, offsets and theme |
| Home screen | Native chat name, greeting and connected Help Center; ordered suggested intents and help links |
| Behavior | Fixed/browser language, expected reply time and pathname visibility |
| Installation | Stable embed code and migration/custom-launcher guidance |

Behavior links to native inbox **business-hours**, **pre-chat-form**, **csat**, **bot-configuration**, **configuration**, and the main inbox settings tab for feature flags and email continuity. Those pages save their own changes. Existing URLs, permissions, domain/identity checks, conversations and messaging APIs remain authoritative.

Save publishes native and extension values in one transaction. A failing save retains the draft and leaves the previous publication intact. A concurrent publication or native settings edit returns HTTP 409; the editor keeps the unsaved input and offers a reload. Unsaved settings are neither stored in administrator localStorage nor shared with other administrators.

## Supported settings

- Six enabled starters and six enabled help links, at most 30 stored entries of each kind; stable ids survive reordering. Labels: 60 characters; starter messages: 500. Welcome heading: 120; tagline: 255.
- Starters send an ordinary message. They do not look up an order, issue a refund, invoke Builder or complete a business operation. Required pre-chat fields remain required; the starter message can be edited or abandoned before submission. Existing/resolved conversations and native bot handoff keep their normal rules. An uncertain failed send is never automatically retried.
- Links open published articles from the connected account portal in the native article viewer, or HTTPS URLs without embedded credentials. Disabled/unavailable articles are omitted. A link click does not create a conversation.
- Launcher uploads: PNG, JPEG, WebP or an allowlisted static SVG, at most 1 MiB. The native header logo accepts PNG, JPEG and WebP through this editor (also capped at 1 MiB). Raster files must actually decode and fit within 4096 × 4096 pixels. SVG rejects scripts, events, embedded HTML, external references, DTD/entities and unsupported attributes. Gradients/references using `url(...)` are outside the accepted subset.
- SVG is stored in Active Storage. Only a validated SVG receives the purpose-bound signed inline image URL; the normal Chatwoot SVG download policy is unchanged. The image response has a restrictive CSP, `nosniff` and immutable caching. Replacing an image produces a new URL. Other uploads use ordinary Active Storage delivery.
- Side/bottom offsets: integer 0–160 px, clamped to the available viewport/safe area. Long expanded labels truncate visually while retaining the full accessible name. A failed custom image restores the default icon.
- Visibility: all pages, include or exclude; up to 20 exact/prefix pathname rules. Query strings/fragments do not participate. Uses the native SDK location-change integration, including SPA DOM updates. Excluded pages close automatic display and retain session/history; an explicit custom-launcher open is allowed.
- Fixed locale or browser locale with account-language fallback; native translations/RTL are reused. Merchant-written labels/messages are not translated. Light/dark/auto uses native widget theme behavior.

The staff sidebar logo is independent: the original full `inclamo_logo_text_500.jpg` is copied unchanged to `/brand-assets/inclamo-logo-combined.jpg`, SHA-256 `6ee5a4ea5d51dd0a417475c56b99968d6eeba52d502b8eb6fddc2c33deb3f541`. Since the 2026-11-11 refinement it is displayed at 64 × 64 px in the expanded sidebar and 96 × 96 px above the native login form. The compact symbol and favicon are unchanged. The login-only template seam is `patches/0015-brand-logo-size-and-login.patch`.

## Preview and installation

Preview renders the same native widget application, components and launcher helpers in an authenticated iframe with synthetic in-memory store actions and memory routing. It does not import the public widget entrypoint, create a visitor, open a messaging connection or send widget API requests. Its HTTP adapter cannot deliver messages, links remain local, and parent/frame messages require matching origin and source. Desktop/mobile, home/conversation and online/offline controls exercise the presentation before publication.

The new installation snippet contains only the normal base URL and website token. Publication takes effect on the next widget page load; active conversations are not forcibly reloaded. Presentation precedence is **valid explicit `window.chatwootSettings` option → saved inbox setting → native default**. Existing snippets, `hideMessageBubble`, identity integration and programmatic open continue working.

For a legacy installation, remove only the explicit presentation options you want the editor to control (for example `position`, `type`, `launcherTitle`, `darkMode`, `locale`, `useBrowserLanguage`). Do this once on the website. Keep the website token, identity/HMAC integration and any intentional behavior options. An explicit `useBrowserLanguage: false` also remains authoritative; remove that option if the editor should control browser-language selection. The editor cannot inspect a remote site's old snippet and does not silently publish browser-local builder values.

A custom site button may call `window.$chatwoot.toggle('open')` after `chatwoot:ready`. To hide the built-in launcher, set `window.chatwootSettings = { hideMessageBubble: true }` before loading the SDK.

## Implementation seams

Owned backend: `Inclamo::WebsiteWidget`, `Settings`, `Configuration`, `Image`, the account-scoped configuration/preview controller and signed image controller. Additive migrations create `inclamo_website_widgets` and its publication counter; native channel tables and message schema remain unchanged. The revision fingerprints shared native values, attached blob ids and the publication counter. Separate native edits conflict; background thumbnail/metadata processing does not create false conflicts.

The small upstream patch covers:

- `widgets/show.html.erb`: safely serialized public settings and safe greeting/name/header-image serialization.
- SDK `IFrameHelper.js`: ready-time presentation resolution, launcher decoration, pathname visibility and suppression of automatic unread opening.
- Widget `App.vue`: preview bootstrap guard and page-visibility signal.
- Widget `Home.vue`: owned optional home actions.
- `PreChat/Form.vue` and `views/PreChatForm.vue`: transient editable starter prefill and visible submission failure.
- Conversation store actions: return success/failure to the caller while retaining native requests and failed-message handling.
- Widget router: memory history only for the isolated preview.
- `HeaderActions.vue`: accessible close name using a native translation.
- Native inbox `Settings.vue`: editor link.

No Enterprise source, alternate messaging client, Builder runtime, extra polling or duplicate WebSocket is introduced. Public initial-load budget is measured across the SDK plus every loaded widget JS dependency, not just the entry file. The additional editor and preview entry are not loaded by visitors.

## Verification and rollback

Reproducible synthetic scenarios live in `e2e/website-widget/`. Run them only against an isolated fixture stack, never a merchant account. `compose.yaml` is an override for `e2e/theme/compose.yaml`; its private-network allowance is required only for the local synthetic bot and must not be copied into production. Use `seed.rb` after the theme seed. Fixture assertions run local Docker commands by default. For a remote synthetic stack, set `WIDGET_FIXTURE_SSH` to its SSH host and optionally `WIDGET_SSH_COMMAND` to your SSH wrapper. Container names can be overridden with `WIDGET_POSTGRES_CONTAINER` and `WIDGET_BOT_CONTAINER`. Install the browser scripts' pinned Playwright dependency with `npm install --prefix e2e`; the scripts use Chrome.

```sh
WIDGET_BASE=http://localhost:3197 node e2e/website-widget/acceptance.mjs
WIDGET_BASE=http://localhost:3197 node e2e/website-widget/native-flows.mjs
WIDGET_BASE=http://localhost:3197 node e2e/website-widget/editor-checks.mjs
WIDGET_BASE=http://localhost:3197 node e2e/website-widget/visibility.mjs
WIDGET_BASE=http://localhost:3197 node e2e/website-widget/presentation.mjs
WIDGET_BASE=http://localhost:3197 node e2e/website-widget/delivery.mjs
WIDGET_BASE=http://localhost:3197 node e2e/website-widget/measure.mjs
```

Request tests: `custom/spec/requests/api/v1/accounts/inclamo/website_widgets_spec.rb`. Focused frontend tests: SDK settings/cookies, owned home actions and native pre-chat submission. Build both Vite application assets and `pnpm run build:sdk`. Run `scripts/assemble.sh` against a fresh pinned checkout to verify the entire patch chain.

Browser runs save review output under ignored `build/evidence/website-widget/`. Synthetic message/contact identities are test fixtures. Review the output separately from the source tree.

Rollback restores the previous backend/frontend image together and leaves the additive table/assets in place. Existing native settings, conversations and history remain valid. Older assets ignore widget-only options. Do not run a destructive database down-migration or mix old/new asset manifests. The original staff logo asset remains available independently.

## SuperAdmin branding

`patches/0016-superadmin-logo.patch` applies the combined image to SuperAdmin navigation (56 px inside its native 56 px header) and the standalone sign-in page (96 px). The image links to the product; the SuperAdmin label, release link and update indicator remain. The templates reuse existing asset and sizing styles.
