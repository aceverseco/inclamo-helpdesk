// Stands in for Chatwoot's theme/colors.js (kept as colors.chatwoot.js): the
// brand colour reads the workspace's token, with Chatwoot's blue as its
// fallback. Every other colour is Chatwoot's.
import { colors as chatwoot } from './colors.chatwoot';

export const colors = {
  ...chatwoot,
  n: {
    ...chatwoot.n,
    brand: 'rgb(var(--inclamo-brand, 39 129 246) / <alpha-value>)',
  },
};
