## MODIFIED Requirements

### Requirement: Order data is read from the store when needed and is not kept
The panel SHALL read order data from the store when it is opened and after every action. Order data MAY be reused for at most 60 seconds. Outside the conversation attributes of the marked order named below and the store facts of the customer that `store-data-rules` writes on the conversation (whether the contact is a customer, the number of orders, the total spent, the customer's tags, and the latest order's payment status, fulfilment status, total and tags), order and customer data SHALL NOT be stored by the helpdesk. The stored facts SHALL NOT include a name, an email address, a phone number or an address.

#### Scenario: Order changed in the store
- **WHEN** an order is fulfilled in the store and the agent reopens the conversation two minutes later
- **THEN** the panel shows the order as fulfilled
