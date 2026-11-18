# interface-language

Behavior contract for this source revision.

### Requirement: Own screens follow the chosen interface language

The Helpdesk's own dashboard screens SHALL be shown in the same interface language as the rest of the dashboard: the language set in the staff member's profile, else the language of the account, else English. When that language changes, the own screens SHALL change together with the rest of the dashboard. The choice SHALL be available to every account and every staff member; nothing is switched on per installation or per account.

#### Scenario: Profile language is Ukrainian

- **WHEN** a staff member whose profile language is Ukrainian opens the workspace and a conversation
- **THEN** the workspace navigation and the Orders section beside the conversation are in Ukrainian

#### Scenario: Account language applies when the profile has none

- **WHEN** an account's language is Ukrainian and a staff member has set no language in the profile
- **THEN** that staff member sees the workspace navigation in Ukrainian

#### Scenario: Profile language wins over the account's

- **WHEN** an account's language is Ukrainian and a staff member's profile language is English
- **THEN** that staff member sees the workspace navigation in English

#### Scenario: Language is switched

- **WHEN** a staff member chooses Ukrainian as the language in the profile settings
- **THEN** the workspace navigation is in Ukrainian at once, without reloading the page

### Requirement: A missing wording is shown in English

Where an own screen has no wording in the chosen language, it SHALL show the English wording. It SHALL NOT show a key, an empty label or a placeholder name.

#### Scenario: Language the own screens are not translated into

- **WHEN** a staff member whose profile language is German opens the profile settings
- **THEN** the workspace navigation is in English, while Chatwoot's page beside it is in German

#### Scenario: Single missing text

- **WHEN** the chosen language is Ukrainian and one text of a screen has no Ukrainian wording
- **THEN** that text is shown in English and every other text of the screen in Ukrainian

### Requirement: English reads as before

With English as the interface language, every own screen SHALL show the same texts as before this capability existed.

#### Scenario: English interface

- **WHEN** a staff member whose interface language is English opens the workspace
- **THEN** its navigation reads in English as before

### Requirement: Own screens are complete in Ukrainian

Every text of the own dashboard screens SHALL have a Ukrainian wording. Left as they are: names of products and companies (Shopify, Inclamo, SLA), technical identifiers the staff member must type or recognise exactly (access scopes, domains, code samples), and data that comes from the store, the customer or the server.

#### Scenario: No English left on an own screen

- **WHEN** an administrator with a Ukrainian interface opens each of the Helpdesk's own settings pages and the workspace
- **THEN** each page carries its Ukrainian title and not its English one

#### Scenario: Identifier kept

- **WHEN** a message names missing access scopes
- **THEN** the sentence is in Ukrainian and the scope names are unchanged, for example `read_orders`

### Requirement: Ukrainian counts take the right form

A text with a number SHALL use the Ukrainian form that number requires: one form for 1, 21, 31; another for 2–4, 22–24; a third for 0, 5–20, 25–30. This SHALL hold on every screen of the dashboard for any text that provides the three forms. A text that provides two forms SHALL use the first for 1 and the second for every other number, as before.

#### Scenario: Three forms on an own screen

- **WHEN** an SLA policy has applied to 1, then 3, then 5 conversations and an administrator with a Ukrainian interface opens the SLA policies
- **THEN** the policy's summary reads "1 розмова", then "3 розмови", then "5 розмов"

#### Scenario: Two-form text of Chatwoot is unchanged

- **WHEN** a Chatwoot text that has two Ukrainian forms is shown for 1, 2 and 5
- **THEN** it reads as it did before: the first form for 1, the second for 2 and for 5

#### Scenario: Other languages are untouched

- **WHEN** the interface language is English
- **THEN** texts with numbers read as before

### Requirement: Dates, times and money follow the interface language

On the own screens, dates, times and amounts of money SHALL be written by the conventions of the interface language, not of the browser. The currency of an amount SHALL remain the one the store reports. The short age of a moment on the workspace ("5m", "2h") SHALL be worded in the interface language.

#### Scenario: Date in Ukrainian

- **WHEN** a staff member with a Ukrainian interface, in a browser set to English, sees an order placed on 12 November 2026
- **THEN** the date reads in Ukrainian, for example "12 лист. 2026 р."

#### Scenario: Amount in Ukrainian

- **WHEN** the same staff member sees an order total of 1234.5 US dollars
- **THEN** it is written the Ukrainian way with the dollar currency, for example "1 234,50 USD", and not "$1,234.50"

### Requirement: One word for one thing

The Ukrainian wording of the own screens SHALL name each thing with the single term the published glossary gives it. In particular a conversation is "розмова", an inbox is "вхідні", to resolve is "вирішити", a team member who answers is "агент".

#### Scenario: Conversation has one name

- **WHEN** the Ukrainian wording of all own screens is searched for "бесід" and "діалог"
- **THEN** neither is found
