## Purpose

Lets an agent put a product of the store and a freshly made discount code into the reply they are writing, without the storefront and the store's admin.

## ADDED Requirements

### Requirement: A product is inserted into the reply
In an account with a working connection that has `read_products`, any agent SHALL be able to search the store's catalogue by title or SKU from the conversation and insert a product into the reply being written: its title, its price with currency and its link in the online store. This SHALL work whether or not the conversation's contact matches a customer. A product that is not published in the online store SHALL be shown in the results as having no link and SHALL be inserted as title and price only. Without `read_products` the control SHALL NOT be offered.

#### Scenario: Product with a link
- **WHEN** an agent searches for a product by its title, picks it and inserts it
- **THEN** the reply editor contains the product's title, price and storefront link, and the agent can keep typing around them

#### Scenario: Search by SKU
- **WHEN** an agent searches by a variant's SKU
- **THEN** the results show the product that has that SKU

#### Scenario: Product not in the online store
- **WHEN** an agent picks a product that is not published in the online store
- **THEN** the results marked it as having no link, and the reply gets its title and price without a link

#### Scenario: Nothing found
- **WHEN** an agent searches for text no product has
- **THEN** the dialog says nothing was found and nothing is inserted

### Requirement: A discount code is created and inserted
An agent holding the order-actions role, and any administrator, SHALL be able to create a discount code from the conversation on a connection that has `write_discounts`: a percentage or an amount off the whole order, usable once, expiring in 7 days, 30 days (the default) or never. The code text SHALL be proposed by the helpdesk and editable before creation. When the conversation's contact matches a customer, the code SHALL work for that customer only; otherwise for anyone. On creation the code SHALL be inserted into the reply being written. An agent without the role SHALL NOT be offered the control; without the scope the control SHALL NOT be offered and the panel SHALL name the missing permission.

#### Scenario: Percentage code for the customer
- **WHEN** an agent with the role creates a 10 % code in a conversation of a matched customer
- **THEN** the store has a code of 10 %, usable once, limited to that customer, expiring in 30 days, and the reply editor contains the code

#### Scenario: Amount code with another expiry
- **WHEN** an agent with the role creates a code of 5.00 off expiring in 7 days
- **THEN** the store has a code of that amount with that expiry

#### Scenario: Contact who is not a customer
- **WHEN** an agent with the role creates a code in a conversation whose contact matches no customer
- **THEN** the store has a single-use code not limited to a customer

#### Scenario: Agent without the role
- **WHEN** an agent without the order-actions role opens the Orders section
- **THEN** "Insert product" is offered to them and "Discount code" is not

#### Scenario: Permission missing
- **WHEN** an administrator opens the Orders section on a connection without `write_discounts`
- **THEN** "Discount code" is not offered and a line names the missing permission

### Requirement: A created code leaves a record and failures are shown
Creating a code SHALL leave a private note in the conversation naming the agent, the code, its value and its expiry. When the store refuses the code, the dialog SHALL show the store's reason, nothing SHALL be inserted and no record SHALL be left.

#### Scenario: Record of a code
- **WHEN** an agent creates a 10 % code
- **THEN** the conversation gets a private note naming the agent, the code, 10 % and the expiry date

#### Scenario: Code text already taken
- **WHEN** an agent creates a code whose text already exists in the store
- **THEN** the dialog shows the store's reason and the reply editor is unchanged
