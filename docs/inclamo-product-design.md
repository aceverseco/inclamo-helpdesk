# Inclamo product design

The staff application uses an Inclamo visual theme: original Inclamo mark, navy ink, sky-blue controls, orange accents and white light-mode surfaces. Native Vue components keep their state, permissions, events and keyboard behavior. The application uses actual locally owned shadcn-vue component sources adapted to the existing native control APIs. They share Chatwoot’s Vue runtime; no React or remote design service is added.

This supersedes the earlier Twenty-inspired palette and the earlier exclusion of authentication and administration. The completed Twenty proposal remains historical evidence. Sibling CRM/Builder applications and public merchant branding are independent.

## Source and boundaries

- `shims/app/javascript/dashboard/inclamo/ui/`: approved shadcn-vue button, input, tabs, dropdown-menu and badge sources, with provenance in `registry.json` and the MIT license.
- `shims/app/javascript/dashboard/inclamo/theme/`: palette, shared controls, workspace structure, authentication and administration styles.
- `shims/app/javascript/dashboard/inclamo/components/{BrandMark,WorkspaceHeader}.vue`: presentation using the real current account and user.
- `shims/public/brand-assets/`: unchanged original mark plus composed light/dark wordmarks. Source SVG SHA-256: `9bc0807a517e86b98a02f2a59cb0b490545f72548855f1be832acbf1b583d5e7`.
- `patches/0008-shadcn-workspace.patch`: native adapters, dependency manifest/lockfile and the corrected workspace integration; applied after the earlier presentation patches.
- `patches/0010-profile-menu.patch`: two sidebar presentation adapters for the owned shadcn profile/availability menu. Native handlers, role checks and branding restrictions remain in place. The popup uses collision-aware placement, keyboard navigation and the existing light/dark tokens; dialog actions run after menu focus is released.
- `workspace/useQueueCounts.js`: independent account-wide open queue counts, loaded through native metadata and refreshed from native events. Navigation no longer reads filtered list statistics or hides counts on secondary routes.
- `patches/0011-brand-favicons.patch`: staff browser/touch icon URLs and native notification icon switching use Inclamo assets. Regenerate the checked-in PNG/ICO exports from the unchanged logo with `node scripts/render-brand-icons.mjs` (existing prototype Playwright development installation and Chrome required).
- `patches/0006-dashboard-theme.patch`: existing token/radius seams. `0007-inclamo-branded-workspace.patch`: current presentation hooks and staff entry points, listed below.
- `custom/config/locales/en.yml`: the localized Inclamo onboarding heading; existing domain logic and API contracts are unchanged.

`body.inclamo-app-theme` owns dashboard application tokens, including teleported controls. `body.inclamo-dashboard-theme` owns account workspace geometry. The separate v3 authentication entry imports the same tokens and honors its native HTML/root dark class. Installation administration and onboarding share the existing standalone layout, with `body.inclamo-administration`. The public widget, portal and survey do not import staff structure. Default product logos are local; merchant-configured logos and channel colors remain configured by their native mechanisms. On a fresh installation the default public product footer also says Inclamo; merchant layout and colours remain independent.

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
| Font | Approved prototype Inter variable font, served locally; user font-size preference preserved |
| Control / panel / dialog radius | 6 / 12 / 14px at 16px root |
| Default sidebar / condensed list / customer panel | 218 / 294 / 285px at desktop default font size |

The compatible dark appearance uses navy surfaces, pale ink and sky controls. Status/error colors remain semantic. No fabricated AI state, online-agent count or demo customer is rendered in the product. Native channel tools, account switching, sidebar resizing, expanded conversation lists and mobile drawers remain available.

## Component ownership and dependencies

The copied components are regular application source, following shadcn-vue’s distribution model. `Button.vue` and `Input.vue` keep the native public API and delegate their primitive rendering to these sources. Owned status/reply tabs, queue dropdowns and order badges use the same components directly. Messaging, routing, permissions, resizing, commerce actions and native dialogs retain their existing implementation.

Pinned runtime additions match the approved prototype: `reka-ui@2.11.0`, `class-variance-authority@0.7.1`, `clsx@2.1.1`, `tailwind-merge@2.6.0`, and `lucide-vue-next@0.468.0`. Tailwind colour names are scoped with `ui-` to avoid changing merchant-facing utilities. `ui/registry.json` records original prototype hashes; adaptation and formatting are intentional. Upgrading these sources is an explicit code change, not a runtime download.

Desktop geometry uses: 61px workspace header, 218px navigation, 294px condensed conversation list, 285px customer pane and 14px outer right/bottom spacing. The compact editor retains native resizing. The actual application displays its real channel/navigation options and customer data; reference-only AI widgets and online-agent counts are not fabricated.

## Validation and upgrades

Assemble the pinned CE tree with `scripts/assemble.sh <isolated-target>`; build the ordinary upstream Dockerfile. Each patch must apply cleanly in order. Never edit generated `build/chatwoot` as the source of truth.

Run owned/native component checks and `node scripts/check-ui-strings.mjs`. Run `HELPDESK_IMAGE=<image> sh e2e/theme/run.sh --update-snapshots` in a disposable installation, visually review the resulting `inclamo-*.png`; subsequent regression runs omit snapshot updates. The default suite is `inclamo-product-design.spec.mjs`; `THEME_LEGACY=1` selects the historical Twenty suite for paired measurements against an older image. Fixtures, accounts, passwords and Shopify responses are synthetic; the Docker network is internal. Existing installations are not reseeded.

Coverage includes actual replies, private notes and attachments, drafts, order-action refusals and permissions, contacts, reports, settings, authentication/admin, keyboard, dark/auto, larger fonts, mobile/RTL and public boundaries. Compare reachable gzip assets and five warm conversation/dialog interactions with the previous build. Investigate growth above 32 KiB CSS, 16 KiB JavaScript, or an interaction median increase above max(10%, 50ms). Do not accept screenshots solely because the snapshot tool updated them.

No data migration is needed. Deploy the checked product image through the existing installation process; rollback is the preceding image. Mobile APIs are unchanged, so future iOS/Android applications remain possible. The web presentation itself is not a native mobile implementation.


## Additional native seams

Application entry points and server layouts activate the owned scope. Sidebar components carry the logo and retain native navigation/account controls. Conversation hooks distinguish list, header, message, editor and customer presentation without new state. Shared button/input and context-menu hooks support contrast; existing props/events remain intact. Settings/contact layout hooks carry the same frame into secondary screens. The controller and installation locale/view changes replace only default staff identity.

- `app/controllers/dashboard_controller.rb`
- `app/javascript/dashboard/App.vue`
- `app/javascript/dashboard/components-next/Contacts/ContactsListLayout.vue`
- `app/javascript/dashboard/components-next/Conversation/ConversationCard/UnreadBadge.vue`
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
- `app/javascript/dashboard/components/buttons/ResolveAction.vue`
- `app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue`
- `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue`
- `app/javascript/dashboard/components/widgets/conversation/ConversationSidebar.vue`
- `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`
- `app/javascript/dashboard/components/widgets/conversation/contextMenu/menuItem.vue`
- `app/javascript/dashboard/routes/dashboard/Dashboard.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/ConversationView.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue`
- `app/javascript/dashboard/routes/dashboard/settings/SettingsHeader.vue`
- `app/javascript/dashboard/routes/dashboard/settings/SettingsWrapper.vue`
- `app/javascript/entrypoints/superadmin.scss`
- `app/javascript/v3/App.vue`
- `app/javascript/v3/views/login/Index.vue`
- `app/views/installation/onboarding/index.html.erb`
- `app/views/layouts/super_admin/application.html.erb`
- `app/views/super_admin/application/_brand.html.erb`
- `app/views/super_admin/application/_standalone.html.erb`
- `config/installation_config.yml`

## Reference-fidelity correction seams (0008)

- `package.json`
- `pnpm-lock.yaml`
- `tailwind.config.js`
- `app/javascript/dashboard/components-next/button/Button.vue`
- `app/javascript/dashboard/components-next/input/Input.vue`
- `app/javascript/dashboard/components/ChatList.vue`
- `app/javascript/dashboard/components/ChatListHeader.vue`
- `app/javascript/dashboard/components/widgets/ChatTypeTabs.vue`
- `app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue`
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`
- `app/javascript/dashboard/components-next/sidebar/SidebarGroup.vue`
- `app/javascript/dashboard/components-next/sidebar/SidebarGroupLeaf.vue`
- `app/javascript/dashboard/components-next/sidebar/SidebarAccountSwitcher.vue`
- `app/javascript/dashboard/components/widgets/conversation/ResizableEditorWrapper.vue`
- `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue`
- `app/javascript/dashboard/components-next/message/Message.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/contact/ContactInfo.vue`
- `app/javascript/dashboard/components/widgets/WootWriter/ReplyTopPanel.vue`
- `app/javascript/dashboard/components-next/Conversation/SidepanelSwitch.vue`
- `app/javascript/dashboard/routes/dashboard/conversation/ConversationView.vue`
- `app/javascript/dashboard/routes/dashboard/inbox/InboxView.vue`
- `app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue`
- `app/javascript/dashboard/components/widgets/conversation/ConversationBox.vue`
- `app/javascript/dashboard/components-next/message/MessageMeta.vue`
- `app/javascript/dashboard/components-next/avatar/Avatar.vue`
- `app/javascript/dashboard/components/widgets/conversation/specs/ResizableEditorWrapper.spec.js`


## Demo composition transfer

`0009-prototype-composition.patch` connects owned presentation components under `inclamo/workspace/` to native navigation descriptors, permission checks, Vuex getters and conversation handlers. Its navigation uses the approved Inbox/queues/Customers/Knowledge/Channels composition. All other permitted routes, custom views and segments remain reachable through Workspace tools. Query-linked queue changes are checked against the native permission-derived queue list.

Conversation rows keep native selection, bulk selection, context menus, preview formatting, SLA and assignee/priority data. The message timeline gains an actual subject (or localized contact fallback), date dividers and delivery metadata outside message bubbles. Removing the empty auto-margin history loader lets short conversations start at the top. Pagination, scroll handling, rich content and the existing editor remain native.

Details contains the customer profile, real commerce metrics, conversation labels and the first expanded order. Manage retains native assignment, macros, attributes, notes, files and previous conversations. Customer actions expand inline, keeping native dialogs free of an enclosing dropdown focus trap. Order actions and store management are explicit disclosures; their existing permissions, refusals, loading states and mutation handlers remain intact.

`theme/_reference.scss` transfers the relevant prototype rules into owned component scope and maps its palette to existing light/dark tokens. It does not load the prototype application or its simulated data. There is no iframe, second frontend application, React runtime or separate data store.
