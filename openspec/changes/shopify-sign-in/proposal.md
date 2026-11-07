## Why

A merchant's team already signs in to Shopify every day; a second password for the helpdesk is one more thing to forget and to share. ADR 0070 puts both Shopify ways in into the hosted release: the store connected by Shopify OAuth (`shopify-oauth-connection`) and the team signing in to the helpdesk through Shopify. This change is the second: a person signs in with their Shopify staff account, and opening the app from the Shopify admin lands them in the helpdesk already signed in.

## What Changes

- **"Sign in with Shopify" on the login page**, above the email and password form, when the instance's store is connected through our Shopify app. No shop field: the store is the connected one. Password sign-in stays as it is.
- **Shopify says who the person is.** The button sends the browser through Shopify's authorization for one staff member (an online access token, `grant_options[]=per-user`). The helpdesk reads the staff member Shopify names, then throws the token away: it is never stored, never logged and never used to call Shopify.
- **Only people who already are users of the store's helpdesk account get in**, and only when Shopify has verified their email. Anyone else is refused with words on the login page. No user and no account is ever created this way, whatever the instance's sign-up setting; Chatwoot's own OAuth sign-in would create one.
- **The helpdesk session is Chatwoot's own**, made by the same one-time link Chatwoot uses after Google sign-in, so it has Chatwoot's lifespan, session limit and session list, and does not end when Shopify's token does (at most 24 hours).
- **Opening the app from the Shopify admin** signs the person in and opens the store's account. The launch is received and its signature checked by `shopify-oauth-connection`; this change takes over once the store is known.
- **Every attempt is checked and recorded**: the request this browser started, Shopify's signature, the shop, the kind of token. One log line per attempt with its outcome, without email, name, token or code. Starts and callbacks are rate limited per address.
- **One new seam in Chatwoot's login page**: a list of extra sign-in methods that the overlay fills (a patch under ADR 0067). Chatwoot's own error messages are not touched; the button shows ours.
- **A stand-in for Shopify's authorization** in the end-to-end proxy, so every scenario runs without a real Shopify login; the real consent screen is checked once by hand on a development store.

Not in this change: the Shopify app itself, its configuration, its secret, the store's install and offline token, the launch handler and uninstall (all `shopify-oauth-connection`); inviting people from the Shopify staff list; mobile apps; the Chatwoot super admin console.

## Capabilities

### New Capabilities
- `shopify-sign-in`: who can sign in to the helpdesk with a Shopify staff account, from the login page and from the Shopify admin, what they see when refused, and what the helpdesk keeps and logs about it.

### Modified Capabilities
- none.

## Assumptions for the founder

1. **Only a store connected through our app gets the button.** A store connected with the merchant's own app credentials (the path of `shopify-order-panel`) has no "Sign in with Shopify": its app is the merchant's, not ours.
2. **Only existing users of the account get in.** An email the account does not know is refused with "ask an administrator to invite you"; nobody is invited or created automatically, the store owner included, and the owner gets no role from being the owner.
3. **Collaborator accounts are refused this way** (agencies, developers who reach the store as collaborators), even when their email matches a helpdesk user. They use the password.
4. **A user who turned on two-factor authentication in the helpdesk is refused this way** and uses the password and code. Chatwoot's one-time sign-in link does not ask for the code, so allowing it would quietly switch the helpdesk's second factor off for that person.
5. **An invited user who has not accepted yet may accept by signing in through Shopify**, when Shopify has verified the same email. Chatwoot does the same after Google sign-in.
6. **No switch to turn this way in off.** It is on whenever the store is connected through the app; disconnecting the store turns it off.
7. **Removal from the Shopify store ends this way in at the next attempt.** The helpdesk does not end sessions already open and does not remove the user; an administrator removes them in the helpdesk.
8. **One store per login page.** On an instance where more than one account is connected through the app, the login page shows no button: it would have to ask for the store or list them. Opening the app from each store's Shopify admin still works.

## Impact

- Backend: two routes under `/inclamo/shopify/sign_in` outside the account API (availability, start), the `sign_in` purpose of the app's one callback, the launch handler for a connected store, a sign-in service, a Redis record per started attempt (no table, no migration), a per-address counter of attempts in Redis, three more filtered parameters.
- Dashboard: a "Sign in with Shopify" component on the login page through a new seam (patch `login-methods`, number taken when built).
- Depends on `shopify-oauth-connection`: the app's client id and secret, its one callback and state store, its checks of the shop and signature, the store connection made through the app (`auth_kind: shopify_app`), the launch handler's seam.
- Shopify: no new redirection URL and no new scope.
- Tests: request and model specs, component tests, end-to-end tests against a stand-in for Shopify's authorization; one manual check on a development store with a real staff account.
