# team-queues

Behavior contract for this source revision.

### Requirement: Team queues are shared by the whole account

The workspace navigation SHALL list the account's team queues under the existing "All", "Mine" and "Unassigned" queues, in the order the account has set. Every staff member of the account SHALL see the same team queues with the same names. A team queue SHALL be one definition for the account, not a copy per staff member. The existing "All", "Mine" and "Unassigned" queues SHALL keep working as before.

#### Scenario: Two staff members see the same queues

- **WHEN** an administrator and an agent of the same account open the workspace
- **THEN** both see the same team queues, with the same names, in the same order

#### Scenario: A new staff member gets the queues without setup

- **WHEN** an agent is added to the account and opens the workspace for the first time
- **THEN** the team queues are already in their navigation

#### Scenario: Native queues are unchanged

- **WHEN** an agent selects "Mine"
- **THEN** the list shows the open conversations assigned to them, as it did before team queues existed

### Requirement: Ready queues exist for every account

Every account SHALL have these team queues without anybody creating them: "Urgent", "Handed over by AI", "Overdue", "Delivery", "Cancellation", "Damage", "Missing parts" and "Return". They SHALL exist for accounts created before this capability as well as for new ones.

#### Scenario: A new account has the ready queues

- **WHEN** an account is created and its administrator opens the workspace
- **THEN** the navigation lists the eight ready queues

#### Scenario: An existing account gets the ready queues on upgrade

- **WHEN** an installation with existing accounts is upgraded to a version with team queues
- **THEN** each of those accounts has the eight ready queues

### Requirement: A queue lists the open conversations that match it

Opening a team queue SHALL show the open conversations that match it, in the conversation list, with the list's usual sorting, paging and live updates. Membership SHALL be:

- "Urgent": the conversation's priority is urgent.
- "Handed over by AI": the conversation carries one of the labels the AI agent's hand-over sets, whether the agent handed over itself, failed, or reached its limit.
- "Overdue": an SLA target of the conversation was missed and is still unmet: the first response was missed and nobody has answered yet, or the resolution was missed.
- A category queue: the conversation carries that category's label, set by staff or a rule, or the label of the same category that the AI agent sets.

A conversation SHALL leave a queue as soon as it stops matching, and SHALL leave every team queue when it is resolved.

#### Scenario: Urgent conversation appears

- **WHEN** an agent sets an open conversation's priority to urgent
- **THEN** the conversation is in "Urgent"

#### Scenario: AI hand-over appears and leaves

- **WHEN** the AI agent hands a conversation over to people
- **THEN** the conversation is in "Handed over by AI"
- **WHEN** an agent later resolves it
- **THEN** it is no longer in that queue

#### Scenario: Missed first response appears and leaves

- **WHEN** a conversation's first-response target passes without an answer
- **THEN** the conversation is in "Overdue"
- **WHEN** an agent answers and the resolution target has not been missed
- **THEN** the conversation is no longer in "Overdue"

#### Scenario: Missed resolution stays until resolved

- **WHEN** a conversation's resolution target passes while it is open
- **THEN** the conversation is in "Overdue" until it is resolved

#### Scenario: Category label puts a conversation in its queue

- **WHEN** an agent, or one of the store's automation rules, adds the delivery label to an open conversation
- **THEN** the conversation is in "Delivery"

#### Scenario: The AI agent's category label counts too

- **WHEN** the AI agent labels an open conversation as a return
- **THEN** the conversation is in "Return"

#### Scenario: Snoozed conversation is not listed

- **WHEN** an agent snoozes a conversation that is in "Urgent"
- **THEN** the conversation is not in "Urgent" until it is open again

### Requirement: Queues work without the AI subscription

Team queues SHALL work for an account with no AI agent connected. "Handed over by AI" SHALL then be empty, and no queue SHALL depend on the AI service to fill or to show.

#### Scenario: Account without an AI agent

- **WHEN** an account with no AI agent connected has an urgent conversation and a conversation labelled as a return
- **THEN** "Urgent" and "Return" each list their conversation and "Handed over by AI" is empty

### Requirement: A queue never widens what a staff member may see

A team queue SHALL list only conversations the staff member could already open: an agent SHALL NOT see, through a queue or its count, a conversation of an inbox they are not a member of.

#### Scenario: Agent outside an inbox

- **WHEN** an urgent conversation is in an inbox agent A is not a member of
- **THEN** agent A's "Urgent" neither lists nor counts it, and an administrator's "Urgent" does

### Requirement: Each queue shows how many conversations it holds

Each team queue in the navigation SHALL show the number of conversations it currently lists for that staff member. The number SHALL equal the number of conversations the queue shows when opened, and SHALL update without reloading the page after conversations enter or leave the queue. When the number cannot be obtained, the navigation SHALL keep the last known number instead of showing zero.

#### Scenario: Count matches the list

- **WHEN** three open conversations are urgent
- **THEN** "Urgent" shows 3 and lists those three

#### Scenario: Count follows a change

- **WHEN** an agent resolves one of them
- **THEN** "Urgent" shows 2 without a page reload

#### Scenario: Count request fails

- **WHEN** "Urgent" shows 2 and the next refresh of the numbers fails
- **THEN** "Urgent" still shows 2

### Requirement: Administrators manage team queues

An administrator SHALL have a settings page listing the team queues, where they can rename a queue, change the order, hide a queue and show it again, and restore a ready queue to the name, position and membership it shipped with. A hidden queue SHALL not appear in anybody's navigation. Agents SHALL NOT be able to open the page, and SHALL NOT be offered any control that edits or deletes a team queue.

#### Scenario: Rename

- **WHEN** an administrator renames "Missing parts" to "Parts requests"
- **THEN** every staff member's navigation shows "Parts requests" and it lists the same conversations

#### Scenario: Hide and show

- **WHEN** an administrator hides "Cancellation"
- **THEN** no staff member's navigation lists it
- **WHEN** the administrator shows it again
- **THEN** it returns at its place in the order

#### Scenario: Reorder

- **WHEN** an administrator moves "Return" to the first place
- **THEN** every staff member's navigation lists "Return" first among the team queues

#### Scenario: Restore

- **WHEN** an administrator restores the renamed "Parts requests"
- **THEN** it is named "Missing parts" again

#### Scenario: Agent cannot manage

- **WHEN** an agent opens the address of the team queues page, or opens a team queue in the conversation list
- **THEN** the page is not shown to them, the settings menu has no entry for it, and the list offers no edit or delete control for the queue

### Requirement: Opening a queue that is not available

Opening the address of a team queue that is hidden or does not exist SHALL show the "All" queue and a message that the queue is not available, never an empty list presented as that queue.

#### Scenario: Link to a hidden queue

- **WHEN** an agent opens a saved link to "Cancellation" after an administrator hid it
- **THEN** they see "All" and a message that the queue is not available

### Requirement: Installing the ready queues is repeatable

Installing the ready queues again, as every upgrade does, SHALL create no duplicate queue, SHALL NOT change the name, order or hidden state an administrator has set, and SHALL NOT show a queue the administrator hid.

#### Scenario: Second installation changes nothing

- **WHEN** an administrator has renamed one ready queue and hidden another, and the installation runs again
- **THEN** the account still has eight ready queues, the renamed one keeps its name and the hidden one stays hidden
