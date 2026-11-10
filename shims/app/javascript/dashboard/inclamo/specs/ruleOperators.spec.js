import { generateCustomAttributeTypes, getOperators } from 'dashboard/helper/automationHelper';
import { OPERATOR_TYPES_1, OPERATOR_TYPES_3 } from 'dashboard/routes/dashboard/settings/automation/operators';
import registry from 'dashboard/extensions/ruleOperators';
import ruleOperators from '../ruleOperators';

const definition = (key, type) => ({ attribute_key: key, attribute_display_name: key, attribute_display_type: type });
const offered = (key, type) =>
  generateCustomAttributeTypes([definition(key, type)], 'conversation_attribute')[0].filterOperators.map(operator => operator.value);

describe('rule operators of the store attributes', () => {
  it('is what Chatwoot reads through the seam', () => {
    expect(registry).toBe(ruleOperators);
  });

  it('offers "greater than" and "less than" for a number the overlay keeps', () => {
    expect(offered('shopify_customer_spent', 'number')).toEqual([
      'equal_to',
      'not_equal_to',
      'is_present',
      'is_not_present',
      'is_greater_than',
      'is_less_than',
    ]);
  });

  it('offers "contains" for a text the overlay keeps', () => {
    expect(offered('shopify_customer_tags', 'text')).toEqual([
      'equal_to',
      'not_equal_to',
      'contains',
      'does_not_contain',
      'is_present',
      'is_not_present',
    ]);
  });

  it('leaves a list of the overlay with Chatwoot\'s operators', () => {
    expect(offered('shopify_is_customer', 'list')).toEqual(OPERATOR_TYPES_1.map(operator => operator.value));
  });

  it('leaves the account\'s own attributes with Chatwoot\'s operators', () => {
    expect(offered('lifetime_value', 'number')).toEqual(OPERATOR_TYPES_1.map(operator => operator.value));
    expect(offered('segment', 'text')).toEqual(OPERATOR_TYPES_3.map(operator => operator.value));
  });

  it('offers the same when a saved rule is opened', () => {
    const all = [definition('shopify_last_order_total', 'number')];

    expect(getOperators(all, {}, {}, 'edit', 'shopify_last_order_total').map(operator => operator.value)).toContain('is_greater_than');
  });
});
