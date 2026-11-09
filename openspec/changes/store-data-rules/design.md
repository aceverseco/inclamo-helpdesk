## Context

See proposal.md for motivation. Facts checked in Chatwoot v4.19.1:

- Automation conditions accept any custom attribute that has a definition in the account (`AutomationRule#json_conditions_format`, `ConditionsFilterService#custom_attribute`). The rule editor lists them without a patch, but offers a number "equal to" and "not equal to" only and a text no "contains" (`automationHelper.js#getOperatorTypes`), though the server compares both ways (found in task 3.3; see D11).
- Rules of a new conversation are evaluated in `AutomationRuleListener#conversation_created` and `#message_created`, inside the asynchronous event job, not in the web request.
- Our overlay already creates definitions for the six order attributes (`ConversationOrder.ensure_definitions!`) and ties an order named in the first message.

## Goals / Non-Goals

**Goals:** rules use store data without a second rule engine; the order of "facts first, rules second" is guaranteed, not likely; presets are plain Chatwoot rules.

**Non-Goals:** store events as rule triggers (needs Shopify webhooks, a later change); a rule builder of our own; conditions on line items.

## Decisions

**D1. Facts are conversation attributes with definitions.** Keys: `shopify_customer_orders` (number), `shopify_customer_spent` (number), `shopify_customer_tags` (text, comma-separated), `shopify_is_customer` (list: yes, no), `shopify_last_order_payment_status`, `shopify_last_order_fulfillment_status` (text), `shopify_last_order_total` (number), `shopify_last_order_tags` (text). Conversation, not contact: a rule evaluates the conversation, and facts on the contact would go stale silently between conversations. Alternative rejected: contact attributes, because contact conditions in rules are limited to Chatwoot's built-in contact fields.

**D2. Enrichment runs inside the automation listener.** The overlay prepends `AutomationRuleListener`: before `conversation_created` and the first `message_created` of a conversation are processed, it matches the customer, writes the facts and ties the order named in the message, then calls the original method. This is the only place where "before the rules" is a guarantee. It runs in the background job, so the web request is not slowed. Bounded to 5 seconds; on timeout or error the original method runs without facts. The attribute write is done without publishing a `conversation_updated` event of its own, so it cannot start a second round of rules.

**D3. One store call.** The customer search already returns order count and total spent; the query is extended with tags and the latest order's statuses, total and tags. The result fills the panel's cache, so the agent's first panel read is free.

**D4. Number operators.** Task 1.1 confirms on the stand that "greater than" works on number-type custom attributes in conditions; if Chatwoot's filter does not support it for custom attributes, the design is re-opened before any code.

**D5. A preset is a rule with a marker.** Switching on creates an `AutomationRule` whose description ends with a marker line (`inclamo-preset: vip`). The page finds its rules by the marker. Off means `active: false`. No table of our own; the administrator's edits to conditions and actions survive.

**D6. Labels used by presets are created on first use** (`vip`, `awaiting-shipment`, `pre-sale`), because a rule's "add label" needs the label to exist.

**D7. The facts are customer data at rest, and the order panel's spec says so.** `conversation-order-panel` allowed only the six attributes of the marked order to be stored (its D6, "nothing at rest"). A rule can only compare what is on the conversation when Chatwoot's filter runs, so the eight facts have to be stored; the founder accepted this on 2026-11-06 and the requirement is modified in this change. What keeps the exception narrow: counts, amounts, statuses and tags only, never a name, email, phone or address; nothing in a table of our own; a contact that matches several customers gets no facts at all. The order panel's check "a read writes nothing to the database" becomes "a read writes nothing but the conversation's attributes and their definitions".

**D8. Two kinds of write.** Before the rules (D2) the facts and the tied order are written quietly: no validation callbacks, no `conversation_updated` event. When the panel reads the customer they are written the ordinary way, like the marked order's attributes: the dashboard and rules for updated conversations see the change. Both go through one writer that locks the conversation's row and reads it again, because the events of one conversation are processed in parallel and each holds its own copy of the attributes.

**D9. The earlier auto-tie stays.** `Inclamo::OrderMarkListener` and its job still run after the listeners of the first message. When the tie before the rules succeeded they find the order tied and do nothing; when the store was too slow for the 5-second limit they tie it a moment later, so the agent still gets the order though the rules did not.

**D10. Definitions for accounts connected earlier.** The eight definitions are created when a store is connected and, for accounts connected before this change, by the first write of facts (one query when they all exist).

**D11. Seam 5: the operators of a custom attribute in the rule editor.** Decided by the founder on 2026-11-06, when the editor turned out to offer no "greater than" for a number attribute and no "contains" for a text one: without them an administrator could build a rule on total spent or on tags only through a preset. `patches/0005-rule-operators.patch` adds `dashboard/extensions/ruleOperators.js` (an empty list of functions `definition => operators`) and asks it in the one place where `automationHelper.js` picks the operators of a custom attribute. One core file touched by a few lines, one file added. Our entry answers only for the attributes the overlay keeps (keys starting with `shopify_`): a number gets Chatwoot's own list with "greater than" and "less than", a text the list with "contains" and "does not contain"; the lists are Chatwoot's, so the labels are too. The account's own attributes keep Chatwoot's behaviour, and Chatwoot's test of the helper passes unchanged. Number 0004 belongs to `macro-order-actions`.

## Risks / Trade-offs

- [The listener prepend depends on Chatwoot's method names] → a spec fails when the methods are renamed; the upgrade routine runs it.
- [A slow store delays rules by up to 5 seconds] → bounded; rules are background work. The same job carries the event to Chatwoot's other listeners (webhooks, notifications), which wait as long.
- [A channel that creates the conversation and its first message in two steps] → the rules of "conversation created" run before the message exists, so the order it names is tied only for the rules of "message created". Channels that create both at once (website widget, email) are not affected.
- [Total spent is compared with "greater than"; Chatwoot has no "at or above"] → a customer who spent exactly the amount does not match; the VIP preset says "spent more than".
- [A fifth patch to carry] → same build gate as the other seams: the image build stops when it does not apply, and Chatwoot's own test of the patched helper runs in CI.
- [An administrator deletes the marker line] → the preset shows as off and switching it on creates a second rule; the page says so next to the switch.
