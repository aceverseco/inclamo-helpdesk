// Whether the reply editor of an inbox keeps a link. Chatwoot's editor keeps
// the marks its formatting table lists for the channel: email and widget keep
// links, the plain-text channels (API, SMS, ...) strip a link to its text.
// Only the table and the inbox types are read here, not the editor itself.
import { FORMATTING } from 'dashboard/constants/editor';
import { INBOX_TYPES, TWILIO_CHANNEL_MEDIUM } from 'dashboard/helper/inbox';

// A Twilio inbox is formatted as WhatsApp or as SMS by its medium, as the editor does.
const channelOf = inbox => {
  if (inbox.channel_type === INBOX_TYPES.TWILIO) {
    return inbox.medium === TWILIO_CHANNEL_MEDIUM.WHATSAPP ? INBOX_TYPES.WHATSAPP : INBOX_TYPES.TWILIO;
  }
  return inbox.channel_type;
};

// An unknown inbox is taken as plain text, so that the address is never lost.
export const inboxTakesLinks = inbox => {
  if (!inbox?.channel_type) return false;
  const formatting = FORMATTING[channelOf(inbox)] || FORMATTING['Context::Default'];
  return (formatting.marks || []).includes('link');
};
