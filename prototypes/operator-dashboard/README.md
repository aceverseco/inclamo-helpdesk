# Inclamo operator workspace · shadcn-vue prototype

A single interactive inbox screen for evaluating a stronger visual direction for Inclamo Helpdesk. Built on Vue 3.5 and Tailwind 3, matching the existing Chatwoot frontend's framework and CSS generation. This is an isolated design prototype, not a production Chatwoot integration.

The accepted layout now uses Inclamo branding: navy `#101B3D` for ink and navigation, sky blue `#91C8F5` for controls, orange `#FF6A00` for selective accents, and white main surfaces. Lighter fills and darker text variants keep controls readable. Shared palette values live in `src/style.css`; shadcn-vue theme variables use the same colours. `public/inclamo-logo.svg` is an unchanged copy of `/Users/user/Documents/inclamo.com/docs/inclamo_logo.svg` and serves as both the application logo and favicon.

## Open

```sh
cd /Users/user/Documents/inclamo-helpdesk/prototypes/operator-dashboard
pnpm install --frozen-lockfile
pnpm dev
```

Visit http://127.0.0.1:5190/. For a portable preview, run `pnpm build`, then open `dist/inclamo-inbox-preview.html` in a browser. The portable file embeds its JavaScript, stylesheet, font and logo, and needs no server or internet connection.

## What works

- Queue, channel, unread and priority filters; conversation search and sorting.
- Conversation selection with separate reply and private-note drafts per conversation.
- Local replies and notes, assignment, priority, snooze and resolve/reopen state.
- Customer details, order history, shipping-address review, tag editing.
- Copilot tab with explicitly labelled example suggestions and editable drafts.
- Saved replies, emoji insertion and local attachment-name previews.
- Responsive inbox/conversation views and customer drawer; keyboard search and send shortcuts.

All people, orders and policies are fixtures. Changes live only in memory and reset on refresh. Reply sending, attachment transfer, AI inference, Shopify mutations and timed snooze wake-ups are not connected to services. Snooze moves a conversation into the snoozed queue. No customer information leaves the preview.

## Structure

- `src/components/ui/`: actual shadcn-vue New York components downloaded from its official registry. `shadcn-registry.json` records sources and source hashes. MIT notice in `LICENSE.shadcn-vue`.
- `src/components/`: workspace navigation, conversation list, conversation/composer, customer panel, shared avatar and tooltip button.
- `src/App.vue`: composition and temporary UI state. `src/lib/demo.ts`: synthetic conversation fixtures.
- `src/style.css`: visual design and responsive layout. Self-hosted Inter font; Lucide icons.
- `scripts/create-preview.mjs`: portable artifact generator; does not replace the Vue sources.

The main Helpdesk dependencies, existing theme patches, backend, routes and completed OpenSpec change are untouched. A production integration should port the approved presentation to native Chatwoot Vue components and existing stores/action handlers, with regression checks for real inbox actions. It should not retain this separate mock application, introduce React, or replace Chatwoot state with fixture state.

## Verify

`pnpm build` runs TypeScript checking and the production build. With the local preview running and Google Chrome installed, `pnpm check:browser` exercises nine groups of user-facing interactions and captures desktop/tablet/mobile screenshots in `evidence/`. `BROWSER_CHANNEL` and `PREVIEW_URL` can override the browser and preview location.

This is design validation, not Chatwoot integration, production performance, native mobile, or a complete accessibility certification. Mobile screenshots demonstrate responsive web behavior only.
