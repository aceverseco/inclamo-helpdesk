# sla-timers Specification

## Purpose
Lets a merchant set how fast conversations must get a first answer and be resolved, shows agents the time left on each conversation, and marks the conversations where a target was missed.

## Requirements

### Requirement: Administrators define SLA policies
An administrator SHALL have a settings page to create, change, reorder and delete SLA policies. A policy SHALL have a name, a first-response target, a resolution target (at least one of the two), a switch "count business hours only", and the inboxes it covers: all inboxes or chosen ones. Targets SHALL be entered in minutes, hours or days. The page SHALL be open to administrators only.

#### Scenario: Administrator creates a policy
- **WHEN** an administrator creates the policy "Standard" with a first response of 2 hours and a resolution of 2 days for all inboxes
- **THEN** the policy is in the list with those targets

#### Scenario: Policy without a target
- **WHEN** an administrator tries to save a policy with neither target
- **THEN** the policy is not saved and the page says a target is needed

#### Scenario: Agent cannot manage policies
- **WHEN** an agent opens the address of the SLA page
- **THEN** the page is not shown to them and the settings menu has no entry for it

### Requirement: A policy applies to new conversations of its inboxes
When a conversation is created in an inbox, the first policy in the list that covers that inbox SHALL be applied to it with the targets the policy has at that moment. Conversations that existed before the policy, and conversations in inboxes no policy covers, SHALL have no timer. Changing or deleting a policy SHALL NOT change targets already applied; deleting a policy SHALL stop its timers on conversations that are still open.

#### Scenario: New conversation gets a timer
- **WHEN** a customer writes into an inbox covered by "Standard"
- **THEN** the conversation's sidebar shows an "SLA" section with the policy's name and the time left to the first response and to the resolution

#### Scenario: Inbox without a policy
- **WHEN** a customer writes into an inbox no policy covers
- **THEN** the conversation has no "SLA" section

#### Scenario: Conversation older than the policy
- **WHEN** an administrator creates a policy and an agent opens a conversation that was created before it
- **THEN** that conversation has no "SLA" section

#### Scenario: Policy deleted
- **WHEN** an administrator deletes a policy while a conversation it covers is open
- **THEN** that conversation no longer shows a running timer and is not marked as missed later

### Requirement: The two timers stop on the first human reply and on resolution
The first-response timer SHALL stop when a person sends the first public reply in the conversation; private notes, messages sent by automation rules, macros run by rules, bots and campaign messages SHALL NOT stop it. The resolution timer SHALL stop the first time the conversation is resolved. A timer stopped before its target SHALL be shown as met with the time it took.

#### Scenario: Agent replies in time
- **WHEN** an agent sends a public reply before the first-response target
- **THEN** the section shows the first response as met and the resolution timer keeps running

#### Scenario: Automatic message does not count
- **WHEN** an automation rule sends a message to the customer and no person has replied
- **THEN** the first-response timer keeps running

#### Scenario: Resolved in time
- **WHEN** an agent resolves the conversation before the resolution target
- **THEN** the section shows the resolution as met

### Requirement: Business hours
For a policy with "count business hours only", a timer SHALL advance only inside the business hours of the conversation's inbox, as set in that inbox's settings, and SHALL be shown as paused outside them. For an inbox without business hours the timer SHALL advance at all times.

#### Scenario: Conversation created outside business hours
- **WHEN** a customer writes into an inbox that is closed now, covered by a policy that counts business hours only
- **THEN** the section shows the timers as paused with the full target time left

### Requirement: A missed target is marked once
When a timer passes its target, the conversation SHALL get the label "sla-missed" and a private note naming the target that was missed and its length, within two minutes of the moment it was missed, once per target. The section SHALL show that target as missed and by how much. A target met later SHALL stay shown as missed.

#### Scenario: First response missed
- **WHEN** no person replies before the first-response target
- **THEN** the conversation gets the label "sla-missed", a private note names the first-response target, and the section shows it as missed

#### Scenario: Resolution missed
- **WHEN** the conversation is still open when the resolution target passes
- **THEN** a private note names the resolution target and the section shows it as missed

### Requirement: Summary per policy
The SLA page SHALL show, per policy and for the last 7 or 30 days, the number of conversations the policy was applied to and the share of them that met the first-response target and the resolution target; conversations whose timer is still running SHALL be counted as neither.

#### Scenario: Summary after one met and one missed
- **WHEN** in the last 7 days one conversation of a policy met the first-response target and one missed it
- **THEN** the summary shows 2 conversations and 50 % for the first response
