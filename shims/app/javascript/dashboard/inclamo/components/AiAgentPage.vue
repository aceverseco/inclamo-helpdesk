<script setup>
// Settings → AI agent, for administrators (design D9). Without a connection it
// says what the agent does and where to get it, and takes a connection code
// and the inboxes the agent answers in. With one it shows the inboxes, the
// state, the agent's last reply and the last failed delivery, and offers to
// disconnect. It never shows a conversation's content.
import { ref, reactive, computed, onMounted } from 'vue';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import InclamoAPI from '../api';
import { t, has } from '../i18n';
import { dateTime } from '../format';

const page = ref(null);
const loading = ref(true);
const failed = ref(false);
const busy = ref(false);
const error = ref('');
const notice = ref('');
const confirmDialog = ref(null);
const form = reactive({ code: '', inboxIds: [] });

const state = computed(() => page.value?.state || 'never_connected');
const connected = computed(() => !!page.value?.connected);
const connection = computed(() => page.value?.connection || {});
const inboxes = computed(() => page.value?.inboxes || []);
const connectedInboxes = computed(() => inboxes.value.filter(inbox => inbox.connected));
const canConnect = computed(() => page.value?.encryption_configured && form.code.trim() !== '' && form.inboxIds.length > 0 && !busy.value);

const show = data => {
  page.value = data;
  form.inboxIds = form.inboxIds.filter(id => (data.inboxes || []).some(inbox => inbox.id === id && inbox.selectable));
};

const load = async () => {
  try {
    const { data } = await InclamoAPI.getAiConnection();
    show(data);
  } catch (failure) {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const errorText = failure => {
  const data = failure.response?.data || {};
  if (data.error === 'refused' && data.message) return data.message;
  if (data.error && has(`SETTINGS.AI_AGENT.ERRORS.${data.error}`)) return t(`SETTINGS.AI_AGENT.ERRORS.${data.error}`);
  return data.message || t('SETTINGS.AI_AGENT.ERRORS.not_answered');
};

const connect = async () => {
  busy.value = true;
  error.value = '';
  notice.value = '';
  try {
    const { data } = await InclamoAPI.connectAi({ connection_code: form.code.trim(), inbox_ids: form.inboxIds });
    // The code is used once; it does not stay on the page.
    form.code = '';
    show(data);
  } catch (failure) {
    error.value = errorText(failure);
  } finally {
    busy.value = false;
  }
};

const toggle = inbox => {
  if (!inbox.selectable) return;
  form.inboxIds = form.inboxIds.includes(inbox.id) ? form.inboxIds.filter(id => id !== inbox.id) : [...form.inboxIds, inbox.id];
};

const disconnect = async () => {
  busy.value = true;
  error.value = '';
  try {
    const { data } = await InclamoAPI.disconnectAi();
    confirmDialog.value.close();
    form.inboxIds = [];
    show(data);
    notice.value = data.ai_service_told === false ? t('SETTINGS.AI_AGENT.NOT_TOLD') : '';
  } catch (failure) {
    confirmDialog.value.close();
    error.value = errorText(failure);
  } finally {
    busy.value = false;
  }
};

const otherBot = inbox => (inbox.other_bot === 'Dialogflow' ? t('SETTINGS.AI_AGENT.HAS_DIALOGFLOW') : t('SETTINGS.AI_AGENT.HAS_OTHER_BOT'));
const failureKind = kind => {
  if (!kind) return '';
  if (has(`SETTINGS.AI_AGENT.FAILURES.${kind}`)) return t(`SETTINGS.AI_AGENT.FAILURES.${kind}`);
  const status = /^http_(\d{3})$/.exec(kind);
  return status ? t('SETTINGS.AI_AGENT.FAILURES.http', { status: status[1] }) : kind;
};

onMounted(load);
</script>

<template>
  <SettingsLayout :is-loading="loading" :loading-message="t('SETTINGS.AI_AGENT.LOADING')">
    <template #header>
      <BaseSettingsHeader :title="t('SETTINGS.AI_AGENT.TITLE')" :description="t('SETTINGS.AI_AGENT.INTRO')" />
    </template>
    <template #body>
      <p v-if="failed" class="text-sm text-n-ruby-11" data-testid="inclamo-ai-failed">{{ t('SETTINGS.AI_AGENT.FAILED') }}</p>
      <div v-else-if="page" class="flex flex-col gap-5 text-sm text-n-slate-12" data-testid="inclamo-ai-page" :data-state="state">
        <p v-if="notice" class="p-2 rounded-md bg-n-amber-3 text-n-amber-11" data-testid="inclamo-ai-notice">{{ notice }}</p>
        <p v-if="error" class="p-2 rounded-md bg-n-ruby-3 text-n-ruby-11" data-testid="inclamo-ai-error">{{ error }}</p>

        <template v-if="connected">
          <div class="flex items-center gap-2" data-testid="inclamo-ai-state" :data-state="connection.state">
            <span class="h-2 w-2 rounded-full" :class="connection.state === 'failing' ? 'bg-n-ruby-9' : 'bg-n-teal-9'" />
            <span class="font-medium">{{ t(`SETTINGS.AI_AGENT.STATE.${connection.state}`) }}</span>
          </div>
          <p v-if="connection.state === 'failing'" class="p-2 rounded-md bg-n-ruby-3 text-n-ruby-11" data-testid="inclamo-ai-failing">{{ t('SETTINGS.AI_AGENT.FAILING') }}</p>
          <dl class="grid grid-cols-[max-content_1fr] gap-x-6 gap-y-2">
            <dt class="text-n-slate-11">{{ t('SETTINGS.AI_AGENT.INBOXES') }}</dt>
            <dd data-testid="inclamo-ai-inboxes">
              <span v-for="inbox in connectedInboxes" :key="inbox.id" class="mr-3" :data-testid="`inclamo-ai-connected-${inbox.id}`">{{ inbox.name }}</span>
            </dd>
            <dt class="text-n-slate-11">{{ t('SETTINGS.AI_AGENT.LAST_REPLY') }}</dt>
            <dd data-testid="inclamo-ai-last-reply">{{ connection.last_reply_at ? dateTime(connection.last_reply_at) : t('SETTINGS.AI_AGENT.NO_REPLY_YET') }}</dd>
            <dt class="text-n-slate-11">{{ t('SETTINGS.AI_AGENT.LAST_ERROR') }}</dt>
            <dd data-testid="inclamo-ai-last-error" :data-kind="connection.last_error || ''">
              <template v-if="connection.last_failed_at">{{ t('SETTINGS.AI_AGENT.FAILED_AT', { kind: failureKind(connection.last_error), time: dateTime(connection.last_failed_at) }) }}</template>
              <template v-else>{{ t('SETTINGS.AI_AGENT.NO_ERROR') }}</template>
            </dd>
            <dt class="text-n-slate-11">{{ t('SETTINGS.AI_AGENT.CONNECTED_AT') }}</dt>
            <dd>{{ dateTime(connection.connected_at) }}</dd>
          </dl>
          <p class="text-n-slate-11">{{ t('SETTINGS.AI_AGENT.WHERE') }}</p>
          <div>
            <button type="button" class="rounded-lg border border-n-ruby-7 px-3 py-1.5 font-medium text-n-ruby-11 disabled:opacity-50" :disabled="busy" data-testid="inclamo-ai-disconnect" @click="confirmDialog.open()">
              {{ t('SETTINGS.AI_AGENT.DISCONNECT') }}
            </button>
          </div>
        </template>

        <template v-else>
          <div class="flex flex-col gap-2" data-testid="inclamo-ai-about">
            <p>{{ t('SETTINGS.AI_AGENT.ABOUT.ANSWERS') }}</p>
            <p>{{ t('SETTINGS.AI_AGENT.ABOUT.HANDOVER') }}</p>
            <p>{{ t('SETTINGS.AI_AGENT.ABOUT.SUBSCRIPTION') }}</p>
            <a :href="page.get_agent_url" target="_blank" rel="noopener noreferrer" class="text-n-blue-text" data-testid="inclamo-ai-get">{{ t('SETTINGS.AI_AGENT.GET') }}</a>
          </div>
          <p v-if="page.last_disconnection" class="text-n-slate-11" data-testid="inclamo-ai-disconnected">
            {{ t('SETTINGS.AI_AGENT.DISCONNECTED_AT', { time: dateTime(page.last_disconnection.disconnected_at) }) }}
            <template v-if="!page.last_disconnection.ai_service_told">{{ t('SETTINGS.AI_AGENT.NOT_TOLD') }}</template>
          </p>
          <p v-if="!page.encryption_configured" class="p-2 rounded-md bg-n-ruby-3 text-n-ruby-11" data-testid="inclamo-ai-encryption">{{ t('SETTINGS.AI_AGENT.ERRORS.encryption_not_configured') }}</p>
          <label class="flex flex-col gap-1">
            <span class="font-medium">{{ t('SETTINGS.AI_AGENT.CODE') }}</span>
            <input v-model="form.code" type="password" autocomplete="off" spellcheck="false" :placeholder="t('SETTINGS.AI_AGENT.CODE_PLACEHOLDER')" class="rounded-md border border-n-weak bg-n-alpha-black2 px-2 py-1.5" data-testid="inclamo-ai-code" />
          </label>
          <fieldset class="flex flex-col gap-2">
            <legend class="mb-1 font-medium">{{ t('SETTINGS.AI_AGENT.PICK') }}</legend>
            <p v-if="inboxes.length === 0" class="text-n-slate-11">{{ t('SETTINGS.AI_AGENT.NO_INBOXES') }}</p>
            <label
              v-for="inbox in inboxes"
              :key="inbox.id"
              class="flex items-center gap-2"
              :class="{ 'text-n-slate-10': !inbox.selectable }"
              :data-testid="`inclamo-ai-inbox-${inbox.id}`"
              :data-selectable="inbox.selectable ? 'true' : 'false'"
            >
              <input type="checkbox" :checked="form.inboxIds.includes(inbox.id)" :disabled="!inbox.selectable || busy" @change="toggle(inbox)" />
              <span>{{ inbox.name }}</span>
              <span v-if="!inbox.selectable" class="text-xs" data-testid="inclamo-ai-other-bot">{{ otherBot(inbox) }}</span>
            </label>
          </fieldset>
          <div>
            <button type="button" class="rounded-lg bg-n-brand px-3 py-1.5 font-medium text-white disabled:opacity-50" :disabled="!canConnect" data-testid="inclamo-ai-connect" @click="connect">
              {{ busy ? t('SETTINGS.AI_AGENT.CONNECTING') : t('SETTINGS.AI_AGENT.CONNECT') }}
            </button>
          </div>
        </template>
      </div>
      <Dialog
        ref="confirmDialog"
        type="alert"
        :title="t('SETTINGS.AI_AGENT.CONFIRM.TITLE')"
        :confirm-button-label="t('SETTINGS.AI_AGENT.CONFIRM.YES')"
        :cancel-button-label="t('SETTINGS.AI_AGENT.CONFIRM.NO')"
        :is-loading="busy"
        @confirm="disconnect"
      >
        <p class="text-sm text-n-slate-12" data-testid="inclamo-ai-confirm">{{ t('SETTINGS.AI_AGENT.CONFIRM.BODY') }}</p>
      </Dialog>
    </template>
  </SettingsLayout>
</template>
