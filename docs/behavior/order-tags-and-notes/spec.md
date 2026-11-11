# order-tags-and-notes

Behavior contract for this source revision.

### Requirement: The panel shows tags and notes

For each order the panel SHALL show the order's tags and its note. For a matched customer the panel SHALL show the customer's tags and note. In the limited mode the customer's tags and note SHALL NOT be shown.

#### Scenario: Order with tags and a note

- **WHEN** an agent opens an order that has the tags "gift" and "priority" and the note "Leave at the door" in the store
- **THEN** the order card shows both tags and the note

#### Scenario: Customer with tags and a note

- **WHEN** an agent opens a conversation of a customer tagged "wholesale" with the note "Pays by invoice"
- **THEN** the customer block shows the tag and the note

### Requirement: Order tags and note can be changed

An agent holding the order-actions role, and any administrator, SHALL be able to add a tag to an order, remove a tag and replace the order's note, when the connection has `write_orders`. Adding or removing one tag SHALL NOT change the order's other tags, including tags added in the store since the panel read the order. An agent without the role SHALL see tags and notes and SHALL NOT be offered the controls.

#### Scenario: Agent adds an order tag

- **WHEN** an agent with the role adds the tag "address-confirmed" to order #1042
- **THEN** the order has that tag in the store and the card shows it

#### Scenario: Agent removes an order tag

- **WHEN** an agent with the role removes the tag "priority" from an order tagged "gift" and "priority"
- **THEN** the order keeps "gift" and no longer has "priority" in the store

#### Scenario: Tag added in the store meanwhile

- **WHEN** the panel shows an order with the tag "gift", someone adds "fraud-check" in the store, and the agent then adds "address-confirmed" in the panel
- **THEN** the order has all three tags in the store

#### Scenario: Agent edits the order note

- **WHEN** an agent with the role replaces the order's note with "Customer asked for delivery after 6 pm"
- **THEN** the order has that note in the store and the card shows it

#### Scenario: Agent without the role

- **WHEN** an agent without the order-actions role opens an order with tags and a note
- **THEN** they see the tags and the note and no control to change them

### Requirement: Customer tags and note need their own permission

Changing the customer's tags or note SHALL need the order-actions role and the `write_customers` scope on the connection. Without that scope the customer's tags and note SHALL be shown without controls, with one line saying which permission the merchant's app lacks.

#### Scenario: Agent adds a customer tag

- **WHEN** an agent with the role adds the tag "vip" to the customer, on a connection that has `write_customers`
- **THEN** the customer has that tag in the store and the customer block shows it

#### Scenario: Agent edits the customer note

- **WHEN** an agent with the role replaces the customer's note with "Prefers phone calls"
- **THEN** the customer has that note in the store

#### Scenario: Connection without the customer permission

- **WHEN** an administrator opens a conversation on a connection without `write_customers`
- **THEN** the customer's tags and note are shown, no control changes them, and a line names the missing permission

### Requirement: Every change leaves a record and failures are shown

Each change of tags or of a note SHALL leave a private note in the conversation naming the agent, the order or the customer, and what was added, removed or replaced; a note's text SHALL be named as changed without repeating the customer's personal data from it. When the store refuses a change, the panel SHALL show the store's reason and SHALL keep showing the old value.

#### Scenario: Record of a tag

- **WHEN** an agent adds the tag "address-confirmed" to order #1042
- **THEN** the conversation gets a private note saying who added "address-confirmed" to #1042

#### Scenario: Store refuses the change

- **WHEN** the store answers a tag change with an error
- **THEN** the panel shows the reason and the tags stay as they were
