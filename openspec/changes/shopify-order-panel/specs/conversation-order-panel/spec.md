## Purpose

What an agent sees and can do about a customer's Shopify orders inside a conversation: how the customer is matched, what the order panel shows, how an order is tied to the conversation, who may act on an order, how cancel, refund, address change and the free replacement work, and what record every action leaves.

## ADDED Requirements

### Requirement: The panel is a section of the conversation sidebar
For an account with a working store connection, the conversation sidebar SHALL contain an "Orders" section that behaves like the other sections of that sidebar: it can be collapsed, expanded and reordered, and it remembers its state per user. Without a connection the section SHALL show a "not connected" state, with a connect action for administrators and an explanation for agents.

#### Scenario: Connected account
- **WHEN** an agent opens a conversation in an account with a working connection
- **THEN** the sidebar shows the "Orders" section among the other sections, and messages stay visible next to it

#### Scenario: Not connected, agent
- **WHEN** an agent opens a conversation in an account without a connection
- **THEN** the section says the store is not connected and that an administrator can connect it, with no connect action

### Requirement: The customer is matched by email, then phone, never by guess
The panel SHALL look the conversation's contact up in the store by the contact's email, and if that finds no customer, by the contact's phone number. Exactly one customer found SHALL be used. When more than one customer is found, none SHALL be chosen automatically: the panel SHALL list them and the agent's choice SHALL be remembered for that contact. When none is found, the panel SHALL offer lookup by order number.

#### Scenario: One customer by email
- **WHEN** the contact's email belongs to exactly one customer of the store
- **THEN** the panel shows that customer and their orders

#### Scenario: Two customers with the same phone
- **WHEN** the contact has no email and the phone number belongs to two customers
- **THEN** the panel lists both without showing orders, the agent picks one, and the next conversation of this contact opens with that customer

#### Scenario: Unknown contact, order number given
- **WHEN** no customer matches and the agent enters an order number that exists in the store
- **THEN** the panel shows that order and its customer, and the agent can keep that customer for the contact

#### Scenario: Contact without email and phone
- **WHEN** the contact has neither an email nor a phone number
- **THEN** the panel offers only lookup by order number

#### Scenario: Store connected in the limited mode
- **WHEN** the store does not give customer personal data to the connection
- **THEN** the panel offers lookup by order number only, shows the order's items, statuses, shipments and refunds, shows the customer's name and the shipping address as unavailable, and does not offer the address change

### Requirement: The panel shows the customer and their recent orders
For a matched customer the panel SHALL show the customer's name, the number of orders and the total spent, and the ten most recent orders, newest first, with the possibility to load more. For each order it SHALL show the order number, date, total with currency, payment status, fulfilment status, the line items with quantity and price, the shipping address, each shipment's carrier, tracking number and tracking link, the refunds already made, and a link to the order in the store's admin.

#### Scenario: Order with two shipments
- **WHEN** an order was shipped in two parcels
- **THEN** the order shows both shipments, each with its carrier, tracking number and link

#### Scenario: Partially refunded order
- **WHEN** an order has an earlier refund
- **THEN** the order shows the refunded amount and what remains refundable

### Requirement: Order data is read from the store when needed and is not kept
The panel SHALL read order data from the store when it is opened and after every action. Order data MAY be reused for at most 60 seconds. Outside the conversation attributes named below, order and customer data SHALL NOT be stored by the helpdesk.

#### Scenario: Order changed in the store
- **WHEN** an order is fulfilled in the store and the agent reopens the conversation two minutes later
- **THEN** the panel shows the order as fulfilled

### Requirement: One order can be tied to the conversation
The agent SHALL be able to mark one order as the order the conversation is about, and to change or clear that mark. When the customer's first message contains an order number of the matched customer, that order SHALL be marked automatically. The marked order's number, payment status, fulfilment status, first tracking number, first tracking link and admin link SHALL be written as attributes of the conversation, refreshed whenever the panel reads the order, so that macros, automation rules and other services can use them. The shipping address SHALL NOT be written to attributes.

#### Scenario: Agent marks an order
- **WHEN** the agent marks order #1042 in the panel
- **THEN** the conversation's attributes carry the order number 1042, its statuses, tracking number and links

#### Scenario: Order number in the first message
- **WHEN** the customer's first message says "where is my order #1042" and #1042 belongs to the matched customer
- **THEN** order #1042 is marked without the agent's action

#### Scenario: Order number of someone else
- **WHEN** the first message names an order number that does not belong to the matched customer
- **THEN** no order is marked automatically

### Requirement: Order actions need a role given by an administrator
Administrators SHALL always be able to perform order actions. An agent SHALL be able to perform them only while holding the order-actions role, which only an administrator can give and take away. One role SHALL cover every order action of this capability. A newly added agent SHALL NOT hold it. The administrator SHALL give and take the role on a page of the account settings that lists the team with a switch for each agent; the panel SHALL link to that page for administrators. An agent without the role SHALL see the panel and the order data in full, SHALL see each action as unavailable with the reason, and a request to perform an action SHALL be refused without calling the store.

#### Scenario: Agent without the role
- **WHEN** an agent who does not hold the role opens a conversation with a matched customer
- **THEN** the orders are shown, every action is shown as unavailable with the reason "an administrator has not allowed you to act on orders", and a direct request to refund is refused

#### Scenario: Administrator gives the role
- **WHEN** an administrator follows the panel's link to the settings page and switches the role on for an agent
- **THEN** on that agent's next panel load the actions allowed by the store's scopes are available

#### Scenario: Role taken away during a confirmation
- **WHEN** an agent opens the refund confirmation, an administrator takes the role away, and the agent confirms
- **THEN** the refund is refused, the store is not called, and the action record holds the attempt as refused

#### Scenario: Agent tries to give the role
- **WHEN** a user with the agent role calls the endpoint that gives or takes the role
- **THEN** the request is refused and nothing changes

### Requirement: Cancel an order
The agent SHALL be able to cancel an order that the store allows to be cancelled. The confirmation SHALL ask for a reason from the store's list, whether to refund the payment, whether to restock, and whether to notify the customer, and SHALL state that cancellation cannot be undone. The panel SHALL show the order as "cancelling" until the store confirms, and the final state afterwards.

#### Scenario: Unfulfilled paid order
- **WHEN** the agent cancels an unfulfilled paid order with refund and restock, and confirms
- **THEN** the store cancels and refunds the order, the panel shows it as cancelled, and a private note records the cancellation

#### Scenario: Order the store will not cancel
- **WHEN** the agent tries to cancel an order that is already cancelled or has a return in progress
- **THEN** the action is not offered, or if the state changed meanwhile, the store's refusal is shown in words and nothing else changes

### Requirement: Refund an order fully or partly
The agent SHALL be able to refund an order: the full remaining amount, selected line items with quantities, shipping, or a custom amount up to what remains refundable. The confirmation SHALL show the amount and currency, where the money goes, whether items are restocked and whether the customer is notified. An amount above what remains refundable SHALL be refused before the store is called. One confirmation SHALL result in at most one refund, also when the request is repeated after a network failure. When the agent asks for the items to be put back in stock, they SHALL go back into stock without the agent choosing where: items that have shipped at the location the store proposes for their return, items that have not shipped at the location that keeps them for shipping. The confirmation SHALL name the location. An item the store names no location for SHALL be refunded without restocking, and the confirmation SHALL say so. Putting items back in stock needs the scopes `read_locations` and `read_merchant_managed_fulfillment_orders`: without either the refund SHALL remain available, the items SHALL stay out of stock, and the confirmation SHALL say so and name the missing scope.

#### Scenario: Partial refund by amount
- **WHEN** the agent refunds 20.00 EUR of an order with 54.00 EUR refundable and confirms
- **THEN** the store records one refund of 20.00 EUR, the panel shows 34.00 EUR as refundable, and a private note records the refund

#### Scenario: Shipped item put back in stock
- **WHEN** the agent refunds an item that has shipped, asks for it to be put back in stock, and confirms
- **THEN** the confirmation named the location the item was shipped from, nothing more was asked of the agent, and the store records the refund with the item returned to that location

#### Scenario: Unshipped item put back in stock
- **WHEN** the agent refunds an item that has not shipped, asks for it to be put back in stock, and confirms
- **THEN** the confirmation named the location that kept the item, and the store records the refund with the item back in stock there

#### Scenario: Item the store names no location for
- **WHEN** the agent refunds, with restocking, an item that has not shipped and whose location the store does not show
- **THEN** the confirmation says the item stays out of stock, and the refund is made without restocking it

#### Scenario: Locations scope missing
- **WHEN** the connection lacks `read_locations` and the agent refunds an item with restocking
- **THEN** the confirmation says the item stays out of stock and names the scope, and the refund is made without restocking it

#### Scenario: Amount above the refundable
- **WHEN** the agent enters 60.00 EUR for an order with 54.00 EUR refundable
- **THEN** the form refuses the amount and the store is not called

#### Scenario: Repeat after a lost answer
- **WHEN** the refund request reached the store, the answer was lost, and the same confirmation is sent again
- **THEN** the store holds one refund, and the panel shows it once

### Requirement: Change the shipping address
The agent SHALL be able to change the shipping address of an order that has no shipment yet. The form SHALL start from the current address. For an order with any shipment the action SHALL NOT be offered, and the panel SHALL say why.

#### Scenario: Unfulfilled order
- **WHEN** the agent changes the street and postcode of an unfulfilled order and confirms
- **THEN** the store holds the new address, the panel shows it, and a private note records that the address was changed, without the address itself

#### Scenario: Order already shipped
- **WHEN** the order has a shipment
- **THEN** the address action is unavailable with the reason "already shipped"

### Requirement: Duplicate an order as a free replacement
The agent SHALL be able to duplicate an order of the customer as a replacement that costs the customer nothing. The dialog SHALL start from all items of the original order; the agent SHALL be able to lower quantities and remove items, and SHALL NOT be able to add items or change prices. The replacement SHALL go to the customer and the shipping address of the original order, with the items fully discounted and shipping free. The confirmation SHALL list the items and state that a new order will be created in the store, that stock will be taken, and that the customer is charged nothing. An accepted replacement SHALL be a new order in the store, marked as a replacement and naming the original order number. One confirmation SHALL result in at most one replacement order, also when the request is repeated after a network failure. When the store does not create the order, nothing unfinished SHALL be left behind unnoticed: an unfinished draft is removed, or named in the message with a link to it.

#### Scenario: Damaged item reshipped
- **WHEN** the agent duplicates order #1042, keeps one of its three items, and confirms
- **THEN** the store holds a new order with that one item at a total of 0, marked as a replacement of #1042, the panel shows the new order, and a private note names both order numbers

#### Scenario: Item no longer in stock
- **WHEN** the store refuses the replacement because an item cannot be supplied
- **THEN** no order is created, the agent sees the store's reason, and no draft is left in the store

#### Scenario: Repeat after a lost answer
- **WHEN** the replacement request reached the store, the answer was lost, and the same confirmation is sent again
- **THEN** the store holds one replacement order, and the panel shows it once

#### Scenario: Draft orders scope missing
- **WHEN** the connection holds `write_orders` but not `write_draft_orders`
- **THEN** cancel, refund and address change are available, and the replacement is shown as unavailable naming `write_draft_orders`

#### Scenario: Products scope missing
- **WHEN** the connection holds `write_orders` and `write_draft_orders` but not `read_products`
- **THEN** the replacement is shown as unavailable naming `read_products`, and the panel shows orders as before

### Requirement: Every action leaves a record
Every action that the store accepted SHALL leave a private note in the conversation, visible to the team and not to the customer, naming the agent, the action, the order number and, for refunds, the amount and currency. Every attempt, accepted or refused, SHALL also be written to an action record kept by the helpdesk with the time, the agent, the conversation, the order, the action, its parameters without personal data, and the outcome.

#### Scenario: Refused action
- **WHEN** the store refuses a refund
- **THEN** no private note is written, the agent sees the store's reason, and the action record holds the attempt with the outcome "refused"

### Requirement: Failures are shown, never silent
When the store is unreachable, slow or throttling, the panel SHALL say so and offer to retry, and SHALL NOT show stale data as current. An action whose outcome is unknown SHALL be shown as "outcome unknown" with a link to the order in the store's admin, and SHALL NOT be reported as done or as failed.

#### Scenario: Store does not answer
- **WHEN** the store does not answer within the time limit while the panel loads
- **THEN** the panel shows that the store did not answer and a retry action

#### Scenario: Cancellation still running
- **WHEN** a cancellation is accepted but not confirmed by the store within the waiting time
- **THEN** the order is shown as "cancelling", and the panel checks again when it is next read
