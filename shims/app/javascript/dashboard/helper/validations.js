// Stands in for Chatwoot's validations.js (kept as validations.chatwoot.js):
// a step the overlay adds to macros (dashboard/inclamo/macroSteps) takes no
// parameters, so its missing parameters are not an error.
import macroSteps from 'dashboard/inclamo/macroSteps';
import {
  ACTION_PARAMETERS_REQUIRED,
  validateActions as validateChatwootActions,
  validateAutomation as validateChatwootAutomation,
} from './validations.chatwoot';

const withoutOverlaySteps = (errors, actions) => {
  const keys = macroSteps.steps.map(step => step.key);
  (actions || []).forEach((action, index) => {
    const name = `action_${index}`;
    if (
      keys.includes(action.action_name) &&
      errors[name] === ACTION_PARAMETERS_REQUIRED
    ) {
      delete errors[name];
    }
  });
  return errors;
};

export const validateActions = actions =>
  withoutOverlaySteps(validateChatwootActions(actions), actions);

export const validateAutomation = automation =>
  withoutOverlaySteps(
    validateChatwootAutomation(automation),
    automation.actions
  );

// The rest is Chatwoot's, as it is.
export {
  ATTRIBUTE_KEY_REQUIRED,
  FILTER_OPERATOR_REQUIRED,
  VALUE_REQUIRED,
  VALUE_MUST_BE_BETWEEN_1_AND_998,
  ACTION_PARAMETERS_REQUIRED,
  ATLEAST_ONE_CONDITION_REQUIRED,
  ATLEAST_ONE_ACTION_REQUIRED,
  isEmptyValue,
  validateSingleFilter,
  parseRouteFilters,
  validateConditions,
} from './validations.chatwoot';
