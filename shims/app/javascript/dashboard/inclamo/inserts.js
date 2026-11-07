// What the reply inserts put into the reply, and how a discount preset reads.
// Nothing of the editor is imported here: the settings page uses this too.
import { t } from './i18n';
import { money } from './format';

const linkText = text => text.replace(/([[\]\\])/g, '\\$1');

// One line per product: "Title, price" with the title as a link where the
// editor keeps links, "Title, price: URL" where it does not, and no link for a
// product that is not in the online store.
export const productLine = ({ product, variant }, { links }) => {
  const name = variant?.title ? `${product.title} — ${variant.title}` : product.title;
  const price = variant ? money(variant.price.amount, variant.price.currency) : '';
  const head = price ? `${name}, ${price}` : name;
  const url = product.online_store_url;
  if (!url) return head;
  if (!links) return `${head}: ${url}`;
  return price ? `[${linkText(name)}](${url}), ${price}` : `[${linkText(name)}](${url})`;
};

export const presetValue = (preset, currency) =>
  preset.kind === 'percentage' ? t('DISCOUNTS.VALUE_PERCENTAGE', { value: preset.value }) : money(preset.value, currency);

// "10% off the order · 30 days · once · this customer only"
export const presetConditions = (preset, currency) => {
  let expiry = t('DISCOUNTS.CONDITIONS.NEVER');
  if (preset.expires_in_days === 1) expiry = t('DISCOUNTS.CONDITIONS.ONE_DAY');
  else if (preset.expires_in_days) expiry = t('DISCOUNTS.CONDITIONS.DAYS', { count: preset.expires_in_days });
  const uses = preset.usage_limit === 1 ? t('DISCOUNTS.CONDITIONS.ONCE') : t('DISCOUNTS.CONDITIONS.TIMES', { count: preset.usage_limit });
  return [t('DISCOUNTS.CONDITIONS.OFF', { value: presetValue(preset, currency) }), expiry, uses, t(`DISCOUNTS.AUDIENCE.${preset.audience}`)].join(' · ');
};
