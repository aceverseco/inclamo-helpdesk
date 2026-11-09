<script setup>
// Settings → Discount codes: the presets an agent may give, and who may give
// them. An agent picks a preset and changes nothing; codes already made keep
// their conditions when a preset changes. Administrators always may give.
import { ref, reactive, onMounted } from 'vue';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import InclamoAPI from '../api';
import { presetConditions } from '../inserts';
import { t, has } from '../i18n';

const presets = ref([]);
const members = ref([]);
const currency = ref('');
const loading = ref(true);
const failed = ref(false);
const busy = ref(false);
const actionError = ref(false);
// null: no form; {}: a new preset; { id }: the preset being changed.
const editing = ref(null);
const errors = ref({});
const removing = ref(null);
const blank = () => ({ name: '', kind: 'percentage', value: '', expires_in_days: '30', usage_limit: '1', audience: 'customer' });
const form = reactive(blank());

const load = async () => {
  try {
    const [found, grants, connection] = await Promise.all([
      InclamoAPI.getDiscountPresets(),
      InclamoAPI.getDiscountGrants(),
      InclamoAPI.getConnection().catch(() => ({ data: {} })),
    ]);
    presets.value = found.data.presets;
    members.value = grants.data.members;
    currency.value = connection.data.shop_currency || '';
  } catch (error) {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const startNew = () => {
  Object.assign(form, blank());
  errors.value = {};
  editing.value = {};
};

const startEdit = preset => {
  Object.assign(form, {
    name: preset.name, kind: preset.kind, value: preset.value, audience: preset.audience,
    expires_in_days: preset.expires_in_days ? String(preset.expires_in_days) : '', usage_limit: String(preset.usage_limit),
  });
  errors.value = {};
  editing.value = { id: preset.id };
};

// The first reason the server gave for a field, in words.
const problem = field => {
  const code = (errors.value[field] || [])[0];
  if (!code) return '';
  const key = `SETTINGS.DISCOUNTS.ERRORS.${field}.${code}`;
  return has(key) ? t(key) : t('SETTINGS.DISCOUNTS.ERRORS.INVALID');
};

const save = async () => {
  busy.value = true;
  errors.value = {};
  // An empty expiry means the code never expires.
  const payload = { ...form, expires_in_days: String(form.expires_in_days).trim() };
  try {
    const { data } = editing.value.id ? await InclamoAPI.updateDiscountPreset(editing.value.id, payload) : await InclamoAPI.createDiscountPreset(payload);
    presets.value = data.presets;
    editing.value = null;
  } catch (error) {
    errors.value = error?.response?.data?.fields || { base: ['failed'] };
  } finally {
    busy.value = false;
  }
};

const remove = async preset => {
  busy.value = true;
  actionError.value = false;
  try {
    const { data } = await InclamoAPI.deleteDiscountPreset(preset.id);
    presets.value = data.presets;
    removing.value = null;
  } catch (error) {
    actionError.value = true;
  } finally {
    busy.value = false;
  }
};

const toggle = async (member, event) => {
  busy.value = true;
  actionError.value = false;
  try {
    const { data } = member.can_give ? await InclamoAPI.takeDiscountGrant(member.user_id) : await InclamoAPI.giveDiscountGrant(member.user_id);
    members.value = data.members;
  } catch (error) {
    actionError.value = true;
    if (event?.target) event.target.checked = member.can_give;
  } finally {
    busy.value = false;
  }
};

onMounted(load);
</script>

<template>
  <SettingsLayout :is-loading="loading" :loading-message="t('SETTINGS.DISCOUNTS.LOADING')">
    <template #header>
      <BaseSettingsHeader :title="t('SETTINGS.DISCOUNTS.TITLE')" :description="t('SETTINGS.DISCOUNTS.INTRO')" />
    </template>
    <template #body>
      <p v-if="failed" class="text-sm text-n-ruby-11" data-testid="inclamo-discounts-failed">{{ t('SETTINGS.DISCOUNTS.FAILED') }}</p>
      <div v-else class="flex flex-col gap-6 text-sm text-n-slate-12" data-testid="inclamo-discounts-page">
        <p v-if="actionError" role="alert" class="text-sm text-n-ruby-11" data-testid="inclamo-discounts-action-error">{{ t('SETTINGS.DISCOUNTS.ACTION_FAILED') }}</p>
        <section class="flex flex-col gap-2">
          <h3 class="text-base font-medium">{{ t('SETTINGS.DISCOUNTS.PRESETS') }}</h3>
          <p v-if="!presets.length" class="text-n-slate-11" data-testid="inclamo-presets-none">{{ t('SETTINGS.DISCOUNTS.NO_PRESETS') }}</p>
          <div v-for="preset in presets" :key="preset.id" class="flex items-start justify-between gap-2 rounded-md outline outline-1 outline-n-weak p-2" data-testid="inclamo-preset" :data-preset-id="preset.id">
            <span class="flex flex-col">
              <span class="font-medium" data-testid="inclamo-preset-name">{{ preset.name }}</span>
              <span class="text-xs text-n-slate-11" data-testid="inclamo-preset-conditions">{{ presetConditions(preset, currency) }}</span>
            </span>
            <span v-if="removing === preset.id" class="flex shrink-0 gap-3 text-xs">
              <span>{{ t('SETTINGS.DISCOUNTS.REMOVE_CONFIRM') }}</span>
              <button type="button" class="text-n-ruby-11" :disabled="busy" data-testid="inclamo-preset-remove-confirm" @click="remove(preset)">{{ t('SETTINGS.DISCOUNTS.REMOVE') }}</button>
              <button type="button" class="text-n-slate-11" @click="removing = null">{{ t('DIALOG.BACK') }}</button>
            </span>
            <span v-else class="flex shrink-0 gap-3 text-xs">
              <button type="button" class="text-n-blue-text" data-testid="inclamo-preset-edit" @click="startEdit(preset)">{{ t('SETTINGS.DISCOUNTS.EDIT') }}</button>
              <button type="button" class="text-n-ruby-11" data-testid="inclamo-preset-remove" @click="removing = preset.id">{{ t('SETTINGS.DISCOUNTS.REMOVE') }}</button>
            </span>
          </div>
          <button v-if="!editing" type="button" class="self-start rounded-md border border-n-weak px-3 py-1" data-testid="inclamo-preset-add" @click="startNew">{{ t('SETTINGS.DISCOUNTS.ADD') }}</button>

          <form v-if="editing" class="flex flex-col gap-3 rounded-md outline outline-1 outline-n-weak p-3" data-testid="inclamo-preset-form" @submit.prevent="save">
            <label class="flex flex-col gap-1">
              <span class="text-xs text-n-slate-11">{{ t('SETTINGS.DISCOUNTS.FIELDS.NAME') }}</span>
              <input v-model="form.name" type="text" maxlength="60" :placeholder="t('SETTINGS.DISCOUNTS.FIELDS.NAME_PLACEHOLDER')" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-preset-field-name" />
              <span v-if="problem('name')" class="text-xs text-n-ruby-11" data-testid="inclamo-preset-error-name">{{ problem('name') }}</span>
            </label>
            <div class="flex flex-wrap gap-3">
              <label class="flex flex-col gap-1">
                <span class="text-xs text-n-slate-11">{{ t('SETTINGS.DISCOUNTS.FIELDS.KIND') }}</span>
                <select v-model="form.kind" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-preset-field-kind">
                  <option value="percentage">{{ t('SETTINGS.DISCOUNTS.KINDS.percentage') }}</option>
                  <option value="amount">{{ t('SETTINGS.DISCOUNTS.KINDS.amount', { currency }) }}</option>
                </select>
              </label>
              <label class="flex flex-col gap-1">
                <span class="text-xs text-n-slate-11">{{ t('SETTINGS.DISCOUNTS.FIELDS.VALUE') }}</span>
                <input v-model="form.value" type="text" inputmode="decimal" class="w-28 rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-preset-field-value" />
                <span v-if="problem('value')" class="text-xs text-n-ruby-11" data-testid="inclamo-preset-error-value">{{ problem('value') }}</span>
              </label>
              <label class="flex flex-col gap-1">
                <span class="text-xs text-n-slate-11">{{ t('SETTINGS.DISCOUNTS.FIELDS.EXPIRES') }}</span>
                <input v-model="form.expires_in_days" type="text" inputmode="numeric" :placeholder="t('SETTINGS.DISCOUNTS.FIELDS.EXPIRES_PLACEHOLDER')" class="w-28 rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-preset-field-expires" />
                <span v-if="problem('expires_in_days')" class="text-xs text-n-ruby-11" data-testid="inclamo-preset-error-expires_in_days">{{ problem('expires_in_days') }}</span>
              </label>
              <label class="flex flex-col gap-1">
                <span class="text-xs text-n-slate-11">{{ t('SETTINGS.DISCOUNTS.FIELDS.USES') }}</span>
                <input v-model="form.usage_limit" type="text" inputmode="numeric" class="w-20 rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-preset-field-uses" />
                <span v-if="problem('usage_limit')" class="text-xs text-n-ruby-11" data-testid="inclamo-preset-error-usage_limit">{{ problem('usage_limit') }}</span>
              </label>
              <label class="flex flex-col gap-1">
                <span class="text-xs text-n-slate-11">{{ t('SETTINGS.DISCOUNTS.FIELDS.AUDIENCE') }}</span>
                <select v-model="form.audience" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-preset-field-audience">
                  <option value="customer">{{ t('DISCOUNTS.AUDIENCE.customer') }}</option>
                  <option value="anyone">{{ t('DISCOUNTS.AUDIENCE.anyone') }}</option>
                </select>
              </label>
            </div>
            <p v-if="problem('base')" class="text-xs text-n-ruby-11" data-testid="inclamo-preset-error-base">{{ problem('base') }}</p>
            <span class="flex gap-3">
              <button type="submit" class="rounded-md bg-n-brand px-3 py-1.5 text-white" :disabled="busy" data-testid="inclamo-preset-save">{{ t('SETTINGS.DISCOUNTS.SAVE') }}</button>
              <button type="button" class="text-n-slate-11" @click="editing = null">{{ t('DIALOG.BACK') }}</button>
            </span>
          </form>
        </section>

        <section class="flex flex-col gap-1">
          <h3 class="text-base font-medium">{{ t('SETTINGS.DISCOUNTS.WHO') }}</h3>
          <p class="text-xs text-n-slate-11">{{ t('SETTINGS.DISCOUNTS.WHO_INTRO') }}</p>
          <div class="flex flex-col divide-y divide-n-weak" data-testid="inclamo-discount-grants">
            <label v-for="member in members" :key="member.user_id" class="flex items-center justify-between gap-2 py-3" :data-testid="`inclamo-grant-${member.user_id}`">
              <span class="flex flex-col">
                <span>{{ member.name }}</span>
                <span class="text-xs text-n-slate-11">{{ member.switchable ? member.email : t('SETTINGS.ORDER_ROLES.ADMIN') }}</span>
              </span>
              <input type="checkbox" :checked="member.can_give" :disabled="!member.switchable || busy" :aria-label="t('SETTINGS.DISCOUNTS.ALLOW')" @change="toggle(member, $event)" />
            </label>
          </div>
        </section>
      </div>
    </template>
  </SettingsLayout>
</template>
