// Stands in for Chatwoot's automationHelper.js (kept as
// automationHelper.chatwoot.js): the overlay may name the operators a rule
// offers for a custom attribute (dashboard/inclamo/ruleOperators). An
// attribute it does not name keeps Chatwoot's list for its type.
import ruleOperators from 'dashboard/inclamo/ruleOperators';
import {
  generateCustomAttributeTypes as generateChatwootTypes,
  getOperators as getChatwootOperators,
  isACustomAttribute,
} from './automationHelper.chatwoot';

const overlayOperators = attribute =>
  ruleOperators.map(entry => entry(attribute)).find(Boolean);

export const generateCustomAttributeTypes = (customAttributes, type) =>
  generateChatwootTypes(customAttributes, type).map((item, index) => {
    const operators = overlayOperators(customAttributes[index]);
    return operators ? { ...item, filterOperators: operators } : item;
  });

export const getOperators = (
  allCustomAttributes,
  automationTypes,
  automation,
  mode,
  key
) => {
  if (mode === 'edit') {
    const attribute = isACustomAttribute(allCustomAttributes, key);
    const operators = attribute && overlayOperators(attribute);
    if (operators) return operators;
  }
  return getChatwootOperators(
    allCustomAttributes,
    automationTypes,
    automation,
    mode,
    key
  );
};

// The rest is Chatwoot's, as it is.
export {
  getCustomAttributeInputType,
  isACustomAttribute,
  getCustomAttributeListDropdownValues,
  isCustomAttributeCheckbox,
  isCustomAttributeList,
  getOperatorTypes,
  getActionIcon,
  generateConditionOptions,
  generateTeamOptions,
  generateLabelOptions,
  getActionOptions,
  getConditionOptions,
  getFileName,
  getDefaultConditions,
  getDefaultActions,
  filterCustomAttributes,
  getStandardAttributeInputType,
  generateAutomationPayload,
  getCaptainConditionUsage,
  formatDelay,
  isCustomAttribute,
  generateCustomAttributes,
  getAttributes,
  getAutomationType,
  getInputType,
  getCustomAttributeType,
  showActionInput,
} from './automationHelper.chatwoot';
