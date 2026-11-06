# Order steps in macros

A macro can refund, cancel or replace the order a conversation is about, in
the same click as its message, labels and status. The order steps run the
order actions of the Orders section: the same permissions, the same record and
the same private note.

## The four steps

In the macro editor (**Settings → Macros**), the list of actions holds four
more entries while the account has a working store connection. None of them
takes options: what each one does is fixed, and the editor says so under the
step.

| Step | What it does to the order |
| --- | --- |
| **Refund the order in full** | Refunds everything still refundable, through the payments Shopify proposes. The items are not put back in stock. Shopify notifies the customer. |
| **Refund the shipping cost** | Refunds only what is left of the shipping cost. The items are not refunded. Shopify notifies the customer. Refused when the order has no shipping cost left to refund. |
| **Cancel the order** | Cancels the order at the customer's request, refunds it in full to the original payments and puts the items back in stock. Shopify notifies the customer. It cannot be undone. |
| **Send a free replacement** | Creates a new order with the same items and quantities, to the same address and for the same customer. It costs the customer nothing, shipping included. It is tagged `replacement` and its note names the original order. |

Every step acts on the order the conversation is about: the one marked with
"This conversation is about this order" in the Orders section, or found by its
number in the customer's first message. A step never picks "the customer's
latest order" by itself.

Automation rules have no order steps: an order action always needs a person.

## Running a macro with order steps

Before such a macro runs, the agent sees a confirmation. It names the order and
says what each order step will do to it, with the amount of every refund. The
helpdesk works this out with the same code the steps run with. **Don't run**
runs no step of the macro, not even the ones that do not touch the order. A
macro without order steps runs as before, without a confirmation.

When no order is tied to the conversation, the confirmation says so and offers
only to close.

A macro with order steps runs in one conversation at a time: the bulk bar of
the conversation list does not run it for several conversations at once.

## Who can run them

The steps are performed as the agent who runs the macro. Administrators can.
An agent can only after an administrator switches it on for them in
**Settings → Order actions**. The connected app needs the scopes listed in
[Connecting a Shopify store](connect-shopify.md); the replacement needs
`write_draft_orders` and `read_products` as well.

## When a step cannot be done

The steps run in the order the macro lists them. When an order step cannot be
done, the steps after it do not run, so the customer never gets "we refunded
you" for a refund that did not happen. The steps before it stay done. The
conversation gets a private note naming the macro, the step and the reason:

- no order is tied to the conversation;
- the agent may not act on orders;
- the connected app lacks a scope, which the note names;
- Shopify refused, with Shopify's own words, for example when nothing is left
  to refund because the macro already ran on this order;
- Shopify has not finished a cancellation yet, or did not confirm. Check the
  order in Shopify before telling the customer anything.

## What is recorded

A step that was done leaves the private note the manual action leaves, written
as the agent: for a refund, the amount and the order number. The account's
order-action records (`GET .../inclamo/shopify/conversations/:id/actions`) hold
every attempt, done or refused, with `macro_id` naming the macro it ran in.
