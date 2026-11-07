## Purpose

Lets a saved reply, a typed reply and the message step of a macro carry the facts of the order the conversation is about, so the agent does not copy order numbers and tracking links by hand.

## ADDED Requirements

### Requirement: Order variables exist under readable names
For an account with a working store connection, the following variables SHALL be available: `order.number`, `order.date`, `order.total` (with currency), `order.payment_status`, `order.fulfillment_status`, `order.tracking_number`, `order.tracking_link`, `order.status_link` (the order status page the store shows the customer) and `order.items` (one line per item: quantity and title). They SHALL be offered in the variable list of the reply editor next to Chatwoot's own variables, each with a short description, and SHALL work in saved replies and in the message step of a macro. Statuses SHALL be rendered in the words the order panel shows. For an account without a connection the variables SHALL NOT be offered.

#### Scenario: Variable list offers the order variables
- **WHEN** an agent opens the variable list in the reply editor of an account with a working connection
- **THEN** the list contains the order variables with their descriptions

#### Scenario: Account without a connection
- **WHEN** an agent opens the variable list in an account that has no store connection
- **THEN** the list contains no order variables

#### Scenario: Saved reply with number and tracking link
- **WHEN** an agent inserts a saved reply "Your order {{order.number}} is on its way: {{order.tracking_link}}" in a conversation tied to shipped order #1042 and sends it
- **THEN** the customer receives the text with "#1042" and the tracking link of that order

#### Scenario: Items and total
- **WHEN** an agent sends a reply with `{{order.items}}` and `{{order.total}}` in a conversation tied to an order with two items
- **THEN** the message lists both items with their quantities and shows the order total with its currency

#### Scenario: Macro message
- **WHEN** an agent runs a macro whose message step contains `{{order.number}}` and `{{order.fulfillment_status}}` in a conversation tied to an order
- **THEN** the message sent by the macro contains that order's number and its fulfilment status in the panel's words

### Requirement: The variables speak about the order the conversation is about
The variables SHALL take their values from the order tied to the conversation. When no order is tied, they SHALL take the latest order of the customer the conversation's contact is matched to (the same customer the Orders panel shows), so that an agent changes the order by tying another one by hand. When there is neither a tied order nor a matched customer with orders and the agent's reply contains order variables, the agent SHALL be told before sending which variables have no value. A message sent by a macro in such a conversation SHALL render order variables as empty text and SHALL NOT contain raw placeholders.

#### Scenario: Latest order when none is tied
- **WHEN** an agent sends a reply with `{{order.number}}` in a conversation of a customer with orders #1040, #1041 and #1042 and no tied order
- **THEN** the message names #1042

#### Scenario: Tied order wins over the latest
- **WHEN** an agent ties order #1040 in that conversation and sends a reply with `{{order.number}}`
- **THEN** the message names #1040

#### Scenario: Agent warned when no order is known
- **WHEN** an agent inserts a saved reply with `{{order.number}}` in a conversation whose contact matches no customer of the store, with no tied order, and presses send
- **THEN** the agent is told that `order.number` has no value before the message goes out

#### Scenario: Macro in a conversation without a known order
- **WHEN** a macro whose message contains `{{order.number}}` runs in a conversation whose contact matches no customer of the store, with no tied order
- **THEN** the message is sent without the text "{{" and without an order number

### Requirement: Values are those of the moment of sending
When a message with order variables is sent, the values SHALL be read from the store at that moment, within the freshness the order panel itself has. When the store cannot be reached, the message SHALL still be sent: for a tied order the number, statuses, tracking number and tracking link SHALL take the values last written on the conversation and the other order variables SHALL be empty; for a conversation without a tied order every order variable SHALL be empty.

#### Scenario: Tracking added after the panel was last open
- **WHEN** an order tied to a conversation gets a tracking number in the store, nobody opens the panel, and a macro with `{{order.tracking_number}}` runs
- **THEN** the message contains the new tracking number

#### Scenario: Store unreachable
- **WHEN** the store does not answer and a macro with `{{order.number}}` and `{{order.total}}` runs in a conversation tied to order #1042
- **THEN** the message is sent with "#1042" and without a total
