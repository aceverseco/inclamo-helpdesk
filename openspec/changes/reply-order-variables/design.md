## Context

See proposal.md for motivation. Facts checked in Chatwoot v4.19.1:

- Outgoing message content is rendered as a Liquid template on create (`Liquidable#message_drops`: `contact`, `agent`, `conversation`, `inbox`, `account`). This runs for agent replies, macro messages and automation messages alike. Unknown variables render as empty text.
- The dashboard resolves variables on its side first: the variable list is built from the constant `MESSAGE_VARIABLES` plus the account's custom attributes (`VariableList.vue`), values come from `getMessageVariables` of `@chatwoot/utils` (`editorHelper.js`), and the editor warns about variables that have no value before sending.
- The order panel already ties one order to a conversation and reads it through `OrderReader` with a 60-second cache per account and customer.

## Goals / Non-Goals

**Goals:** readable names; one source of values on the server; fresh values at send time; no second copy of order data in the database.

**Non-Goals:** variables in automation rules (needs the ordering work of `store-data-rules`); the customer's "last order" as a fallback; address variables; localisation of status words.

## Decisions

**D1. The server is the source of values.** An `order` drop is added to the message drops through the overlay (`Message` is prepended in `custom/`). It holds the conversation and reads the order lazily, on first use, through the existing reader: the tied order when one is tied; otherwise the customer the contact is matched to (the same matcher the panel uses, with the remembered customer) and the first order of that customer's list, which the store gives newest first. Both reads share one 3-second budget (D2) and the reader's 60-second cache. A message without order variables costs no store call. Alternative rejected: writing every value as a conversation attribute on each panel read. Items and totals do not belong in attributes, and the values would be stale.

**D2. Time limit and fallback.** The read is bounded to 3 seconds in all. On a timeout or an error the drop answers from the conversation's attributes (number, statuses, tracking number, tracking link) when an order is tied — only a tied order has values written there — and returns empty text for the rest, or for everything when no order is tied. The message is never held back by the store.

**D3. The dashboard gets a registry of reply variables (seam 3).** `patches/0003-reply-variables.patch` adds `dashboard/extensions/replyVariables.js` (empty by default) and reads it in two places: the variable list, and the map of values the editor uses to resolve variables and to warn about undefined ones. Our entry supplies the order variables and, for the open conversation, their values from the panel's store (the tied order the panel already loaded). The exact second place (the caller of `getMessageVariables` in `editorHelper.js` or its caller in the reply box) is settled in task 2.1 by reading the code; the patch stays under 30 lines or the approach is re-opened.

Findings of task 2.1 (Chatwoot v4.19.1):

- The list: `VariableList.vue` builds its items from `MESSAGE_VARIABLES` plus the account's custom attributes. It is the one list for every editor that offers variables (reply box, saved replies, macros), so one change there covers all three.
- The values: `getReplyVariables` in `editorHelper.js` is the single builder of the map; the reply box (`messageVariables`) and the forward-email panel call it and nothing else does. The map serves three uses: the value shown in the list, the replacement on insert (`resolveVariableText`: a variable with a value becomes text, one without stays `{{…}}` for the server), and the warning before sending (`getUndefinedVariablesInMessage` of `@chatwoot/utils`: a placeholder is undefined when its key is **absent** from the map; a key with an empty value is not).
- So the patch touches two core files: `VariableList.vue` (entries of the registry join the list) and `editorHelper.js` (`getReplyVariables` merges the registry's values), plus the new registry file. About 20 lines.
- What follows for our entry: a known order (tied, or the first of the panel's list of the matched customer) → keys with values (replaced in the editor); the panel read and found neither → no keys (the editor's own warning names them); the panel not read yet, or a value the order does not have → keys with empty values (the placeholder stays, no warning, the server fills it on send). Before the panel is read the dashboard cannot know whether the customer has orders, so it does not warn; the server decides.
- The panel keeps its state inside `OrdersSection.vue`; there is no shared store yet. Task 3.2 adds a small reactive module that the section writes what it loaded into, and the registry entry reads. Whether a store is connected is read from `GET …/inclamo/shopify/connection`, which every member may call.
- The values the dashboard shows are computed on the server by the same code as the drop and travel in the panel's answer (`variables` on `marked_order` and on every order of the list), so the two sides cannot format a date, a total or the items differently.

**D4. Client value and server value may differ.** The dashboard resolves a variable from what the panel loaded; the server would have read a fresher value. Since the dashboard replaces the variable before sending, the agent sends what they saw in the editor. Only macro messages are rendered on the server. This is intended: the agent's text is never changed after they pressed send.

**D5. Status words** come from one shared table used by both the panel and the drop (the panel's English strings), so the two cannot drift.

**D6. How the values are written** (settled while implementing; the spec names the variables, not their notation). One class, `OrderVariables`, computes them for both sides. `order.date` is the day the order was placed in UTC, written `November 5, 2026`: the helpdesk does not know the store's time zone, and a browser-local date would differ between the agent's editor and a macro. `order.total` is `1,585.90 UAH`: the amount with the decimal places of its currency, then the ISO code; a currency sign would need a locale the server does not have. `order.items` is one line per item, `2 × Blue Mug`. `order.tracking_number` and `order.tracking_link` are those of the first shipment, the same the conversation attributes carry. `order.status_link` is the store's `statusPageUrl` of the order, a new field of the `OrderFields` fragment; no new scope.

**D7. Which connection counts.** The variables are offered while the connection is working. With a broken connection they are not offered, and a message that names them takes the last known values (D2). In an account with no connection they render as empty text even when a conversation still carries attributes of an earlier connection.

## Risks / Trade-offs

- [A third patch to carry] → same build gate as the other seams: the image build stops when it does not apply, and Chatwoot's own tests around the patched files run in CI.
- [A store call inside message creation] → lazy, cached, bounded to 3 seconds, with the attribute fallback.
- [`@chatwoot/utils` changes how variables are resolved] → the patch touches Chatwoot's own files, not the package; a component test pins the behaviour.
