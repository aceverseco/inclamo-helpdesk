# store-data-rules

Behavior contract for this source revision.

### Requirement: Store facts are conditions in automation rules

For an account with a working store connection, the automation rule editor SHALL offer these conditions: customer's number of orders, customer's total spent (a number in the store's currency), customer's tags, latest order's payment status, latest order's fulfilment status, latest order's total, latest order's tags, and whether the contact is a customer of the store. Number conditions SHALL support "greater than" and "less than"; tag conditions SHALL support "contains".

#### Scenario: Rule on total spent

- **WHEN** an administrator has a rule "conversation created, customer's total spent greater than 500: priority high, assign the senior team" and a customer who spent 620 writes in
- **THEN** the new conversation gets high priority and the senior team

#### Scenario: Customer below the amount

- **WHEN** the same rule exists and a customer who spent 80 writes in
- **THEN** the new conversation keeps its priority and gets no team

#### Scenario: Rule on a customer tag

- **WHEN** a rule "customer's tags contain wholesale: add the label wholesale" exists and a customer tagged "wholesale" in the store writes in
- **THEN** the new conversation gets the label "wholesale"

#### Scenario: Rule on the latest order

- **WHEN** a rule "latest order's fulfilment status is unfulfilled: add the label awaiting-shipment" exists and a customer whose latest order is not shipped writes in
- **THEN** the new conversation gets the label "awaiting-shipment"

### Requirement: The facts are there before the rules run

When a conversation is created for a contact that matches one store customer, the facts SHALL be written before the automation rules of that conversation are evaluated, and an order named in the first message SHALL be tied before that too. When the contact matches no customer, "is a customer" SHALL be "no" and the other facts SHALL be absent. When the store does not answer within the time limit, the rules SHALL run without the facts and the conversation SHALL be created as usual. For a store connected in the limited mode no customer facts SHALL be written. The facts SHALL be refreshed whenever the order panel reads the customer.

#### Scenario: Rule message with the order number

- **WHEN** a rule "conversation created: send the message 'We are checking order {{order.number}}'" exists and a customer's first message names their order #1042
- **THEN** the customer receives "We are checking order #1042"

#### Scenario: Contact who is not a customer

- **WHEN** a rule "is a customer of the store: no: add the label pre-sale" exists and a contact unknown to the store writes in
- **THEN** the new conversation gets the label "pre-sale"

#### Scenario: Store silent

- **WHEN** the store does not answer and a customer who spent 620 writes in while the total-spent rule exists
- **THEN** the conversation is created, the agent can answer it, and the rule has not fired

#### Scenario: Store in the limited mode

- **WHEN** the account's store hides customer data and a contact writes in
- **THEN** the conversation carries no customer facts and rules on them do not fire

### Requirement: Preset rules are switched on with one toggle

An administrator SHALL have a settings page listing preset rules, each with a switch and, where the rule needs one, a value to enter. Switching a preset on SHALL create an ordinary automation rule, visible and editable in Chatwoot's automation list; switching it off SHALL deactivate that rule without deleting the administrator's edits. The page SHALL be open to administrators only. The presets SHALL be: "VIP customers first", "Order not shipped yet" and "No orders yet".

#### Scenario: Administrator switches on the VIP preset

- **WHEN** an administrator enters 500 and switches on "VIP customers first", and a customer who spent 620 writes in
- **THEN** a rule with that name is in the automation list, and the new conversation gets high priority and the label "vip"

#### Scenario: Preset switched off

- **WHEN** the administrator switches the preset off and the same customer writes in again
- **THEN** the rule is shown as inactive in the automation list and the new conversation keeps its priority

#### Scenario: Agent cannot manage presets

- **WHEN** an agent opens the address of the presets page
- **THEN** the page is not shown to them and the settings menu has no entry for it
