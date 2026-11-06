# Order variables in replies

A reply can name the facts of the order a conversation is about: "your order
#1042 is on its way, here is the tracking link". You write a variable, the
helpdesk puts the value in.

They work in three places: a reply you type, a saved reply (canned response),
and the message step of a macro. They are offered only when a store is
connected and its connection works.

## The variables

| Variable | What it becomes | Example |
| --- | --- | --- |
| `{{order.number}}` | the order number as the store shows it | `#1042` |
| `{{order.date}}` | the day the order was placed (UTC) | `November 5, 2026` |
| `{{order.total}}` | the order total with its currency | `1,585.90 UAH` |
| `{{order.payment_status}}` | the payment status, in the words of the Orders panel | `Paid` |
| `{{order.fulfillment_status}}` | the shipping status, in the words of the Orders panel | `Shipped` |
| `{{order.tracking_number}}` | the tracking number of the first shipment | `E2EV1` |
| `{{order.tracking_link}}` | the tracking link of the first shipment | `https://example.com/track/E2EV1` |
| `{{order.status_link}}` | the order status page the store shows the customer | a link to your store |
| `{{order.items}}` | the items, one line each: quantity and title | `2 × Blue Mug` |

Type `{{` in the reply editor to pick one from the list; the list shows a
short description and the current value of each.

## Which order

Always the order **tied to the conversation**, and no other: the one marked
"This conversation is about this order" in the Orders panel. An agent ties it
with one click; it is also tied by itself when the customer's first message
names one of their own orders.

When no order is tied:

- In the reply editor you are told before sending which variables have no
  value, and can go back or send anyway.
- A macro sends its message with the variables as empty text. The customer
  never sees a raw `{{order.number}}`.

So a macro that names an order is best run after the order is tied.

## How fresh the values are

- **A macro's message** reads the order from the store at the moment it is
  sent, even if nobody has opened the Orders panel since the order changed.
- **A reply in the editor** shows you the values the Orders panel last read,
  and sends exactly what you see. A variable the order has no value for yet (a
  tracking number of an order not shipped) stays as `{{…}}` in the editor and
  is filled in, or left empty, when the message is sent.

The helpdesk reuses what it read of an order for up to a minute, the same as
the Orders panel does.

## When the store does not answer

The message is sent anyway. The store gets three seconds; after that the
number, the two statuses, the tracking number and the tracking link take the
values last written on the conversation (the attributes "Order number", "Order
payment status" and so on), and the other variables are empty.

## Not yet

- Variables in automation rules.
- The shipping address as a variable.
- Status words in languages other than English.
