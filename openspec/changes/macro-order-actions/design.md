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

**D5. The confirmation asks the backend for a preview** (`POST inclamo/macro_previews` with the macro and the conversation): the tied order's number, and per order step what will happen and the amount, computed by the same code that will run. When no order is tied the dialog says so and offers only "close". The server still checks everything at run time; the dialog is not the guard.

**D6. Bulk and API runs.** A run through the API with several conversations has no dialog; each conversation runs with its own tied order under the same server checks. The dashboard's bulk macro surface, if a release adds one, is covered by the same hook or the steps are hidden there.

## Risks / Trade-offs

- [A fourth patch] → same build gate and Chatwoot tests as the other seams.
- [The job runs after the request; the agent sees the result a moment later] → the private note is the result; the dialog closes with "running".
- [Between preview and run the order changes] → the runner works on fresh data; a refund larger than what is refundable is refused by the store and stops the macro.
