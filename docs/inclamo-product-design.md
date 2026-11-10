# Inclamo product design

The staff application uses the approved `prototypes/operator-dashboard` visual reference: original Inclamo mark, navy ink, sky-blue controls, orange accents and white light-mode surfaces. Native Vue components keep their state, permissions, events and keyboard behavior. No additional runtime, component library or remote service is added to production.

This supersedes the earlier Twenty-inspired palette and the earlier exclusion of authentication and administration. The completed Twenty proposal remains historical evidence. Sibling CRM/Builder applications and public merchant branding are independent.

## Source and boundaries

- `shims/app/javascript/dashboard/inclamo/theme/`: palette, shared controls, workspace structure, authentication and administration styles.
- `shims/app/javascript/dashboard/inclamo/components/{BrandMark,WorkspaceHeader}.vue`: presentation using the real current account and user.
- `shims/public/brand-assets/`: unchanged original mark plus composed light/dark wordmarks. Source SVG SHA-256: `9bc0807a517e86b98a02f2a59cb0b490545f72548855f1be832acbf1b583d5e7`.
- `patches/0006-dashboard-theme.patch`: existing token/radius seams. `0007-inclamo-branded-workspace.patch`: current presentation hooks and staff entry points, listed below.
- `custom/`: existing backend overlay, unchanged by this design.

`body.inclamo-app-theme` owns dashboard application tokens, including teleported controls. `body.inclamo-dashboard-theme` owns account workspace geometry. The separate v3 authentication entry imports the same tokens and honors its native HTML/root dark class. Installation administration and onboarding share the existing standalone layout, with `body.inclamo-administration`. The public widget, portal and survey do not import staff structure. Default product logos are local; merchant-configured logos and channel colors remain configured by their native mechanisms.

Default `INSTALLATION_NAME` becomes Inclamo. The staff dashboard controller also presents Inclamo when an existing installation still has the exact upstream default `Chatwoot`, without modifying its database or replacing custom installation names. Upstream licenses and version links are retained.

## Visual contract

| Purpose | Light appearance |
| --- | --- |
| Ink / identity | `#101B3D` |
| Primary button fill | `#91C8F5`, with navy text |
| Accent | `#FF6A00`; pale orange and dark orange for readable surfaces/text |
| Main panels / canvas | White |
| Fields / outgoing messages | `#EEF7FF` |
| Selection | `#E1F1FF` |
| Decorative separators | `#E2EAF3` |
| Focus | `#326FA8`, 2px outline |
| Input boundary | `#6B89A6`, distinct from decorative separators |
| Font | Existing local Inter; user font-size preference preserved |
| Control / panel / dialog radius | 6 / 10 / 14px at 16px root |
| Default sidebar / condensed list / customer panel | 218 / 294 / 300px at desktop default font size |

The compatible dark appearance uses navy surfaces, pale ink and sky controls. Status/error colors remain semantic. No fabricated AI state, online-agent count or demo customer is rendered in the product. Native channel tools, account switching, sidebar resizing, expanded conversation lists and mobile drawers remain available.

## Validation and upgrades

Assemble the pinned CE tree with `scripts/assemble.sh <isolated-target>`; build the ordinary upstream Dockerfile. Each patch must apply cleanly in order. Never edit generated `build/chatwoot` as the source of truth.

Run owned/native component checks and `node scripts/check-ui-strings.mjs`. Run `HELPDESK_IMAGE=<image> sh e2e/theme/run.sh --update-snapshots` in a disposable installation, visually review the resulting `inclamo-*.png`, then rerun without snapshot updates. The default suite is `inclamo-product-design.spec.mjs`; `THEME_LEGACY=1` selects the historical Twenty suite for paired measurements against an older image. Fixtures, accounts, passwords and Shopify responses are synthetic; the Docker network is internal. Existing installations are not reseeded.

Coverage includes actual replies, private notes and attachments, drafts, order-action refusals and permissions, contacts, reports, settings, authentication/admin, keyboard, dark/auto, larger fonts, mobile/RTL and public boundaries. Compare reachable gzip assets and five warm conversation/dialog interactions with the previous build. Investigate growth above 32 KiB CSS, 16 KiB JavaScript, or an interaction median increase above max(10%, 50ms). Do not accept screenshots solely because the snapshot tool updated them.

No data migration is needed. Deploy the checked product image through the existing installation process; rollback is the preceding image. Mobile APIs are unchanged, so future iOS/Android applications remain possible. The web presentation itself is not a native mobile implementation.

## Additional native seams

- `app/controllers/dashboard_controller.rb`
- `app/javascript/dashboard/App.vue`
- `app/javascript/dashboard/components-next/Contacts/ContactsListLayout.vue`
- `app/javascript/dashboard/components-next/button/Button.vue`
- `app/javascript/dashboard/components-next/input/Input.vue`
- `app/javascript/dashboard/components-next/message/Message.vue`
- `app/javascript/dashboard/components-next/message/bubbles/Base.vue`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- `app/javascript/dashboard/components-next/sidebar/SidebarGroupHeader.vue`
- `app/javascript/dashboard/components-next/sidebar/SidebarGroupLeaf.vue`
- `app/javascript/dashboard/components-next/sidebar/provider.js`
- `app/javascript/dashboard/components/ChatList.vue`
- `app/javascript/dashboard/components/ChatListHeader.vue`
- `app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue`
- `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue`
- `app/javascript/dashboard/components/widgets/conversation/ConversationSidebar.vue`
- `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`
- `app/javascript/dashboard/routes/dashboard/Dashboard.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/ConversationView.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue`
- `app/javascript/dashboard/routes/dashboard/settings/SettingsHeader.vue`
- `app/javascript/dashboard/routes/dashboard/settings/SettingsWrapper.vue`
- `app/javascript/entrypoints/superadmin.scss`
- `app/javascript/v3/App.vue`
- `app/javascript/v3/views/login/Index.vue`
- `app/views/layouts/super_admin/application.html.erb`
- `app/views/super_admin/application/_brand.html.erb`
- `app/views/super_admin/application/_standalone.html.erb`
- `config/installation_config.yml`
