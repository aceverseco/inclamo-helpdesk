## Purpose

Lets an agent put a product of the store and a freshly made discount code into the reply they are writing, without the storefront and the store's admin. The discounts an agent may give are set beforehand by an administrator.

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

### Requirement: Discount presets are set by an administrator
An administrator SHALL be able to keep a list of discount presets in the account settings. Each preset SHALL hold a name shown to agents, a value as a percentage (above 0, at most 100) or as an amount in the shop's currency (above 0), an expiry in whole days or none, the number of times its code may be used (1 or more), and an audience: this customer only, or anyone. An empty expiry SHALL mean that the code never expires. A preset that breaks these limits SHALL be refused with the reason. Changing or removing a preset SHALL NOT change codes already created from it. Agents SHALL NOT be able to change presets.

#### Scenario: Preset created
- **WHEN** an administrator adds a preset "Sorry" of 10 %, 30 days, 1 use, this customer only
- **THEN** the list of presets shows it with those conditions

#### Scenario: Preset that never expires
- **WHEN** an administrator adds a preset with the expiry left empty
- **THEN** the list shows it as never expiring

#### Scenario: Preset outside the limits
- **WHEN** an administrator adds a preset of 0 %, of more than 100 %, of an amount of 0, or with 0 uses
- **THEN** the preset is not saved and the reason is shown

#### Scenario: Agent cannot change presets
- **WHEN** an agent who is not an administrator tries to open or change the presets
- **THEN** the settings page is not offered to them and a change sent anyway is refused

### Requirement: The right to give discounts
An administrator SHALL be able to give and take, per agent, the right to give discounts. The right SHALL be separate from the order-actions role: either may be held without the other. Administrators SHALL always hold it. A new agent SHALL NOT hold it until an administrator gives it.

#### Scenario: Right given
- **WHEN** an administrator gives an agent the right to give discounts
- **THEN** that agent is offered "Discount code" in the Orders section, without holding the order-actions role

#### Scenario: Agent without the right
- **WHEN** an agent who holds the order-actions role but not the right to give discounts opens the Orders section
- **THEN** "Insert product" is offered to them and "Discount code" is not

### Requirement: A discount code is created from a preset and inserted
An agent holding the right SHALL be able to create a discount code from the conversation by picking one of the presets, on a connection that has `write_discounts`. The agent SHALL NOT be able to change the preset's conditions. The code SHALL take off the whole order the preset's value, SHALL work the preset's number of times and SHALL expire after the preset's number of days, or never. A preset for this customer only SHALL make a code that works for the conversation's matched customer only, and SHALL NOT be offered when the contact matches no customer; a preset for anyone SHALL make a code any buyer may use, once each. The code's text SHALL be made by the helpdesk and SHALL NOT be editable. On creation the code SHALL be inserted into the reply being written. Without the scope the control SHALL NOT be offered and the panel SHALL name the missing permission. When no preset exists the control SHALL NOT be offered, and an administrator SHALL see a line pointing to the settings page.

#### Scenario: Code for the customer
- **WHEN** an agent with the right picks a preset of 10 %, 30 days, 1 use, this customer only in a conversation of a matched customer
- **THEN** the store has a code of 10 % off the order, usable once, limited to that customer, expiring in 30 days, and the reply editor contains the code

#### Scenario: Code for anyone that never expires
- **WHEN** an agent with the right picks a preset of 5.00, no expiry, 3 uses, anyone
- **THEN** the store has a code of 5.00 off the order with no end date, usable 3 times, once per buyer, not limited to a customer

#### Scenario: Contact who is not a customer
- **WHEN** an agent with the right opens "Discount code" in a conversation whose contact matches no customer
- **THEN** the presets for this customer only are shown as unavailable because the customer was not found, and a preset for anyone can still be used

#### Scenario: Code text is made by the helpdesk
- **WHEN** an agent with the right opens "Discount code"
- **THEN** the dialog offers no field for the code's text, and the created code's text is the one the helpdesk made

#### Scenario: Permission missing
- **WHEN** an administrator opens the Orders section on a connection without `write_discounts`
- **THEN** "Discount code" is not offered and a line names the missing permission

#### Scenario: No presets yet
- **WHEN** an administrator opens the Orders section in an account with no discount preset
- **THEN** "Discount code" is not offered and a line points to the settings page where presets are added

### Requirement: A created code leaves a record and failures are shown
Creating a code SHALL leave a private note in the conversation naming the agent, the preset, the code, its value and its expiry. When the store refuses the code, the dialog SHALL show the store's reason, nothing SHALL be inserted and no note SHALL be left.

#### Scenario: Record of a code
- **WHEN** an agent creates a code from the preset "Sorry" of 10 %
- **THEN** the conversation gets a private note naming the agent, "Sorry", the code, 10 % and the expiry date

#### Scenario: Store refuses the code
- **WHEN** the store refuses to create the code
- **THEN** the dialog shows the store's reason, the reply editor is unchanged and the conversation gets no note
