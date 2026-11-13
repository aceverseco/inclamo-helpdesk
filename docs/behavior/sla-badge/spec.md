# sla-badge

Behavior contract for this source revision.

Shows staff the SLA deadline of each conversation where they choose what to work on next: on the rows of a conversation list and in the header of an open conversation, without opening the detailed SLA section.

### Requirement: A list row shows the SLA target that needs attention
A conversation shown in a conversation list SHALL carry one SLA badge when its timer has a target that needs attention. The badge SHALL name the target and show the time left, or the time overdue. While the first-response target is not reached, the badge SHALL show the first-response target. After the first response, the badge SHALL show the resolution target only when that target is soon or overdue. The badge SHALL appear in every list that shows conversations as rows: All, Mine, Unassigned, team queues and saved folders.

#### Scenario: New conversation waiting for a first reply
- **WHEN** a conversation with a 15-minute first-response target was created 6 minutes ago and no person has replied
- **THEN** its row shows a badge for the first response with about 9 minutes left

#### Scenario: Replied in time, resolution far away
- **WHEN** a person replied in time and the resolution target has 20 of its 24 hours left
- **THEN** the row shows no SLA badge

#### Scenario: Resolution deadline approaching
- **WHEN** a person replied in time and the resolution target has 2 of its 24 hours left
- **THEN** the row shows a badge for the resolution with about 2 hours left

### Requirement: The badge tells calm, soon and overdue apart
The badge SHALL have three looks. Calm: the target has time left. Soon: the time left is no more than a quarter of the target, and never less than the last five minutes of it. Overdue: the target was missed and is still unmet. An overdue badge SHALL show how long the target is overdue. The difference SHALL NOT be carried by colour alone: the overdue badge SHALL say that it is overdue in words.

#### Scenario: Calm
- **WHEN** a 15-minute first-response target has 10 minutes left
- **THEN** the badge has the calm look and shows the time left

#### Scenario: Soon
- **WHEN** a 15-minute first-response target has 4 minutes left
- **THEN** the badge has the soon look

#### Scenario: Overdue
- **WHEN** a 15-minute first-response target passed 12 minutes ago and no person has replied
- **THEN** the badge has the overdue look and says the first response is 12 minutes overdue

### Requirement: No badge when there is nothing to watch
A row SHALL show no SLA badge when the conversation has no timer, when the timer was stopped because its policy was deleted, when the conversation is resolved, or when no target needs attention. A first-response target that was missed and then answered SHALL NOT keep a badge on the row.

#### Scenario: Conversation older than the policy
- **WHEN** a conversation was created before any SLA policy covered its inbox
- **THEN** its row shows no SLA badge

#### Scenario: Late reply
- **WHEN** a person replies to a conversation whose first-response target was overdue
- **THEN** the overdue badge leaves the row

### Requirement: A paused timer is shown as paused
While a timer that counts business hours only is outside business hours, the badge SHALL show that the timer is paused, with the time it still has, and SHALL NOT count down.

#### Scenario: Night outside business hours
- **WHEN** a conversation's business-hours timer has 30 minutes left and the inbox is closed
- **THEN** the badge says the timer is paused with 30 minutes left, and the time does not change until the inbox opens

### Requirement: The conversation header shows the same badge
The header of an open conversation SHALL show the same SLA badge as its list row, under the same rules. Pointing at or focusing the badge SHALL show every target of the timer with its state and exact deadline. The "SLA" section of the side panel SHALL stay available.

#### Scenario: Agent opens an overdue conversation
- **WHEN** an agent opens a conversation whose first response is overdue
- **THEN** the header shows the overdue badge, and pointing at it lists the first-response and resolution targets with their deadlines

### Requirement: The badge stays current without reloading
The badge SHALL count down on its own. It SHALL change look when the target becomes soon or overdue, and SHALL update after a reply or a resolution, within about a minute and without the staff member reloading the page. A conversation that appears in the list while it is open SHALL get its badge the same way.

#### Scenario: Deadline passes while the list is open
- **WHEN** a staff member keeps a list open while a first-response target passes
- **THEN** the row's badge turns to the overdue look within about a minute

#### Scenario: Colleague replies
- **WHEN** another staff member sends the first reply to a conversation shown in the list
- **THEN** the first-response badge leaves the row within about a minute

### Requirement: The badge shows only what the staff member may see
SLA data for the badge SHALL be given only for conversations the staff member may open. A failure to read SLA data SHALL leave the rows without badges and SHALL NOT break the list.

#### Scenario: Agent without access to an inbox
- **WHEN** an agent asks for the SLA data of a conversation in an inbox they are not a member of
- **THEN** no SLA data for that conversation is returned

#### Scenario: SLA data unavailable
- **WHEN** the SLA data cannot be read
- **THEN** the list shows its conversations without SLA badges and works as before
