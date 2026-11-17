# App storefront chat contract, version 1

How a store app (a Shopify app run by the operator of a hosted helpdesk) gives
a store its chat on the storefront. The helpdesk makes a website inbox for the
store together with its account and tells the app the two public values the
chat widget needs; the app shows the widget through its own theme app
extension, and the merchant turns it on with one Save in the theme editor.
Nobody pastes a script into a theme.

Version 1. It extends `app-provisioning.md`: the store must already have an
account made through that contract, and every request here is signed exactly
as described there (§2). This document is written before the helpdesk's side
is implemented: until the revision note in §9 says otherwise, nothing here is
live.

```
 Merchant (Shopify admin)     Store app                          Helpdesk
 ────────────────────────     ─────────                          ────────
 presses "Get the helpdesk" ─▶ PUT stores/{shop} ───────────────▶ creates the account and,
                              (app-provisioning.md §3)            with it, the store's
                                                                  website inbox (§2)
                              PUT stores/{shop}/storefront-chat ─▶ finds the inbox
                              ◀── website token, widget address
                              writes both where its theme
                              extension reads them (§4)
 presses "Turn on chat on
 your site", sees the chat in
 the theme editor, saves (§5)
                                                                  Shopper opens the store:
                                                                  the embed loads the widget
                                                                  from the helpdesk (§4)
```

What the helpdesk does not do: it does not touch the theme, does not know
whether the embed is on, and sends no widget settings through the app. The
widget's appearance, greeting, hours and forms are set by the merchant's team
in the helpdesk and reach the storefront on the widget's next load.

## 1. The calls

Under the helpdesk's public address, over HTTPS, on installations that have
provisioning (`app-provisioning.md` §1):

| Call | Purpose |
|---|---|
| `PUT /inclamo/provisioning/stores/{shop_domain}/storefront-chat` | The store has its storefront inbox: find it, or create it when there is none (§2) |
| `GET /inclamo/provisioning/stores/{shop_domain}/storefront-chat` | What is there (§3) |

Headers, signature, request id, retries and the `401` answer are those of
`app-provisioning.md` §2. The signed `path` is the full path above.

## 2. The store has its storefront inbox

### 2.1 When the inbox is made

- **With the account.** When `app-provisioning.md` §3 answers `created`, the
  new account already has its storefront inbox, with `https://{shop_domain}`
  as its website address. That call's request and answer are unchanged and do
  not mention the inbox; the app sends the `PUT` below to learn the token and
  is answered `existed`.
- **By the `PUT` below**, when the account has none: the team deleted it (§6),
  or the account answered `existed` or `restored` and has no storefront inbox.
  The helpdesk never makes a second one by itself.

### 2.2 The request

```
PUT /inclamo/provisioning/stores/example-store.myshopify.com/storefront-chat
Content-Type: application/json

{
  "contract": 1,
  "storefront_url": "https://example-store.com"
}
```

| Field | Required | Meaning |
|---|---|---|
| `contract` | yes | `1` |
| `storefront_url` | no | The store's public storefront address, absolute and HTTPS. Only its origin is kept. Used only when this request creates the inbox; without it `https://{shop_domain}` is used. Ignored when the inbox exists |

### 2.3 The answers

`201` when this request created the inbox, `200` when it existed:

```
{
  "contract": 1,
  "inbox_id": 7,
  "website_token": "wT3xExampleExampleExample",
  "widget_base_url": "https://helpdesk.example.com",
  "state": "active",
  "outcome": "created"
}
```

| `outcome` | Status | What happened |
|---|---|---|
| `created` | `201` | The account had no storefront inbox. A website inbox named after the account now exists, with the given address; the account's administrators are its members |
| `existed` | `200` | The store already has its storefront inbox (the usual answer after §2.1). Nothing was created and **nothing of it was changed**, whatever `storefront_url` said |

An account has one storefront inbox. Two requests arriving together answer
with the same token. Website inboxes the team created themselves are not
counted, changed or reported.

`website_token` and `widget_base_url` are **public values**: every page that
shows the widget carries them in its source. They are not secrets and need no
protection beyond not being confused with one. Nothing else of the inbox is
ever in an answer: not its identity-verification key, its settings, its
conversations, its contacts or its members.

The inbox is an ordinary website inbox of the account. The team may rename it,
change its settings, add people to it and delete it (§6).

The AI agent is meant to answer in this inbox from the start. These calls
attach no bot themselves: connecting the agent (`app-agent-connection.md`)
puts it on the storefront inbox by default, and the merchant's team turns it
off or on in the helpdesk's **AI agent** page, not in the app. Until the agent
is connected, conversations in the inbox go to the team.

### 2.4 Errors

| Status | `error` | When |
|---|---|---|
| `404` | `no_account` | The store has no account. Create it first (`app-provisioning.md` §3) |
| `409` | `account_suspended` | The store's account is suspended. Restore it first |
| `422` | `storefront_url_invalid` | `storefront_url` is present and is not absolute or not HTTPS |
| `422` | `contract_unsupported` | `contract` is not a version this installation speaks |
| `429` | `rate_limited` | With `Retry-After`. These requests count with the store's other provisioning requests |

Nothing is created on any of them.

## 3. What is there

```
GET /inclamo/provisioning/stores/example-store.myshopify.com/storefront-chat
```

`200` with the body of §2.3 without `outcome`. `state` says whether a widget
loaded now would be served:

- `active`: the account is active.
- `suspended`: the account is suspended; the inbox and its token are kept, and
  the widget is refused until the account is restored.

`404 {"error":"no_storefront_chat"}` when the account has no storefront inbox
(never made, or deleted by the team). `404 {"error":"no_account"}` when the
store has no account.

## 4. Showing the widget from a theme app extension

The widget needs exactly the two values. Chatwoot's own installation snippet
is this, and the embed does the same:

```html
<script>
  (function (d, t) {
    var BASE_URL = "{widget_base_url}";
    var g = d.createElement(t), s = d.getElementsByTagName(t)[0];
    g.src = BASE_URL + "/packs/js/sdk.js";
    g.async = true;
    s.parentNode.insertBefore(g, s);
    g.onload = function () {
      window.chatwootSDK.run({ websiteToken: "{website_token}", baseUrl: BASE_URL });
    };
  })(document, "script");
</script>
```

What the app's side builds, and what it must not do:

- **An app embed block** of a theme app extension, target `body`. Not a
  `ScriptTag`, not an edit of the theme, not an instruction to paste code.
- **The two values come from the app, not from the merchant.** After the `PUT`
  the app stores them where the block's Liquid can read them (app-data
  metafields, read through the `app` object). They are not fields the merchant
  types and not settings in the theme editor.
- **No presentation options.** Do not set `window.chatwootSettings` position,
  type, launcher title, dark mode or locale in the embed: an explicit option on
  the page overrides what the merchant's team saved in the helpdesk's widget
  editor, and they would no longer be able to change it there.
- **Only for merchants who chose this helpdesk.** Make the block available
  through `available_if` on an app-data metafield, so a merchant who uses
  another helpdesk does not find it in the theme editor.
- **Turning it on is the merchant's step** (§5). The helpdesk does not know
  whether the embed is on.
- **Do not load a widget that will be refused.** When §3 answers
  `no_storefront_chat` or `state: "suspended"`, clear the stored values or make
  the block unavailable, so shoppers' browsers do not request a script and a
  frame that answer `401`.
- **One open point for the app's side to settle first, not yet verified:** the widget script is
  loaded from the helpdesk's address, not from the extension's own assets,
  because it is versioned with the helpdesk. Shopify's documentation for theme
  app extensions describes extension assets and their size guidance and does
  not state a rule about scripts a block loads itself. Check this against
  Shopify's current review requirements before building the block; the calls
  in this contract do not depend on the answer.

For the app's listing: conversations collected through the widget are stored
in the merchant's own helpdesk account, where the merchant's team reads them.

## 5. How the merchant turns the chat on

Shopify keeps an app embed off until the merchant saves it in a theme; an app
cannot do that for them. The agreed path is three steps:

1. After the account is made, the app shows **Turn on chat on your site**.
2. The button is Shopify's deep link, which opens the theme editor with the
   embed on in preview:

   ```
   https://<myshopifyDomain>/admin/themes/current/editor?context=apps&activateAppId={api_key}/{handle}
   ```

   The merchant sees the chat on their own store and presses **Save**.
3. Back in the app the chat is shown as live. The app reads this from the
   published theme's `settings_data.json`, where an enabled embed is listed;
   that needs the `read_themes` scope, requested as an optional scope at this
   step and not from every merchant at install.

Where the path breaks:

- **The merchant switches theme.** The embed's state belongs to a theme, so it
  is off in the new one. The app sees it and offers the button again.
- **Another chat is already on the site.** There are two launchers. The app
  can only warn.
- **A storefront without a Shopify theme** (a custom front end). The deep link
  does not help; the merchant's developer uses the installation snippet from
  the inbox's settings in the helpdesk.

## 6. What can change without the app asking

- **The team edits the inbox.** Name, address, appearance, hours, forms, and
  whether the AI agent answers in it: all theirs. The token does not change.
- **The team deletes the inbox.** The token stops being served and §3 answers
  `no_storefront_chat`; a token may stop working a few seconds before §3 says
  so. The helpdesk does not make a new inbox by itself. A new `PUT` creates a
  new inbox with a **new token** and none of the earlier conversations; the app
  then replaces the stored values.
- **The account is suspended** (the app was removed, `app-provisioning.md`
  §5). The widget is refused; nothing is deleted. After restoration the same
  token serves the widget again and a returning shopper finds their earlier
  conversation.

The app asks §3 when the merchant opens the app's chat settings, and after a
restoration, to keep its stored values true.

## 7. Summary of answers

| Status | Body | Meaning |
|---|---|---|
| `200` | inbox | Existed, or status |
| `201` | inbox | Created by this request |
| `401` | `{"error":"unauthorized"}` | `app-provisioning.md` §2.3 |
| `404` | `{"error":"no_account"}` | The store has no account |
| `404` | `{"error":"no_storefront_chat"}` | `GET`: the account has no storefront inbox |
| `404` | none or Chatwoot's page | The installation has no provisioning |
| `409` | `{"error":"account_suspended"}` | `PUT` for a suspended account |
| `422` | `{"error","message"}` | §2.4 |
| `429` | `{"error":"rate_limited"}` + `Retry-After` | §2.4 |

## 8. Testing against this contract

The helpdesk's end-to-end stack's stand-in app makes both calls and serves a
page that loads the widget with the answered values. A checklist for the app's
side:

1. The `PUT` is sent after the store's account exists, expects `existed` for
   a new account, and is safe to send again.
2. The two values reach the storefront only through the app embed.
3. The embed sets no presentation options.
4. A changed token after re-creation replaces the stored one.
5. `no_storefront_chat` and `suspended` stop the embed from loading the widget.
6. The setup step links to the theme editor with the embed activated, and is
   offered again when the published theme does not have it on.
7. The block is unavailable to a merchant who did not choose this helpdesk.

## 9. Versions

`contract: 1` is this document, under the versioning rule of
`app-provisioning.md` §9.

Revision note: written 2026-11-17 as the proposed target; the helpdesk's side
is not implemented yet and the shapes are not yet agreed with an app's side.
