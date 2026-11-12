<script setup>
import { ref, computed, watch, onUnmounted, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { Button } from '../ui/button';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '../ui/tabs';
import SupportForm from './SupportForm.vue';
import { supportUI, supportURL, locationContext, submissionId } from './state';
import { t } from '../i18n';
const route = useRoute();
const router = useRouter();
const user = useMapGetter('getCurrentUser');
const accountId = computed(() => route.params.accountId);
const identity = computed(() => `${accountId.value}:${user.value?.id}`);
const dialog = ref(null);
const tab = ref('new');
const opened = ref(false);
const metadata = ref(null);
const requests = ref([]);
const thread = ref(null);
const error = ref('');
const formError = ref('');
const busy = ref(false);
const loading = ref(false);
const code = ref('');
const verification = ref('');
const fresh = () => ({ uuid: submissionId(), category: 'problem', body: '', files: [], includeConversation: false,
  conversationReference: route.params.conversation_id || route.params.conversationId, context: { browser: navigator.userAgent.slice(0, 200), timestamp: new Date().toISOString(), location: locationContext(route.path) } });
const draft = ref(fresh());
const reply = ref(fresh());
const pending = computed(() => thread.value?.submissions.filter(item => item.state !== 'delivered' || !thread.value.messages.some(message => message.submission_uuid === item.uuid)) || []);
let trigger;
let generation = 0;
let polling;
let threadRead = 0;
let selectedReference = null;
const back = () => { selectedReference = null; threadRead += 1; thread.value = null; };
const clearFiles = value => { value.files.forEach(file => { if (file.url) URL.revokeObjectURL(file.url); }); value.files.length = 0; };
const load = async () => {
  if (!opened.value || loading.value || document.hidden) return;
  loading.value = true;
  const mine = generation;
  const reference = selectedReference;
  try {
    const { data } = await axios.get(`${supportURL(accountId.value)}/requests`);
    if (mine !== generation) return;
    requests.value = data.requests;
    error.value = '';
    if (reference && selectedReference === reference) await show(reference, false);
  } catch (failure) {
    if (mine !== generation) return;
    error.value = [401, 403, 404].includes(failure.response?.status) ? 'SUPPORT.ACCESS_CHANGED' : 'SUPPORT.LOAD_FAILED';
    if (error.value === 'SUPPORT.ACCESS_CHANGED') thread.value = null;
  } finally { if (mine === generation) loading.value = false; }
};
const show = async (reference, clearReply = true) => {
  if (clearReply) selectedReference = reference;
  const mine = generation;
  const read = ++threadRead;
  try {
    const { data } = await axios.get(`${supportURL(accountId.value)}/requests/${reference}`);
    if (mine !== generation || read !== threadRead || selectedReference !== reference) return;
    if (clearReply) { clearFiles(reply.value); reply.value = fresh(); verification.value = ''; code.value = ''; }
    thread.value = data;
    tab.value = 'requests';
    await axios.post(`${supportURL(accountId.value)}/requests/${reference}/read`, { cursor: data.last_reply_id });
    const item = requests.value.find(item => item.reference === reference);
    if (item) item.unread = false;
  } catch (failure) {
    if (mine !== generation || read !== threadRead || selectedReference !== reference) return;
    error.value = [401, 403, 404].includes(failure.response?.status) ? 'SUPPORT.ACCESS_CHANGED' : 'SUPPORT.LOAD_FAILED';
    if (error.value === 'SUPPORT.ACCESS_CHANGED') thread.value = null;
  }
};
const open = async () => {
  trigger = document.activeElement;
  opened.value = true;
  if (!draft.value.body && !draft.value.files.length) draft.value = fresh();
  error.value = '';
  const mine = ++generation;
  await nextTick();
  dialog.value.open();
  clearInterval(polling);
  polling = setInterval(load, 10000);
  try {
    const { data } = await axios.get(`${supportURL(accountId.value)}/metadata`);
    if (mine !== generation) return;
    metadata.value = data;
    await load();
    if (supportUI.reference) await show(supportUI.reference);
  } catch { if (mine === generation) error.value = 'SUPPORT.LOAD_FAILED'; }
};
const close = () => {
  opened.value = false;
  generation += 1;
  loading.value = false;
  clearInterval(polling);
  if (route.query.support_request) {
    const query = { ...route.query }; delete query.support_request;
    router.replace({ query });
  }
  nextTick(() => trigger?.focus());
};
watch(() => supportUI.sequence, open, { immediate: true, flush: 'post' });
watch(identity, () => {
  dialog.value?.close(); generation += 1;
  clearFiles(draft.value); clearFiles(reply.value);
  draft.value = fresh(); reply.value = fresh();
  metadata.value = null; requests.value = []; back();
});
const submit = async isReply => {
  const value = isReply ? reply.value : draft.value;
  if (!value.body.trim()) return;
  busy.value = true; formError.value = '';
  const mine = generation;
  const base = supportURL(accountId.value);
  try {
    for (const file of value.files) {
      if (file.reference) continue;
      const form = new FormData(); form.append('file', file.blob, file.name);
      const { data } = await axios.post(`${base}/uploads`, form);
      file.reference = data.reference;
    }
    if (mine !== generation) return;
    const context = { browser: value.context.browser, location: value.context.location };
    if (value.includeConversation && value.conversationReference) context.conversation_reference = value.conversationReference;
    const endpoint = isReply ? `${base}/requests/${thread.value.reference}/replies` : `${base}/requests`;
    const { data } = await axios.post(endpoint, { uuid: value.uuid, body: value.body, category: value.category,
      context, files: value.files.map(file => file.reference) });
    if (mine !== generation) return;
    clearFiles(value);
    if (isReply) reply.value = fresh(); else draft.value = fresh();
    thread.value = data; selectedReference = data.reference; tab.value = 'requests';
    await load();
  } catch (failure) {
    if (mine === generation) {
      if (failure.response?.status === 422 && failure.response?.data?.error === 'invalid_files') value.files.forEach(file => { file.reference = null; });
      formError.value = failure.response?.status === 409 ? 'SUPPORT.SUBMISSION_CONFLICT' : 'SUPPORT.SEND_FAILED';
    }
  } finally { busy.value = false; }
};
const retry = async uuid => {
  try {
    await axios.post(`${supportURL(accountId.value)}/requests/${thread.value.reference}/retry/${uuid}`);
    await show(thread.value.reference, false);
  } catch { error.value = 'SUPPORT.SEND_FAILED'; }
};
const download = async file => {
  try {
    const { data } = await axios.get(file.url, { responseType: 'blob' });
    const url = URL.createObjectURL(data);
    const link = document.createElement('a'); link.href = url; link.download = file.filename || file.name || 'attachment'; link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  } catch { error.value = 'SUPPORT.DOWNLOAD_FAILED'; }
};
const verify = async (sendCode, enabled = true) => {
  try {
    const suffix = sendCode ? 'recipient' : 'recipient/verify';
    const { data } = await axios.post(`${supportURL(accountId.value)}/requests/${thread.value.reference}/${suffix}`, sendCode ? { enabled } : { code: code.value });
    if (sendCode) thread.value.notifications_enabled = enabled;
    verification.value = !enabled ? 'SUPPORT.EMAIL_DISABLED' : data.verified || data.recipients?.[0]?.verified ? 'SUPPORT.EMAIL_VERIFIED' : 'SUPPORT.CODE_SENT';
  } catch { verification.value = 'SUPPORT.VERIFY_FAILED'; }
};
onUnmounted(() => { clearInterval(polling); generation += 1; clearFiles(draft.value); clearFiles(reply.value); });
</script>
<template>
  <Dialog ref="dialog" :title="t('SUPPORT.TITLE')" :show-confirm-button="false" :cancel-button-label="t('SUPPORT.CLOSE')" width="2xl" overflow-y-auto @close="close">
    <div class="inclamo-support space-y-4 text-n-slate-12" data-testid="inclamo-support">
      <p v-if="error" role="alert">{{ t(error) }} <Button type="button" variant="outline" size="sm" @click="open">{{ t('SUPPORT.RETRY') }}</Button></p>
      <Tabs v-model="tab"><TabsList><TabsTrigger value="new">{{ t('SUPPORT.NEW') }}</TabsTrigger><TabsTrigger value="requests">{{ t('SUPPORT.REQUESTS') }}</TabsTrigger></TabsList>
        <TabsContent value="new"><SupportForm :draft="draft" :metadata="metadata" :busy="busy" :error="formError" @submit="submit(false)" /></TabsContent>
        <TabsContent value="requests">
          <div v-if="!thread" class="space-y-2">
            <p v-if="!requests.length && !loading">{{ t('SUPPORT.EMPTY') }}</p>
            <button v-for="item in requests" :key="item.reference" type="button" class="w-full text-start p-3 border border-n-weak rounded-lg" @click="show(item.reference)">
              <span class="flex gap-2"><strong>{{ item.author.name }}</strong><span v-if="item.unread">{{ t('SUPPORT.UNREAD') }}</span><span>{{ t(`SUPPORT.STATUS.${item.status}`) }}</span></span>
              <span class="block truncate">{{ item.preview }}</span><small>{{ t(`SUPPORT.DELIVERY.${item.delivery || 'queued'}`) }}</small>
            </button>
          </div>
          <div v-else class="space-y-4">
            <div class="flex flex-wrap gap-2 items-center"><Button type="button" variant="ghost" size="sm" @click="back">{{ t('SUPPORT.BACK') }}</Button><strong>{{ t(`SUPPORT.STATUS.${thread.status}`) }}</strong><small role="status">{{ t(`SUPPORT.DELIVERY.${thread.delivery || 'queued'}`) }}</small></div>
            <p class="text-xs break-all">{{ thread.reference }}</p>
            <ol class="space-y-3"><li v-for="message in thread.messages" :key="message.id" class="border border-n-weak rounded-lg p-3">
              <strong>{{ message.actor.name || t('SUPPORT.TEAM') }}</strong><span v-if="message.actor.administrator" class="text-xs"> · {{ t('SUPPORT.ADMINISTRATOR') }}</span>
              <p class="whitespace-pre-wrap break-words text-sm mt-2">{{ message.body }}</p>
              <Button v-for="file in message.files" :key="file.id" type="button" variant="outline" size="sm" @click="download(file)">{{ file.filename }}</Button>
            </li><li v-for="submission in pending" :key="submission.uuid" class="border border-n-weak rounded-lg p-3">
              <strong>{{ submission.actor.name }}</strong><span v-if="submission.actor.administrator" class="text-xs"> · {{ t('SUPPORT.ADMINISTRATOR') }}</span>
              <p class="whitespace-pre-wrap break-words text-sm mt-2">{{ submission.body }}</p>
              <p v-if="submission.state !== thread.delivery" role="status" class="text-xs">{{ t(`SUPPORT.DELIVERY.${submission.state}`) }}</p>
              <p v-if="submission.error" class="text-xs">{{ t(submission.error === 'support_unavailable' ? 'SUPPORT.CONNECTION_PROBLEM' : submission.error === 'attachments_incomplete' ? 'SUPPORT.ATTACHMENTS_INCOMPLETE' : 'SUPPORT.ACCESS_CHANGED') }}</p>
              <Button v-for="file in submission.files" :key="file.reference" type="button" variant="outline" size="sm" @click="download(file)">{{ file.filename }}</Button>
              <Button v-if="submission.state !== 'delivered'" type="button" variant="outline" size="sm" @click="retry(submission.uuid)">{{ t('SUPPORT.RETRY') }}</Button>
            </li></ol>
            <SupportForm :draft="reply" :metadata="metadata" :busy="busy" :error="formError" reply @submit="submit(true)" />
            <details v-if="thread.can_verify_email" class="text-sm"><summary>{{ t('SUPPORT.EMAIL_NOTIFICATIONS') }}</summary>
              <p>{{ t('SUPPORT.EMAIL_HINT') }}</p>
              <Button type="button" variant="outline" size="sm" @click="verify(true)">{{ t('SUPPORT.SEND_CODE') }}</Button>
              <Button v-if="thread.notifications_enabled" type="button" variant="ghost" size="sm" @click="verify(true, false)">{{ t('SUPPORT.DISABLE_EMAIL') }}</Button>
              <label class="block mt-2">{{ t('SUPPORT.CODE') }}<input v-model="code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" class="border border-n-weak rounded p-2" /></label>
              <Button type="button" variant="outline" size="sm" :disabled="code.length !== 6" @click="verify(false)">{{ t('SUPPORT.VERIFY') }}</Button>
              <p v-if="verification" role="status">{{ t(verification) }}</p>
            </details>
          </div>
        </TabsContent>
      </Tabs>
    </div>
  </Dialog>
</template>
<style>
html[data-inclamo-capture] dialog:has(.inclamo-support) { visibility:hidden !important; opacity:0 !important; transition:none !important; animation:none !important; }
html[data-inclamo-capture] dialog:has(.inclamo-support)::backdrop { background:transparent; backdrop-filter:none; opacity:0 !important; transition:none !important; }
.inclamo-support { max-height:75dvh; overflow-y:auto; min-width:0; }
.inclamo-support textarea, .inclamo-support select { width:100%; }
.inclamo-support dl { display:grid; grid-template-columns:auto minmax(0,1fr); gap:4px 12px; }
.inclamo-support dd { margin:0; }
@media (max-width:640px) { .inclamo-support { max-height:68dvh; } }
</style>
