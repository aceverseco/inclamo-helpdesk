<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import ConnectDialog from './ConnectDialog.vue';
import StaffPermissionsEditor from './StaffPermissionsEditor.vue';
import AiPolicyEditor from './AiPolicyEditor.vue';
import InclamoAPI from '../api';
import { t } from '../i18n';
import { dateTime } from '../format';
const route = useRoute();
const router = useRouter();
const page = ref(null);
const loading = ref(true);
const busy = ref(false);
const error = ref('');
const editorReady = ref(false);
const connectDialog = ref(null);
const steps = ['store', 'channels', 'staff', 'ai', 'verify'];
const step = computed(() => steps.includes(route.query.step) ? route.query.step : 'store');
const accountPath = computed(() => `/app/accounts/${route.params.accountId}`);
const choose = next => { editorReady.value = false; router.replace({ query: { ...route.query, step: next } }); };
const load = async () => {
  error.value = '';
  try { page.value = (await InclamoAPI.getSetup()).data; }
  catch { error.value = t('SETUP.LOAD_FAILED'); }
  finally { loading.value = false; }
};
const saved = async () => { editorReady.value = true; await load(); };
const run = async action => {
  busy.value = true;
  error.value = '';
  try { await action(); await load(); }
  catch (failure) { error.value = failure.response?.data?.error === 'review_changed' ? t('SETUP.REVIEW_CHANGED') : t('SETUP.SAVE_FAILED'); }
  finally { busy.value = false; }
};
const review = () => run(() => InclamoAPI.reviewSetup(step.value, page.value.review_digests[step.value]));
const recheck = () => run(() => InclamoAPI.recheck());
const complete = () => run(() => InclamoAPI.completeSetup());
onMounted(load);
</script>

<template>
  <SettingsLayout :is-loading="loading" :loading-message="t('SETUP.LOADING')">
    <template #header><BaseSettingsHeader :title="t('SETUP.TITLE')" :description="t('SETUP.INTRO')" /></template>
    <template #body>
      <div class="flex flex-col gap-5 text-sm text-n-slate-12" data-testid="inclamo-setup">
        <p v-if="error" role="alert" class="text-n-ruby-11" data-testid="inclamo-setup-error">{{ error }}</p>
        <button v-if="!page && !loading" type="button" class="text-n-blue-text" @click="load">{{ t('SETUP.RETRY') }}</button>
        <template v-if="page">
          <nav class="flex flex-wrap gap-2" :aria-label="t('SETUP.STEPS_LABEL')">
            <button v-for="(entry, index) in steps" :key="entry" type="button" class="rounded-md px-3 py-2 border border-n-weak" :class="step === entry ? 'bg-n-alpha-black2 font-semibold' : ''" :aria-current="step === entry ? 'step' : undefined" :data-testid="`setup-step-${entry}`" @click="choose(entry)">
              {{ index + 1 }}. {{ t(`SETUP.STEPS.${entry}`) }} <span v-if="page.checks[entry] || (entry === 'verify' && page.complete)">✓</span>
            </button>
          </nav>
          <p v-if="page.complete" role="status" class="p-3 rounded-md bg-n-teal-3 text-n-teal-11" data-testid="setup-complete">{{ t('SETUP.COMPLETE') }}</p>
          <section v-if="step === 'store'" class="flex flex-col gap-3">
            <h3 class="font-semibold">{{ t('SETUP.STEPS.store') }}</h3>
            <p>{{ t('SETUP.STORE_HELP') }}</p>
            <p v-if="page.store">{{ page.store.domain }} · {{ t(page.checks.store ? 'SETUP.WORKING' : 'SETUP.BROKEN') }}</p>
            <div class="flex flex-wrap gap-3">
              <button type="button" class="rounded-md bg-n-brand px-3 py-2 text-white" data-testid="setup-connect" @click="connectDialog.open(page.store?.domain)">{{ t(page.store ? 'SETUP.RECONNECT' : 'SETUP.CONNECT') }}</button>
              <button v-if="page.store" type="button" class="rounded-md border border-n-weak px-3 py-2" :disabled="busy" data-testid="setup-recheck" @click="recheck">{{ t('SETUP.RECHECK') }}</button>
              <button type="button" class="text-n-blue-text" @click="choose('channels')">{{ t('SETUP.NEXT') }}</button>
            </div>
          </section>
          <section v-else-if="step === 'channels'" class="flex flex-col gap-3">
            <h3 class="font-semibold">{{ t('SETUP.STEPS.channels') }}</h3>
            <p>{{ t('SETUP.CHANNELS_HELP') }}</p>
            <p v-if="!page.channels.length" class="text-n-amber-11">{{ t('SETUP.NO_CHANNEL') }}</p>
            <ul v-else class="list-disc pl-5"><li v-for="channel in page.channels" :key="channel.id">{{ channel.name }}</li></ul>
            <p>{{ t('SETUP.TEAM_COUNT', { count: page.members_count }) }}</p>
            <div class="flex flex-wrap gap-4">
              <router-link :to="`${accountPath}/settings/inboxes/list`" class="text-n-blue-text">{{ t('SETUP.CHANNEL_SETTINGS') }}</router-link>
              <router-link :to="`${accountPath}/settings/agents/list`" class="text-n-blue-text">{{ t('SETUP.TEAM_SETTINGS') }}</router-link>
              <button type="button" class="text-n-blue-text" @click="load">{{ t('SETUP.RELOAD') }}</button>
              <button type="button" class="text-n-blue-text" @click="choose('staff')">{{ t('SETUP.NEXT') }}</button>
            </div>
          </section>
          <section v-else-if="step === 'staff'" class="flex flex-col gap-4">
            <StaffPermissionsEditor @loaded="saved" @changed="saved" />
            <button type="button" class="self-start rounded-md bg-n-brand px-3 py-2 text-white disabled:opacity-50" :disabled="busy || !editorReady" data-testid="setup-review-staff" @click="review">{{ t('SETUP.REVIEW_STAFF') }}</button>
            <p v-if="page.checks.staff" role="status">{{ t('SETUP.REVIEWED') }}</p>
            <button type="button" class="text-left text-n-blue-text" @click="choose('ai')">{{ t('SETUP.NEXT') }}</button>
          </section>
          <section v-else-if="step === 'ai'" class="flex flex-col gap-4">
            <p class="p-3 rounded-md bg-n-alpha-black2">{{ t(page.ai_connected ? 'SETUP.AI_CONNECTED' : 'SETUP.AI_OPTIONAL') }}</p>
            <router-link :to="`${accountPath}/settings/ai-agent`" class="text-n-blue-text">{{ t('SETUP.AI_SETTINGS') }}</router-link>
            <AiPolicyEditor @loaded="saved" @changed="saved" @dirty="editorReady = false" />
            <button type="button" class="self-start rounded-md bg-n-brand px-3 py-2 text-white disabled:opacity-50" :disabled="busy || !editorReady" data-testid="setup-review-ai" @click="review">{{ t('SETUP.REVIEW_AI') }}</button>
            <p v-if="page.checks.ai" role="status">{{ t('SETUP.REVIEWED') }}</p>
            <button type="button" class="text-left text-n-blue-text" @click="choose('verify')">{{ t('SETUP.NEXT') }}</button>
          </section>
          <section v-else class="flex flex-col gap-4" data-testid="setup-verification">
            <h3 class="font-semibold">{{ t('SETUP.STEPS.verify') }}</h3>
            <ul class="flex flex-col gap-2"><li v-for="entry in steps.slice(0, 4)" :key="entry">{{ t(`SETUP.STEPS.${entry}`) }}: {{ t(page.checks[entry] ? 'SETUP.CHECK_OK' : 'SETUP.CHECK_MISSING') }}</li></ul>
            <p>{{ t(page.ai_connected ? 'SETUP.AI_CONNECTED' : 'SETUP.AI_OPTIONAL') }}</p>
            <button type="button" class="self-start rounded-md bg-n-brand px-3 py-2 text-white disabled:opacity-50" :disabled="busy || !page.ready" data-testid="setup-finish" @click="complete">{{ t('SETUP.FINISH') }}</button>
            <h4 class="font-semibold">{{ t('SETUP.TEST_TITLE') }}</h4>
            <ol class="list-decimal pl-5 flex flex-col gap-2"><li>{{ t('SETUP.TEST_CUSTOMER') }}</li><li>{{ t('SETUP.TEST_ACTION') }}</li><li>{{ t('SETUP.TEST_VERIFY') }}</li><li>{{ t('SETUP.TEST_CHANNEL') }}</li></ol>
            <router-link :to="`${accountPath}/dashboard`" class="text-n-blue-text">{{ t('SETUP.OPEN_CONVERSATIONS') }}</router-link>
            <p class="text-n-slate-11">{{ t('SETUP.EVIDENCE_HELP') }}</p>
            <p v-if="!page.order_actions.length" data-testid="setup-no-actions">{{ t('SETUP.NO_ACTIONS') }}</p>
            <ul v-else class="flex flex-col gap-1"><li v-for="(action, index) in page.order_actions" :key="index">{{ t(`ACTION_RIGHTS.${action.action}`) }} {{ action.order_number }} · {{ dateTime(action.completed_at) }}</li></ul>
          </section>
        </template>
        <ConnectDialog ref="connectDialog" @connected="load" />
      </div>
    </template>
  </SettingsLayout>
</template>
