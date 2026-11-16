// Stands in for Chatwoot's facebookScopes.js (kept as
// facebookScopes.chatwoot.js): connecting or reauthorizing a Facebook page
// always asks for the Instagram scopes too, so one consent covers Messenger
// and the Instagram account linked to the page.
import { buildFacebookLoginScopes as buildChatwootScopes } from './facebookScopes.chatwoot';

export const buildFacebookLoginScopes = (options = {}) =>
  buildChatwootScopes({ ...options, includeInstagramScopes: true });

// The rest is Chatwoot's, as it is.
export {
  FACEBOOK_PAGE_SCOPES,
  INSTAGRAM_SCOPES,
} from './facebookScopes.chatwoot';
