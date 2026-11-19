<script setup>
// The inboxes of the "AI agent" page with a tick each: the ones the agent is
// to answer in. The same rows serve connecting and, once connected, changing
// the inboxes (capability agent-inbox-selection). An inbox with another bot or
// Dialogflow is shown and cannot be ticked.
import { t } from '../i18n';

const props = defineProps({
  inboxes: { type: Array, default: () => [] },
  modelValue: { type: Array, default: () => [] },
  legend: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);

const toggle = inbox => {
  if (!inbox.selectable || props.disabled) return;
  const ids = props.modelValue;
  emit('update:modelValue', ids.includes(inbox.id) ? ids.filter(id => id !== inbox.id) : [...ids, inbox.id]);
};
const otherBot = inbox => (inbox.other_bot === 'Dialogflow' ? t('SETTINGS.AI_AGENT.HAS_DIALOGFLOW') : t('SETTINGS.AI_AGENT.HAS_OTHER_BOT'));
</script>

<template>
  <fieldset class="flex flex-col gap-2">
    <legend class="mb-1 font-medium">{{ legend }}</legend>
    <p v-if="inboxes.length === 0" class="text-n-slate-11">{{ t('SETTINGS.AI_AGENT.NO_INBOXES') }}</p>
    <label
      v-for="inbox in inboxes"
      :key="inbox.id"
      class="flex items-center gap-2"
      :class="{ 'text-n-slate-10': !inbox.selectable }"
      :data-testid="`inclamo-ai-inbox-${inbox.id}`"
      :data-selectable="inbox.selectable ? 'true' : 'false'"
    >
      <input type="checkbox" :checked="modelValue.includes(inbox.id)" :disabled="!inbox.selectable || disabled" @change="toggle(inbox)" />
      <span>{{ inbox.name }}</span>
      <span v-if="!inbox.selectable" class="text-xs" data-testid="inclamo-ai-other-bot">{{ otherBot(inbox) }}</span>
    </label>
  </fieldset>
</template>
