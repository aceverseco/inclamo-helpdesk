# ready-replies

Behavior contract for this source revision.

### Requirement: Ready saved replies exist for the support categories

Every account SHALL have one ready saved reply for each of the categories delivery, cancellation, damage, missing parts and return. Each SHALL be an ordinary saved reply: listed with the store's own saved replies, inserted the same way, and editable and deletable by the same people. The delivery reply SHALL contain the order number and tracking link variables; the cancellation and return replies SHALL contain the order number variable.

#### Scenario: Agent inserts the delivery reply

- **WHEN** an agent inserts the ready delivery reply in a conversation tied to shipped order #1042 and sends it
- **THEN** the customer receives the text with "#1042" and that order's tracking link in place of the variables

#### Scenario: Ready replies are listed with the store's own

- **WHEN** an administrator opens the saved replies settings of a new account
- **THEN** the five ready replies are in the list and can be edited or deleted like any other

### Requirement: Installing the ready replies is repeatable

Installing the ready replies again, as every upgrade does, SHALL create no duplicate, SHALL NOT change a reply the store edited, and SHALL NOT bring back a reply the store deleted. Where the store already has its own saved reply under the short code a ready reply would use, the store's reply SHALL be left as it is and the ready one SHALL NOT be created.

#### Scenario: Edited reply is kept

- **WHEN** an administrator rewrites the ready return reply and the installation runs again
- **THEN** the reply keeps the administrator's text and there is still one of it

#### Scenario: Deleted reply stays deleted

- **WHEN** an administrator deletes the ready damage reply and the installation runs again
- **THEN** the account has no ready damage reply

#### Scenario: Short code already taken

- **WHEN** a store already has its own saved reply under the short code of the ready cancellation reply and the installation runs
- **THEN** the store's reply is unchanged and no second reply with that short code exists
