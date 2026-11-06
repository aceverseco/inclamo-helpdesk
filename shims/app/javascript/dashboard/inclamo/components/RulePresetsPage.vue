<script setup>
// Settings → Preset rules: ready automation rules that use what the store
// knows about the customer. Each switch creates an ordinary rule in Chatwoot's
// automation list, or deactivates the one it created.
import { ref, onMounted } from 'vue';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import InclamoAPI from '../api';
import { t } from '../i18n';

const AUTOMATION_ROUTE = 'automation_list';

const presets = ref([]);
const connected = ref(true);
const currency = ref('');
// What is typed in the value fields, by preset.
const values = ref({});
// What went wrong with the last switch, by preset.
const errors = ref({});
const loading = ref(true);
const failed = ref(false);
const busy = ref(false);

const show = data => {
  presets.value = data.presets;
  connected.value = data.store_connected;
  currency.value = data.currency || '';
  data.presets.forEach(preset => {
    if (preset.value !== null && preset.value !== undefined) values.value[preset.key] = preset.value;
  });
};

const load = async () => {
  try {
    show((await InclamoAPI.getRulePresets()).data);
  } catch (error) {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const apply = async (preset, active) => {
  busy.value = true;
  errors.value = { ...errors.value, [preset.key]: '' };
  try {
    const payload = preset.needs_value && active ? { active, value: values.value[preset.key] ?? '' } : { active };
    show((await InclamoAPI.switchRulePreset(preset.key, payload)).data);
  } catch (error) {
    errors.value = { ...errors.value, [preset.key]: error.response?.data?.message || t('SETTINGS.RULE_PRESETS.SWITCH_FAILED') };
  } finally {
    busy.value = false;
  }
};

const toggle = async (preset, event) => {
  await apply(preset, !preset.on);
  // A refused switch goes back to what the server holds.
  const now = presets.value.find(one => one.key === preset.key);
  if (event?.target) event.target.checked = now ? now.on : false;
};

// A new amount for a rule that is on is saved when the field is left.
const amountChanged = preset => {
  if (preset.on) apply(preset, true);
};

onMounted(load);
</script>

<template>
  <SettingsLayout :is-loading="loading" :loading-message="t('SETTINGS.RULE_PRESETS.LOADING')">
    <template #header>
      <BaseSettingsHeader :title="t('SETTINGS.RULE_PRESETS.TITLE')" :description="t('SETTINGS.RULE_PRESETS.INTRO')" />
    </template>
    <template #body>
      <p v-if="failed" class="text-sm text-n-ruby-11" data-testid="inclamo-presets-failed">{{ t('SETTINGS.RULE_PRESETS.FAILED') }}</p>
      <div v-else class="flex flex-col gap-3 text-sm text-n-slate-12" data-testid="inclamo-presets-page">
        <p v-if="!connected" class="text-n-amber-11" data-testid="inclamo-presets-not-connected">{{ t('SETTINGS.RULE_PRESETS.NOT_CONNECTED') }}</p>
        <div class="flex flex-col divide-y divide-n-weak">
          <div v-for="preset in presets" :key="preset.key" class="flex items-start justify-between gap-4 py-3" :data-testid="`inclamo-preset-${preset.key}`">
            <span class="flex flex-col gap-1">
              <span class="font-medium">{{ preset.name }}</span>
              <span class="text-xs text-n-slate-11">{{ preset.about }}</span>
              <label v-if="preset.needs_value" class="flex items-center gap-2 text-xs">
                <span>{{ t('SETTINGS.RULE_PRESETS.AMOUNT') }}</span>
                <input
                  v-model="values[preset.key]"
                  type="number"
                  min="0"
                  step="any"
                  class="!mb-0 !w-28"
                  :disabled="busy"
                  :aria-label="t('SETTINGS.RULE_PRESETS.AMOUNT')"
                  :data-testid="`inclamo-preset-${preset.key}-value`"
                  @change="amountChanged(preset)"
                />
                <span v-if="currency">{{ currency }}</span>
              </label>
              <span v-if="preset.rule_id" class="text-xs text-n-slate-11" :data-testid="`inclamo-preset-${preset.key}-rule`">
                {{ t('SETTINGS.RULE_PRESETS.RULE', { name: preset.rule_name }) }}
                <router-link :to="{ name: AUTOMATION_ROUTE }" class="text-n-blue-text">{{ t('SETTINGS.RULE_PRESETS.OPEN_LIST') }}</router-link>
              </span>
              <span v-if="errors[preset.key]" class="text-xs text-n-ruby-11" :data-testid="`inclamo-preset-${preset.key}-error`">{{ errors[preset.key] }}</span>
            </span>
            <input
              type="checkbox"
              :checked="preset.on"
              :disabled="busy"
              :aria-label="t('SETTINGS.RULE_PRESETS.SWITCH', { name: preset.name })"
              :data-testid="`inclamo-preset-${preset.key}-switch`"
              @change="toggle(preset, $event)"
            />
          </div>
        </div>
        <p class="text-xs text-n-slate-11">{{ t('SETTINGS.RULE_PRESETS.MARKER_NOTE') }}</p>
      </div>
    </template>
  </SettingsLayout>
</template>
