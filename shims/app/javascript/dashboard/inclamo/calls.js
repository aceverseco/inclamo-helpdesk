// A call of the AI phone agent, as its conversation holds it: the custom
// attributes `inclamo_call_*` the helpdesk writes when the AI service files
// the call. Only a conversation with `inclamo_call_outcome` is a call.
import { getCurrentInstance } from 'vue';
import { t, has } from './i18n';
import { dateTime } from './format';
import { duration } from './sla';

const words = (group, value) => (has(`CALL.${group}.${value}`) ? t(`CALL.${group}.${value}`) : String(value));

export const callOf = conversation => {
  const attributes = conversation?.custom_attributes || {};
  if (!attributes.inclamo_call_outcome) return null;
  const seconds = Number(attributes.inclamo_call_duration);
  return {
    entry: attributes.inclamo_call_entry ? words('ENTRY', attributes.inclamo_call_entry) : '',
    line: attributes.inclamo_call_line || '',
    caller: attributes.inclamo_call_caller || '',
    duration: attributes.inclamo_call_duration == null || Number.isNaN(seconds) ? '' : duration(seconds),
    endedAt: dateTime(attributes.inclamo_call_ended_at),
    // An outcome the helpdesk has no words for is shown as the AI service sent it.
    outcome: words('OUTCOME', attributes.inclamo_call_outcome),
    matchedBy: attributes.inclamo_call_matched_by ? words('MATCHED_BY', attributes.inclamo_call_matched_by) : '',
    // Only an https link is offered, whatever the attribute was edited to.
    recording: /^https:\/\//i.test(attributes.inclamo_call_recording || '') ? attributes.inclamo_call_recording : '',
  };
};

// Whether the conversation the sidebar shows is a call. Asked while the
// sidebar renders, so the conversations it reads are tracked.
export const isCall = conversationId => {
  const getters = getCurrentInstance()?.proxy?.$store?.getters;
  return Boolean(callOf(getters?.getConversationById?.(conversationId)));
};
