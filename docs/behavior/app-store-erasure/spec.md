# app-store-erasure

Behavior contract for this source revision.

Shopify asks every app of its App Store to erase a store's data after the app
is uninstalled, to erase one shopper's data, and to give the store owner one
shopper's data. The store app receives these requests and passes them on to
the hosted helpdesk over its signed provisioning channel; the calls are
described in `docs/app-store-erasure.md`. On the store app's request the
helpdesk erases a Shopify store's account, and turns the requests about one
shopper of a store into tickets the merchant's team acts on, with automatic
deletion when the team does not.

In this source revision every requirement below is built: the store's
erasure, and the requests about one shopper (the tickets in the account's
"Data requests" inbox, their deletion, holds and reminders, the data
requests and the counts). The scenarios that cannot run against the
installation the end-to-end tests drive are listed, with where they are
covered, in `scripts/check-e2e-coverage.mjs`. The operator's settings and
routines are in `docs/app-provisioning-setup.md`.

### Requirement: Erasure requests come only from the app

The calls of this capability SHALL be accepted only under the rules of the provisioning channel: signed with the shared secret, inside the time window, with a request id, and only on an installation whose operator set the secret. Any other request SHALL be refused without detail and SHALL erase, schedule or reveal nothing. An installation without the secret SHALL answer as if the addresses did not exist.

#### Scenario: An unsigned request to erase a store

- **WHEN** a request to erase a store arrives with a signature that does not match
- **THEN** it is refused as unauthorized and the store's account is unchanged

#### Scenario: A self-hosted installation

- **WHEN** any of the calls is sent to an installation without the shared secret
- **THEN** the answer is the same as for an unknown address

### Requirement: A store's erasure is scheduled, not immediate

On a valid request to erase a store whose account is suspended, the helpdesk SHALL schedule the erasure for the end of the installation's waiting time (7 days unless the operator set another value) and SHALL answer with the date after which the account will be destroyed. Until then the account SHALL stay suspended and whole. A repeated request SHALL answer the same date and SHALL NOT move it.

#### Scenario: The first request

- **WHEN** the app asks to erase a store whose account is suspended
- **THEN** the answer says the erasure is scheduled and gives the date, and the account still holds its conversations

#### Scenario: The request is repeated

- **WHEN** the app sends the same request two days later
- **THEN** the answer gives the same date as before

#### Scenario: A store without an account

- **WHEN** the app asks to erase a store that has no account
- **THEN** the answer says there is nothing to erase and nothing is recorded as scheduled

### Requirement: An active account is never erased by this channel

A request to erase a store whose account is active SHALL be refused and SHALL schedule nothing. When a suspended account with a scheduled erasure is restored, the schedule SHALL be withdrawn, and the account SHALL NOT be erased unless a new request arrives after it is suspended again.

#### Scenario: The store has reinstalled before the request arrives

- **WHEN** the app asks to erase a store whose account is active
- **THEN** the request is refused as naming an active account and nothing is scheduled

#### Scenario: A reinstall inside the waiting time

- **WHEN** a store's erasure is scheduled and the app restores the store's account before the date
- **THEN** the account is active with everything it held, and it is still there after the date has passed

### Requirement: A due erasure destroys the account and everything in it

When the date has passed and the account is still suspended, the helpdesk SHALL destroy the account with its conversations, messages, attached files, contacts, inboxes, labels, settings, the store connection with its key, and the AI agent's connection. After completion no record of the installation SHALL refer to the account, and the stored files of its messages SHALL be gone. Erasure SHALL NOT be reversible by any call.

#### Scenario: The date passes

- **WHEN** a scheduled erasure's date has passed and the account is suspended
- **THEN** within a day the account, its conversations, contacts and files no longer exist, and a request about the store's erasure answers that it is erased with the time

#### Scenario: The widget of an erased store

- **WHEN** a storefront still carries the erased account's website token and a shopper opens the chat
- **THEN** the widget is refused as for an unknown token

### Requirement: The people of an erased account

A user who belonged only to the erased account SHALL be deleted. A user who also belongs to another account SHALL keep that account, their password and their role there, and SHALL lose only the membership of the erased account.

#### Scenario: A user of one account

- **WHEN** an account is erased whose administrator belongs to no other account
- **THEN** that user no longer exists and their email can be used for a new user

#### Scenario: A user of two stores

- **WHEN** an account is erased whose administrator is also an administrator of another store's account
- **THEN** they still sign in and open the other account, and the erased one is not offered to them

### Requirement: What is kept after a store's erasure

After a store's erasure the helpdesk SHALL keep only the store's domain, that it was erased and when. A later request to provision the same store SHALL create a new, empty account with a new account id, and SHALL NOT bring back anything of the erased one.

#### Scenario: Installing again after erasure

- **WHEN** the app provisions a store whose account was erased
- **THEN** the answer says an account was created, its id differs from the erased one, and it holds no conversations and no contacts

### Requirement: A request to erase one shopper becomes a ticket

On a valid request naming a shopper of a store by email, phone or both, the helpdesk SHALL find, in that store's account only, every contact whose email or phone equals the given one, comparing emails without regard to letter case and phones by their digits. When at least one contact is found it SHALL make one ticket in the account's "Data requests" inbox that says that Shopify asked to erase a shopper's data, how many contacts and conversations were found, and the date of automatic deletion, 14 days after the ticket was made unless the operator set another value. The request itself SHALL delete nothing. A repeated request for the same shopper while the ticket is not done SHALL answer with the same ticket's state and SHALL NOT move the date. When no contact is found, no ticket SHALL be made and the answer SHALL say nothing is held. Contacts of other accounts SHALL NOT be counted or touched, even with the same email.

#### Scenario: A shopper with two conversations

- **WHEN** the app asks to erase a shopper whose email belongs to a contact with two conversations
- **THEN** the answer says the request is waiting and gives the date of automatic deletion, the account has a ticket naming one contact and two conversations with that date, and the contact and both conversations still exist

#### Scenario: The request is repeated

- **WHEN** the app sends the same request three days later
- **THEN** there is still one ticket and the answer gives the same date

#### Scenario: The same email in another store's account

- **WHEN** the same email belongs to a contact in another store's account
- **THEN** that account gets no ticket and its contact is unchanged

#### Scenario: A shopper the helpdesk does not know

- **WHEN** the app asks to erase a shopper whose email and phone match no contact of the store's account
- **THEN** the answer says nothing is held, no ticket is made and nothing is deleted

#### Scenario: Neither email nor phone

- **WHEN** the request names a shopper without an email and without a phone
- **THEN** it is refused as naming no shopper

### Requirement: Data-request tickets and erasure tickets are the administrators'

Tickets made by this capability SHALL live in an inbox of the account that only the account's administrators see, SHALL be told from shoppers' conversations by their inbox and a label, and SHALL NOT be held for the AI agent. Only an administrator of the account SHALL be able to delete, hold, lift a hold or mark a request answered; any other user SHALL be refused. Until a ticket is done it SHALL show the administrators the shopper's email and phone as Shopify gave them and SHALL link to each contact found.

#### Scenario: An agent of the team

- **WHEN** a user with the agent role lists the account's conversations
- **THEN** the ticket is not among them, and a request from that user to delete the shopper's data is refused

#### Scenario: An administrator opens the ticket

- **WHEN** an administrator opens a waiting erasure ticket
- **THEN** they see the shopper's email and phone, the contacts found with links, the date of automatic deletion, and the actions "Delete" and "Hold"

### Requirement: An administrator deletes the shopper's data from the ticket

When an administrator chooses "Delete" on an erasure ticket, the helpdesk SHALL delete every contact of the account that matches the request's email or phone at that moment, with all their conversations, messages and attached files, and SHALL remove what it keeps about the orders the request lists. It SHALL NOT replace a name, an email or a phone with a placeholder instead of deleting. A contact who is online SHALL be deleted like any other. The deletion SHALL be complete within a day, and the ticket SHALL then say it is done, when, and which administrator did it.

#### Scenario: Delete from the ticket

- **WHEN** an administrator chooses "Delete" on the ticket of a shopper with one contact and two conversations
- **THEN** within a day the contact, both conversations and their files no longer exist, and the ticket says it was done by that administrator with the time

#### Scenario: The shopper wrote again after the ticket was made

- **WHEN** the shopper started a new conversation after the ticket was made and an administrator then chooses "Delete"
- **THEN** the new conversation is deleted with the earlier ones

### Requirement: Without a decision the helpdesk deletes after the waiting time

When the date of automatic deletion has passed and the ticket is neither done nor held, the helpdesk SHALL delete the shopper's data exactly as an administrator's "Delete" does, and the ticket SHALL say it was done automatically, with the time. Before that date the helpdesk SHALL add reminders to the ticket that name the date. A suspended account SHALL be treated the same as an active one.

#### Scenario: Nobody touched the ticket

- **WHEN** fourteen days have passed since an erasure ticket was made and no administrator deleted or held
- **THEN** within a day the shopper's contact and conversations no longer exist, and the ticket says it was done automatically

#### Scenario: A reminder before the date

- **WHEN** seven days are left before the automatic deletion of a waiting ticket
- **THEN** the ticket has a new note that names the date

#### Scenario: A suspended account

- **WHEN** the date passes for a ticket of an account that is suspended
- **THEN** the shopper's data is deleted automatically

### Requirement: An administrator can hold the deletion with a reason

An administrator SHALL be able to put a hold on a waiting erasure ticket by giving a reason; a hold without a reason SHALL be refused. While a hold stands the helpdesk SHALL NOT delete the shopper's data automatically, SHALL show who held it, when and why, and SHALL remind in the ticket that the request is unmet. An administrator SHALL be able to lift the hold or to delete at any time. After a hold is lifted the automatic deletion SHALL happen on the original date, or within a day when that date has passed.

#### Scenario: A hold with a reason

- **WHEN** an administrator holds a ticket with the reason "open payment dispute" and the original date passes
- **THEN** the shopper's contact and conversations still exist, and the ticket shows the hold, its author, its time and its reason

#### Scenario: A hold without a reason

- **WHEN** an administrator tries to hold a ticket with an empty reason
- **THEN** the hold is refused and the date of automatic deletion is unchanged

#### Scenario: The hold is lifted after the date

- **WHEN** an administrator lifts a hold on a ticket whose original date has passed
- **THEN** within a day the shopper's data is deleted and the ticket says it was done automatically

### Requirement: A finished ticket holds no shopper data

When a shopper's data has been deleted, the ticket SHALL no longer show or store the shopper's email or phone in readable form, including in notes the team wrote in the ticket, and SHALL keep only what kind of request it was, when it was received, when it was done, and whether an administrator or the helpdesk did it. The same SHALL hold for a data-request ticket once it is marked answered.

#### Scenario: Reading a done ticket

- **WHEN** an administrator opens an erasure ticket after the deletion, in which a colleague had earlier written the shopper's email in a note
- **THEN** the ticket shows that it was done and when, and the email cannot be read anywhere in it

### Requirement: A request for one shopper's data becomes a ticket

On a valid request naming a shopper whose data the store owner is asked to provide, the helpdesk SHALL make one ticket in the account's "Data requests" inbox that says a shopper asked for their data and links to each matching contact with the number of conversations, so that the merchant's team can answer the shopper. The answer to the app SHALL say whether anything is held and how much, and SHALL NOT contain the shopper's name, email, phone, any message or any address of a contact. The request SHALL delete nothing. The ticket SHALL stay until an administrator marks it answered; the helpdesk SHALL remind in it and SHALL NOT close it by itself. When no contact matches, no ticket SHALL be made and the answer SHALL say nothing is held.

#### Scenario: A known shopper

- **WHEN** the app passes a data request for a shopper who has one contact with three conversations
- **THEN** the account has a ticket that links to that contact and names three conversations, and the answer says one contact and three conversations and holds no name, email, phone, message text or link

#### Scenario: An unknown shopper

- **WHEN** the app passes a data request for a shopper the account does not hold
- **THEN** the answer says nothing is held and no ticket is made

#### Scenario: The team has answered

- **WHEN** an administrator marks the data-request ticket answered
- **THEN** the ticket is closed and no longer shows the shopper's email or phone

### Requirement: The app learns the state of requests without shopper data

A request about a shopper SHALL be answered with its state: waiting with the date of automatic deletion, held, done with the time and whether it was done by the team or automatically, or nothing held. The app SHALL also be able to ask, with a signed request, how many of a store's requests are waiting, held and overdue, where an erasure is overdue when it is unmet 30 days after it was received and a data request likewise. Neither answer SHALL contain a shopper's name, email, phone, a hold's reason or any message.

#### Scenario: Asking about a held request

- **WHEN** the app repeats the erasure request for a shopper whose ticket is held
- **THEN** the answer says the request is held and holds neither the reason nor the administrator's name

#### Scenario: Counting a store's requests

- **WHEN** the app asks for the requests of a store that has one waiting erasure, one held erasure and one data request received 31 days ago
- **THEN** the answer says, for erasures, one waiting and one held and none overdue, and for data requests one waiting of which one is overdue, and names no shopper

### Requirement: Requests are recorded, and readable shopper data is kept only while a ticket is open

The helpdesk SHALL record every accepted request with its kind, the store's domain, when it was received, its state and when it was completed. For a request about a shopper the record SHALL hold the email and phone in readable form only while the ticket is open, encrypted at rest, and only as keyed digests afterwards. Request logs SHALL NOT contain a shopper's email or phone from these calls.

#### Scenario: Reading the record of a done request

- **WHEN** an operator reads the record of a completed shopper erasure
- **THEN** it shows the store, the kind, the times and whether it was done automatically, and no email or phone can be read from it

### Requirement: Erasures hold after a restore from backup

After the installation's database is restored from a backup, running the installation's re-apply routine SHALL erase again every store and every shopper whose erasure was completed after the backup was taken, as far as the record reaches, and SHALL report what it erased.

#### Scenario: A restore brings an erased shopper back

- **WHEN** a backup taken before a shopper's erasure is restored and the re-apply routine is run with the erasure record
- **THEN** the shopper's contact and conversations no longer exist

#### Scenario: A restore brings an erased store back

- **WHEN** a backup taken before a store's erasure is restored and the re-apply routine is run with the erasure record
- **THEN** the store's account no longer exists
