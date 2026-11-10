## Context

The approved reference is `prototypes/operator-dashboard`, including its branded desktop/mobile evidence. See proposal.md for motivation. Chatwoot CE v4.19.1 already supplies Vue 3.5, Tailwind 3, local Inter, Lucide icons, native menus/dialogs and working conversation state. The earlier Twenty theme is owned code plus patch 0006. CONTRIBUTING.md requires owned implementation and small recorded seams; existing uncommitted features must survive.

## Goals / Non-Goals

**Goals:** reproduce the reference's brand, surface hierarchy, navigation, conversation rows, editor and customer-card treatment in native screens; cover all staff routes through shared primitives and explicit shell hooks; preserve behavior and build compatibility.

**Non-Goals:** importing prototype fixtures or its parallel application into production; replacing Vuex/Pinia, ProseMirror, routing, commerce actions or feature entitlements; adding unsupported AI functionality; modifying sibling CRM/Builder repositories; deploying to production without an identified deployment target.

## Decisions

1. **Native component presentation, shared tokens.** Adapt the existing Button/Input/TabBar/Dialog/menu and legacy control seams to the accepted shadcn-vue visual language. Retain their props, events, disabled/loading behavior and focus management. The alternative of replacing every component with a second implementation would add risk without improving the approved appearance. No new runtime/library dependency is necessary.
2. **Own the design in the overlay.** Keep palette, structural styles and any small presentational brand/header components under `dashboard/inclamo/`. Add stable class/data hooks at native layout boundaries instead of matching generated utility strings or manipulating rendered DOM. Document every upstream file touched by the additional presentation patch. Build from a separate assembled tree so the source-of-truth overlay and unrelated changes remain intact.
3. **Separate app and workspace scopes.** The dashboard application entry owns the staff-wide token scope, including authentication and teleported menus. The account workspace owns layout classes. Installation administration imports the same palette through its own entry/layout. Customer widget/portal/survey entry points do not import staff structure. Existing explicit dark/automatic preferences remain; the approved default light canvas is white.
4. **Brand assets are local and preserved.** Copy the supplied SVG unchanged as the mark; use owned wordmark composition where needed. Replace default CE logo assets/brand defaults at documented seams, without changing customer portal logos or merchant widget configuration. Preserve appropriate attribution/licence material.
5. **Layout changes retain capabilities.** Navigation retains native permission and feature filtering, account switching, resizing and mobile launch. Conversation list selection, unread state, lists and virtual scrolling remain native. Composer and message templates receive presentation hooks, preserving channel tools, notes and attachments. Customer/order sections use existing data/handlers; no fictional statistics or AI suggestions are introduced.
6. **Product acceptance, not only prototype acceptance.** Reuse the isolated synthetic Shopify/Rails/Playwright harness. Extend screen coverage to contacts, reports, settings and authentication/admin. Retain real reply/note/action checks, mobile/RTL and appearance checks. Review screenshots, record production assets and warm interaction samples; investigate unexplained increases above 32 KiB gzip CSS, 16 KiB gzip JS, or the larger of 10%/50ms in measured interactions.

## Risks / Trade-offs

- Broad presentation changes can expose legacy exceptions → inventory shared controls and include legacy settings/auth/admin in visual checks.
- Sky-blue controls need dark text and clear focus → separate fill, text, accent and focus tokens; verify enabled/hover/focus/error states.
- Narrow layouts and stored sidebar widths can conflict with the reference → preserve native responsive/collapse controls and test actual drawers and sending.
- Existing dark preference differs from the white reference → supply a compatible navy dark palette while keeping preference ownership native.
- Upstream changes can invalidate seams → fail assembly on patch conflicts and maintain a concrete patch inventory and regression commands.

## Migration Plan

No schema or data migration. Assemble and build the ordinary CE-plus-overlay product, validate using disposable synthetic accounts, then expose the checked installation for review. Existing production deployments are not replaced implicitly. Rollback uses the previous image and requires no data repair. Keep the approved prototype and completed Twenty change as historical references.
