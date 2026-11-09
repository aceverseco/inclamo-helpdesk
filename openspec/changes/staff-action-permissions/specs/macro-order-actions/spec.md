## MODIFIED Requirements

### Requirement: Order steps act on the tied order after a confirmation
Each order step SHALL require the executing member’s current permission for that operation; cancellation with refund SHALL additionally require refund permission. An order step SHALL act on the order tied to the conversation. Before a macro that contains an order step runs, the agent SHALL see a confirmation naming the order and what each order step will do to it, with the amount for a refund; declining SHALL run no step of the macro. A macro without order steps SHALL run as before, without a confirmation.

#### Scenario: Refund macro runs
- **WHEN** an agent with the required action permissions runs the refund macro in a conversation tied to paid order #1042 and confirms
- **THEN** order #1042 is refunded in full in the store, the macro's message is sent and the conversation is resolved

#### Scenario: Agent declines the confirmation
- **WHEN** the agent runs the refund macro and declines the confirmation
- **THEN** no refund is made, no message is sent and the conversation stays open

#### Scenario: Shipping refund step
- **WHEN** an agent with the required action permissions runs a macro with "Refund the shipping cost" on an order with paid shipping and confirms
- **THEN** the shipping cost of that order is refunded in the store and the items are not

#### Scenario: Cancel step
- **WHEN** an agent with the required action permissions runs a macro with "Cancel the order" on an unshipped paid order and confirms
- **THEN** the order is cancelled and refunded in the store

#### Scenario: Replacement step
- **WHEN** an agent with the required action permissions runs a macro with "Send a free replacement" on an order and confirms
- **THEN** a new free order with the same items exists in the store for the same customer

### Requirement: A failed order step stops the macro
When an order step cannot be done (no order is tied, the agent lacks any permission required by the step, a permission of the merchant's app is missing, or the store refuses), the steps after it SHALL NOT run, and the conversation SHALL get a private note naming the step and the reason. Steps before it stay done.

#### Scenario: No order tied
- **WHEN** an agent with the required action permissions runs the refund macro in a conversation with no tied order
- **THEN** no message is sent, the conversation stays open, and a private note says the refund step had no order to act on

#### Scenario: Agent without the role
- **WHEN** an agent without the refund permission runs the refund macro in a conversation tied to an order
- **THEN** no refund is made, no message is sent, and a private note says the agent may not act on orders

#### Scenario: Nothing left to refund
- **WHEN** the refund macro is run a second time on the same order
- **THEN** no second refund is made, no second message is sent, and a private note gives the store's reason
