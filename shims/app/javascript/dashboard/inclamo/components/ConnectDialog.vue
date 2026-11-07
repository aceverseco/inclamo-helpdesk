<script setup>
import { ref, reactive, computed } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import InclamoAPI from '../api';
import { t } from '../i18n';

const emit = defineEmits(['connected']);

const dialog = ref(null);
const busy = ref(false);
const error = ref('');
const form = reactive({ shop_domain: '', kind: 'client_credentials', client_id: '', client_secret: '', access_token: '' });

const valid = computed(() => {
  if (!form.shop_domain.trim()) return false;
  return form.kind === 'legacy_token' ? !!form.access_token.trim() : !!form.client_id.trim() && !!form.client_secret.trim();
});

const open = domain => {
  Object.assign(form, { shop_domain: domain || '', kind: 'client_credentials', client_id: '', client_secret: '', access_token: '' });
  error.value = '';
  dialog.value.open();
};

const submit = async () => {
  busy.value = true;
  error.value = '';
  const payload =
    form.kind === 'legacy_token'
      ? { shop_domain: form.shop_domain, access_token: form.access_token }
      : { shop_domain: form.shop_domain, client_id: form.client_id, client_secret: form.client_secret };
  try {
    const { data } = await InclamoAPI.connect(payload);
    // The secret does not outlive the request on this side either.
    Object.assign(form, { client_secret: '', access_token: '' });
    dialog.value.close();
    emit('connected', data);
  } catch (failure) {
    error.value = failure.response?.data?.message || t('DIALOG.FAILED_PLAIN');
  } finally {
    busy.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('DIALOG.CONNECT.TITLE')"
    :confirm-button-label="t('DIALOG.CONNECT.CONFIRM')"
    :cancel-button-label="t('DIALOG.CLOSE')"
    :is-loading="busy"
    :disable-confirm-button="!valid"
    overflow-y-auto
    @confirm="submit"
  >
    <div class="flex flex-col gap-3 text-sm text-n-slate-12" data-testid="inclamo-connect-dialog">
      <label class="flex flex-col gap-1">
        <span>{{ t('DIALOG.CONNECT.DOMAIN') }}</span>
        <input v-model="form.shop_domain" type="text" :placeholder="t('DIALOG.CONNECT.DOMAIN_PLACEHOLDER')" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-connect-domain" />
      </label>
      <label v-for="kind in ['client_credentials', 'legacy_token']" :key="kind" class="flex items-center gap-2">
        <input v-model="form.kind" type="radio" :value="kind" :data-testid="`inclamo-connect-kind-${kind}`" />
        {{ t(`DIALOG.CONNECT.KIND.${kind}`) }}
      </label>
      <template v-if="form.kind === 'client_credentials'">
        <label class="flex flex-col gap-1">
          <span>{{ t('DIALOG.CONNECT.CLIENT_ID') }}</span>
          <input v-model="form.client_id" type="text" autocomplete="off" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-connect-client-id" />
        </label>
        <label class="flex flex-col gap-1">
          <span>{{ t('DIALOG.CONNECT.CLIENT_SECRET') }}</span>
          <input v-model="form.client_secret" type="password" autocomplete="off" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-connect-client-secret" />
        </label>
      </template>
      <label v-else class="flex flex-col gap-1">
        <span>{{ t('DIALOG.CONNECT.ACCESS_TOKEN') }}</span>
        <input v-model="form.access_token" type="password" autocomplete="off" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-connect-access-token" />
      </label>
      <div class="p-2 rounded-md bg-n-alpha-black2 text-xs text-n-slate-11">
        <p class="font-medium text-n-slate-12">{{ t('DIALOG.CONNECT.SCOPES') }}</p>
        <p>{{ t('DIALOG.CONNECT.SCOPES_READ') }}</p>
        <p>{{ t('DIALOG.CONNECT.SCOPES_WRITE') }}</p>
      </div>
      <p v-if="error" class="p-2 rounded-md bg-n-ruby-3 text-n-ruby-11" data-testid="inclamo-connect-error">{{ error }}</p>
    </div>
  </Dialog>
</template>
