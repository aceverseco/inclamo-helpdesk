// The comparisons the rule editor offers for the attributes the overlay keeps
// on a conversation (their keys start with `shopify_`). Chatwoot's editor
// gives a number "equal to" and "not equal to" only, and a text no "contains",
// though its server compares both ways. Attributes of the account's own are
// left with Chatwoot's lists.
import {
  OPERATOR_TYPES_2,
  OPERATOR_TYPES_3,
  OPERATOR_TYPES_4,
} from 'dashboard/routes/dashboard/settings/automation/operators';

const OURS = 'shopify_';

// Equal, not equal, contains, does not contain, is present, is not present.
const TEXT = [
  ...OPERATOR_TYPES_2,
  ...OPERATOR_TYPES_3.filter(
    ({ value }) => !OPERATOR_TYPES_2.some(operator => operator.value === value)
  ),
];

const BY_TYPE = {
  // Equal, not equal, is present, is not present, greater than, less than.
  number: OPERATOR_TYPES_4,
  text: TEXT,
};

export const operatorsOf = attribute =>
  String(attribute?.attribute_key || '').startsWith(OURS)
    ? BY_TYPE[attribute.attribute_display_type]
    : undefined;

export default [operatorsOf];
