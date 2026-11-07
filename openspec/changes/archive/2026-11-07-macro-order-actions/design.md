## Context

See proposal.md. Facts checked in Chatwoot v4.19.1:

- A macro's steps are validated against a fixed list (`Macro::ACTIONS_ATTRS`) and run one by one in `Macros::ExecutionService#perform`, each error swallowed, in a background job started by `POST macros/:id/execute`.
- The editor's step list is a constant (`settings/macros/constants.js`); a macro is run from the conversation sidebar (`conversation/Macros/List.vue`, `MacroItem.vue`) with no hook before the request.
- Our actions already go through one runner that checks role and scope, calls the store, writes the record and the private note.

## Goals / Non-Goals

**Goals:** no second implementation of refunds and cancellations; a money step never followed by a false message; the confirmation uses the same numbers the action will use.

**Non-Goals:** options on steps; order steps in rules; running order macros in bulk on many conversations (each conversation would need its own confirmation).

## Decisions

**D1. Steps are thin wrappers over the runner.** `inclamo_refund_full`, `inclamo_refund_shipping`, `inclamo_cancel_order`, `inclamo_replacement` build the same parameters the dialogs send, with the fixed options of the spec, and call the runner as the macro's user. The runner's refusals (role, scope, store) become the step's failure. The action row gets the macro's id.

**D2. The loop stops after a failed order step.** The overlay prepends `Macros::ExecutionService#perform`: Chatwoot's own steps keep their behaviour (errors swallowed, loop continues); an order step that fails writes the private note and breaks the loop. Alternative rejected: running order steps first regardless of their place. The administrator's order of steps is what the preview shows; reordering silently would surprise.

**D3. The allowed list is extended, not replaced.** `Macro#json_actions_format` is prepended so the four names pass validation; `AutomationRule#actions_attributes` is left alone, so a rule with an order step is rejected by Chatwoot's own validation.

**D4. Seam 4: macro steps registry and before-run hook.** `patches/0004-macro-steps.patch` adds `dashboard/extensions/macroSteps.js` (`{ steps: [], beforeRun: null }`), appends `steps` to the editor's list and awaits `beforeRun(macro, conversation)` in the sidebar's run handler, skipping the request when it resolves false. Our `beforeRun` returns true at once for macros without order steps.

Found in task 2.1 by reading v4.19.1. A macro is run from four places: the sidebar list, the reply box, the shortcut command and the bulk bar. The first three go through `useMacroExecution`'s `runMacro`, the fourth through `useBulkActions`. So the hook sits in those two, with the signature `beforeRun(macro, conversationIds)`. Ours refuses more than one conversation with a toast (D6) and otherwise mounts the confirmation in an app of its own. A step entry is `{ key, label(), description(), icon, available }`: the editor offers it while `available` is not false (ours: a working connection), and the preview names it always. The patch touches seven core files by a few lines each:
- `MacroEditor.vue`: appends the steps.
- `MacroNode.vue`: shows the description under the step.
- `MacroPreview.vue`: names the step.
- `helper/validations.js`: the steps take no parameters; without this Chatwoot's validator refuses to save them.
- `AutomationActionInput.vue` and `MacroNode.vue`: an optional chaining guard, so a macro holding a step the editor does not list does not break the page.
- `useMacroExecution.js` and `useBulkActions.js`: the hook.

The automation rule editor is left untouched.

**D5. The confirmation asks the backend for a preview** (`POST inclamo/macro_previews` with the macro and the conversation): the tied order's number, and per order step what will happen and the amount, computed by the same code that will run. When no order is tied the dialog says so and offers only "close". The server still checks everything at run time; the dialog is not the guard.

**D6. Bulk and API runs.** A run through the API with several conversations has no dialog; each conversation runs with its own tied order under the same server checks. The dashboard's bulk macro surface, if a release adds one, is covered by the same hook or the steps are hidden there.

**D7. Choices the spec left open, confirmed by the founder on 2026-11-07.**
- The cancel step gives Shopify the reason `CUSTOMER` (cancelled at the customer's request).
- The shipping refund notifies the customer, as the full refund does.
- A store outcome of "running" (cancellation not finished) or "unknown" (no confirmation) stops the macro like a refusal, so no message to the customer follows an action that may not have happened.
- When the preview already knows a step will be refused (no role, missing scope, nothing to refund), the dialog shows the reason and keeps "Run the macro": the server then stops the macro and writes the private note. Only "no order tied" offers close alone (D5).

## Risks / Trade-offs

- [A fourth patch] → same build gate and Chatwoot tests as the other seams.
- [The job runs after the request; the agent sees the result a moment later] → the private note is the result; the dialog closes with "running".
- [Between preview and run the order changes] → the runner works on fresh data; a refund larger than what is refundable is refused by the store and stops the macro.
