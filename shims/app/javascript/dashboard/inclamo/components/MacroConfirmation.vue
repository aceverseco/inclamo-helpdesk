<script setup>
// The confirmation before a macro with order steps runs: the order tied to the
// conversation, and what each order step will do to it, as the server works
// it out with the code the steps run with. Answers true only on "Run".
import { ref, computed, onMounted } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import InclamoAPI from '../api';
import { t, has } from '../i18n';
import { money } from '../format';

const props = defineProps({
  macro: { type: Object, required: true },
  conversationId: { type: [Number, String], required: true },
});
const emit = defineEmits(['answer']);

const dialog = ref(null);
const preview = ref(null);
const failed = ref(false);
let answered = false;

const loading = computed(() => !preview.value && !failed.value);
const order = computed(() => preview.value?.order || null);
const canRun = computed(() => !!order.value);

const answer = value => {
  if (answered) return;
  answered = true;
  emit('answer', value);
  dialog.value?.close();
};

const why = step => {
  if (step.refusal === 'store_refused' && step.message) return t('MACRO_STEPS.WHY_NOT.store_refused', { message: step.message });
  const key = `MACRO_STEPS.WHY_NOT.${step.refusal}`;
  return has(key) ? t(key, { scopes: (step.missing_scopes || []).join(', ') }) : t('MACRO_STEPS.WHY_NOT.other');
};

const effect = step => {
  if (step.refusal) return t('MACRO_STEPS.CONFIRM.WILL_STOP', { reason: why(step) });
  if (step.step === 'inclamo_cancel_order' && !step.amount) return t('MACRO_STEPS.STEPS.inclamo_cancel_order.EFFECT_UNPAID');
  return t(`MACRO_STEPS.STEPS.${step.step}.EFFECT`, { amount: money(step.amount, step.currency), units: step.units });
};

onMounted(async () => {
  dialog.value.open();
  try {
    const { data } = await InclamoAPI.macroPreview(props.macro.id, props.conversationId);
    preview.value = data;
  } catch (error) {
    failed.value = true;
  }
});
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('MACRO_STEPS.CONFIRM.TITLE', { name: macro.name })"
    :confirm-button-label="t('MACRO_STEPS.CONFIRM.RUN')"
    :cancel-button-label="canRun ? t('MACRO_STEPS.CONFIRM.DONT_RUN') : t('MACRO_STEPS.CONFIRM.CLOSE')"
    :show-confirm-button="canRun"
    overflow-y-auto
    @confirm="answer(true)"
    @close="answer(false)"
  >
    <div class="flex flex-col gap-3 text-sm text-n-slate-12" data-testid="inclamo-macro-confirmation">
      <p v-if="loading" data-testid="inclamo-macro-loading">{{ t('MACRO_STEPS.CONFIRM.LOADING') }}</p>
      <p v-else-if="failed" class="p-2 rounded-md bg-n-ruby-3 text-n-ruby-11" data-testid="inclamo-macro-failed">
        {{ t('MACRO_STEPS.CONFIRM.FAILED') }}
      </p>
      <p v-else-if="!order" class="p-2 rounded-md bg-n-amber-3 text-n-amber-11" data-testid="inclamo-macro-no-order">
        {{ t('MACRO_STEPS.CONFIRM.NO_ORDER') }}
      </p>
      <template v-else>
        <p class="font-medium" data-testid="inclamo-macro-order">{{ t('MACRO_STEPS.CONFIRM.ON_ORDER', { number: order.number }) }}</p>
        <ul class="flex flex-col gap-2 m-0 p-0 list-none">
          <li
            v-for="step in preview.steps"
            :key="step.position"
            class="flex flex-col gap-0.5 p-2 rounded-md"
            :class="step.refusal ? 'bg-n-ruby-3 text-n-ruby-11' : 'bg-n-alpha-black2'"
            :data-testid="`inclamo-macro-step-${step.step}`"
          >
            <span class="font-medium">{{ t(`MACRO_STEPS.STEPS.${step.step}.LABEL`) }}</span>
            <span>{{ effect(step) }}</span>
          </li>
        </ul>
        <p class="text-n-slate-11">{{ t('MACRO_STEPS.CONFIRM.CHECKED_AGAIN') }}</p>
      </template>
    </div>
  </Dialog>
</template>
