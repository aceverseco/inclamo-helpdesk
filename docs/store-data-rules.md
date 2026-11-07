# Store data in automation rules

Chatwoot's automation rules can act on what your Shopify store knows about the
customer: "this customer spent more than 500, give the conversation high
priority and the senior team". The helpdesk writes a few facts about the
customer on every new conversation, and the rule editor offers them as
conditions next to Chatwoot's own.

They are there only when a store is connected and its connection works.

## The conditions

In **Settings → Automation**, add a rule and pick one of these in the list of
conditions (they are at the end, among the conversation's custom attributes):

| Condition | What it holds | Comparisons | Example |
| --- | --- | --- | --- |
| Is a customer of the store | `yes` or `no` | equal to, not equal to | `no` |
| Customer's number of orders | a number | equal to, not equal to, is greater than, is lesser than, is present, is not present | `3` |
| Customer's total spent | a number in the store's currency | the same as above | `620` |
| Customer's tags | the customer's tags in the store, in one text separated by commas | equal to, not equal to, contains, does not contain, is present, is not present | `wholesale` |
| Latest order's payment status | one word, see below | the same as for tags | `paid` |
| Latest order's fulfilment status | one word, see below | the same as for tags | `unfulfilled` |
| Latest order's total | a number in the store's currency | the same as for the number of orders | `185` |
| Latest order's tags | the order's tags in one text separated by commas | the same as for tags | `gift` |

The latest order is the one the customer placed last.

**Payment status** is one of `pending`, `authorized`, `partially_paid`,
`paid`, `partially_refunded`, `refunded`, `voided`, `expired`.

**Fulfilment status** is one of `unfulfilled`, `partially_fulfilled`,
`fulfilled`, `restocked`, `pending_fulfillment`, `open`, `in_progress`,
`on_hold`, `scheduled`, `request_declined`, `fulfillment_not_required`.

Things worth knowing when you write a condition:

- **"Is greater than" means more than, not "at least".** A rule on "total
  spent is greater than 500" does not match a customer who spent exactly 500.
- **Amounts have no currency sign.** Write `500`, not `500 EUR`; the number is
  compared with the amount in your store's currency.
- **Text is compared without regard to capitals.** "Contains wholesale" finds
  the tag `Wholesale` too. It also finds `wholesale-eu`: "contains" looks for
  the letters anywhere in the list of tags.
- "Is greater than", "is lesser than" and "contains" are offered for these
  conditions only. Custom attributes of your own keep the comparisons Chatwoot
  gives them.

## When the facts are written

- **On a new conversation**, before its automation rules run: for the rules
  of "Conversation Created" and, with the customer's first message, for those
  of "Message Created".
  An order the customer names in the first message is tied to the conversation
  at the same moment, so a rule's message can say `{{order.number}}` (see
  [order variables](order-variables.md)).
- **Whenever an agent opens the Orders panel** of the conversation, the facts
  are refreshed.

They are not refreshed on every message. A rule for "Conversation Updated" or
a later message sees the facts as they were last written.

The customer is found the same way as in the Orders panel: by the contact's
email, then by phone.

| The contact | The facts |
| --- | --- |
| matches one customer of the store | all of them; the four about the latest order only when the customer has an order |
| matches nobody | "Is a customer of the store" is `no`, nothing else |
| matches several customers (a shared phone number) | none, until an agent picks the customer in the Orders panel |

A channel that creates a conversation first and its first message a moment
later (the API channel can do that) runs the rules of "Conversation Created"
before the message exists: the order named in it is tied for the rules of
"Message Created". The website widget and email are not affected.

## When the store does not answer

The store gets five seconds. After that the conversation is created as usual
and the rules run without the facts: a rule on them does not fire, every other
rule does. Nothing is retried for the rules; the facts appear when an agent
opens the Orders panel.

## Stores in the limited mode

When Shopify hides customer data from the app the store is connected with
(see [connecting a store](connect-shopify.md)), no facts about the customer
are written, and rules on them do not fire.

## What is kept

The facts are kept on the conversation as custom attributes, so that
Chatwoot's rules can compare them: counts, amounts, statuses and tags. A name,
an email address, a phone number or an address is never among them.

## Preset rules

**Settings → Preset rules** (administrators only) has three ready-made rules.
Each has a switch:

| Preset | When it acts | What it does | You enter |
| --- | --- | --- | --- |
| VIP customers first | the customer spent more than the amount | high priority and the label `vip` | the amount |
| Order not shipped yet | the customer's latest order is `unfulfilled` | the label `awaiting-shipment` | nothing |
| No orders yet | the contact is not a customer of the store, or is one who has not ordered yet | the label `pre-sale` | nothing |

All three act on a new conversation.

- **Switching one on** creates an ordinary rule in Settings → Automation, with
  the labels it needs. You can open it there and change its conditions and
  actions like any other rule.
- **Switching it off** deactivates that rule and keeps your changes. Switching
  it on again activates the same rule.
- **Changing the amount** of the VIP preset on this page changes the number in
  the rule's own condition and nothing else.
- A rule belongs to its switch by the last line of its description
  (`inclamo-preset: vip`). If you remove that line, the switch shows as off and
  switching it on creates a second rule.
