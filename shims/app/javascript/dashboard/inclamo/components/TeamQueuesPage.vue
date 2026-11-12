<script setup>
// Settings → Team queues: the account's shared conversation queues. An
// administrator renames, reorders, hides and restores them; nothing here
// changes which conversations a queue lists, except restoring a ready one.
import { ref, onMounted } from 'vue';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import InclamoAPI from '../api';
import { loadTeamQueues } from '../teamQueues';
import { t } from '../i18n';

const queues = ref([]);
// What is typed in the name fields, by queue.
const names = ref({});
const loading = ref(true);
const failed = ref(false);
const busy = ref(false);
const error = ref('');

const show = data => {
  queues.value = data.queues;
  names.value = Object.fromEntries(data.queues.map(queue => [queue.id, queue.name]));
};

const load = async () => {
  try {
    show((await InclamoAPI.getTeamQueues(true)).data);
  } catch (e) {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

// Every change is answered from the server's list, and the navigation follows.
const change = async request => {
  busy.value = true;
  error.value = '';
  try {
    await request();
  } catch (e) {
    error.value = e.response?.data?.message || t('SETTINGS.TEAM_QUEUES.SAVE_FAILED');
  }
  try {
    show((await InclamoAPI.getTeamQueues(true)).data);
  } catch (e) {
    failed.value = true;
  } finally {
    busy.value = false;
  }
  loadTeamQueues();
};

const rename = queue => {
  const name = (names.value[queue.id] || '').trim();
  if (name === queue.name) return;
  change(() => InclamoAPI.updateTeamQueue(queue.id, { name }));
};

const setShown = (queue, event) => change(() => InclamoAPI.updateTeamQueue(queue.id, { hidden: !event.target.checked }));

const move = (index, by) => {
  const ids = queues.value.map(queue => queue.id);
  const [id] = ids.splice(index, 1);
  ids.splice(index + by, 0, id);
  change(() => InclamoAPI.reorderTeamQueues(ids));
};

const restore = queue => change(() => InclamoAPI.restoreTeamQueue(queue.id));

onMounted(load);
</script>

<template>
  <SettingsLayout :is-loading="loading" :loading-message="t('SETTINGS.TEAM_QUEUES.LOADING')">
    <template #header>
      <BaseSettingsHeader :title="t('SETTINGS.TEAM_QUEUES.TITLE')" :description="t('SETTINGS.TEAM_QUEUES.INTRO')" />
    </template>
    <template #body>
      <p v-if="failed" class="text-sm text-n-ruby-11" data-testid="inclamo-team-queues-failed">{{ t('SETTINGS.TEAM_QUEUES.FAILED') }}</p>
      <div v-else class="flex flex-col gap-3 text-sm text-n-slate-12" data-testid="inclamo-team-queues-page">
        <p v-if="error" class="text-n-ruby-11" role="alert" data-testid="inclamo-team-queues-error">{{ error }}</p>
        <div class="flex flex-col divide-y divide-n-weak">
          <div
            v-for="(queue, index) in queues"
            :key="queue.id"
            class="flex items-center gap-3 py-2"
            :data-testid="`inclamo-team-queue-row-${queue.key || queue.id}`"
          >
            <span class="flex gap-1">
              <button
                type="button"
                class="i-lucide-arrow-up size-4 disabled:opacity-30"
                :disabled="busy || index === 0"
                :aria-label="t('SETTINGS.TEAM_QUEUES.MOVE_UP', { name: queue.name })"
                :data-testid="`inclamo-team-queue-up-${queue.key || queue.id}`"
                @click="move(index, -1)"
              />
              <button
                type="button"
                class="i-lucide-arrow-down size-4 disabled:opacity-30"
                :disabled="busy || index === queues.length - 1"
                :aria-label="t('SETTINGS.TEAM_QUEUES.MOVE_DOWN', { name: queue.name })"
                :data-testid="`inclamo-team-queue-down-${queue.key || queue.id}`"
                @click="move(index, 1)"
              />
            </span>
            <input
              v-model="names[queue.id]"
              type="text"
              maxlength="60"
              class="!mb-0 flex-1"
              :disabled="busy"
              :aria-label="t('SETTINGS.TEAM_QUEUES.NAME', { name: queue.name })"
              :data-testid="`inclamo-team-queue-name-${queue.key || queue.id}`"
              @change="rename(queue)"
            />
            <span v-if="queue.hidden" class="text-xs text-n-slate-11" :data-testid="`inclamo-team-queue-hidden-${queue.key || queue.id}`">
              {{ t('SETTINGS.TEAM_QUEUES.HIDDEN') }}
            </span>
            <label class="flex items-center gap-2 text-xs">
              <span>{{ t('SETTINGS.TEAM_QUEUES.SHOWN_COLUMN') }}</span>
              <input
                type="checkbox"
                :checked="!queue.hidden"
                :disabled="busy"
                :aria-label="t('SETTINGS.TEAM_QUEUES.SHOWN', { name: queue.name })"
                :data-testid="`inclamo-team-queue-shown-${queue.key || queue.id}`"
                @change="setShown(queue, $event)"
              />
            </label>
            <button
              v-if="queue.ready"
              type="button"
              class="text-xs text-n-blue-text disabled:opacity-30"
              :disabled="busy"
              :aria-label="t('SETTINGS.TEAM_QUEUES.RESTORE_LABEL', { name: queue.name })"
              :data-testid="`inclamo-team-queue-restore-${queue.key || queue.id}`"
              @click="restore(queue)"
            >
              {{ t('SETTINGS.TEAM_QUEUES.RESTORE') }}
            </button>
          </div>
        </div>
        <p class="text-xs text-n-slate-11">{{ t('SETTINGS.TEAM_QUEUES.LABEL_NOTE') }}</p>
      </div>
    </template>
  </SettingsLayout>
</template>
