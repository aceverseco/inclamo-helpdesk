# sla-urgency-widget

Behavior contract for this source revision.

Shows staff, at the top of the workspace, where the time-critical work is: for each team queue, how many open conversations are overdue against their SLA, how many are due soon, and how many are neither.

### Requirement: The widget counts each queue's conversations by SLA urgency
The "SLA overview" widget in the workspace header SHALL show a summary: how many conversations are overdue and how many are due soon across the visible team queues, each conversation counted once however many queues list it. Activating the summary SHALL open the list of the account's visible team queues in the account's order. For each queue it SHALL show three numbers for the open conversations that queue lists for the staff member: overdue, soon, and the others. Overdue and soon SHALL be decided by the same rule as the SLA badge of a conversation. A conversation without a timer SHALL be counted among the others. The three numbers of a queue SHALL add up to the count shown next to that queue in the navigation.

#### Scenario: Mixed queue
- **WHEN** the queue "Delivery" lists seven open conversations for an agent: two with an overdue first response, one whose first response is due in three minutes of fifteen, and four with nothing pressing
- **THEN** the widget shows for "Delivery" 2 overdue, 1 soon and 4 others

#### Scenario: Conversation in two queues
- **WHEN** one overdue conversation is listed by both "Delivery" and "Return"
- **THEN** each of the two queues counts it as overdue and the summary counts it once

#### Scenario: Conversation without a timer
- **WHEN** a queue lists a conversation created before any SLA policy existed
- **THEN** that conversation is counted among the others

#### Scenario: Hidden queue
- **WHEN** an administrator hides a team queue
- **THEN** the widget no longer lists it

### Requirement: The numbers are the staff member's own
The counts SHALL cover only conversations the staff member may see, the same as the queue's list for that person.

#### Scenario: Agent limited to one inbox
- **WHEN** a queue holds three overdue conversations, one of them in an inbox the agent is not a member of
- **THEN** the widget shows that agent 2 overdue for the queue

### Requirement: The levels are told apart without relying on colour
Each number SHALL be labelled with its level in words available to assistive technology and on pointing. A level with zero conversations SHALL be shown subdued, not hidden, so the layout does not shift.

#### Scenario: Nothing overdue
- **WHEN** a queue has no overdue conversations
- **THEN** its overdue number reads 0 in the subdued look

### Requirement: A queue's entry opens the queue
Activating a queue's entry in the widget SHALL open that queue's list.

#### Scenario: Agent clicks the overdue count of "Damage"
- **WHEN** an agent activates the entry of "Damage"
- **THEN** the "Damage" queue opens

### Requirement: The widget stays current
The numbers SHALL refresh without reloading the page, within about a minute of a deadline passing, a reply or a resolution. A failure to read the numbers SHALL be shown inside the widget and SHALL NOT affect the rest of the header.

#### Scenario: Deadline passes
- **WHEN** a conversation in "Return" becomes overdue while the workspace is open
- **THEN** the overdue number of "Return" grows by one within about a minute

### Requirement: The widget follows the workspace widget rules
The widget SHALL be a workspace-header widget: present in the product's default header layout, removable and restorable by each staff member, and governed by the administrator's default and assignment like the other widgets. An account with no SLA policy SHALL show the widget with a short explanation and, for administrators, a link to the SLA settings, instead of rows of zeros.

#### Scenario: Agent removes the widget
- **WHEN** an agent removes "SLA overview" in "Customize widgets" and saves
- **THEN** the header no longer shows it for that agent, and other staff still see it

#### Scenario: Account without SLA policies
- **WHEN** an administrator of an account with no SLA policy looks at the widget
- **THEN** it says that no SLA policy exists and links to the SLA settings
