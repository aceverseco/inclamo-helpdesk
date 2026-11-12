<script setup>
// The "Call" section of the conversation sidebar: what the AI service filed
// about a finished call. Shown on call conversations only (sidebarSections).
import { computed } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { t } from '../i18n';
import { callOf } from '../calls';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  contactId: { type: [Number, String], default: undefined },
});

const store = useStore();
const call = computed(() => callOf(store?.getters?.getConversationById?.(props.conversationId)));

const rows = computed(() =>
  call.value
    ? [
        { name: 'line', label: t('CALL.LINE'), value: call.value.line },
        { name: 'caller', label: t('CALL.CALLER'), value: call.value.caller || t('CALL.NO_NUMBER') },
        { name: 'duration', label: t('CALL.DURATION'), value: call.value.duration },
        { name: 'ended', label: t('CALL.ENDED'), value: call.value.endedAt },
        { name: 'outcome', label: t('CALL.RESULT'), value: call.value.outcome },
        { name: 'matched', label: t('CALL.CONTACT'), value: call.value.matchedBy },
      ].filter(row => row.value)
    : []
);
</script>

<template>
  <div v-if="call" class="px-4 py-3 text-sm text-n-slate-12 flex flex-col gap-2" data-testid="inclamo-call-section">
    <span v-if="call.entry" class="font-medium" data-testid="inclamo-call-entry">{{ call.entry }}</span>
    <div v-for="row in rows" :key="row.name" class="flex items-start justify-between gap-3" :data-testid="`inclamo-call-${row.name}`">
      <span class="text-n-slate-11 shrink-0">{{ row.label }}</span>
      <span class="text-right break-words min-w-0">{{ row.value }}</span>
    </div>
    <a
      v-if="call.recording"
      :href="call.recording"
      target="_blank"
      rel="noopener noreferrer"
      class="text-n-blue-text"
      data-testid="inclamo-call-recording"
    >
      {{ t('CALL.RECORDING') }}
    </a>
  </div>
</template>
