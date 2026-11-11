<script setup>
import { ref, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { Input } from '../ui/input';
import { Tabs, TabsList, TabsTrigger } from '../ui/tabs';
import { t as inclamoT } from '../i18n';
const props = defineProps({
  status: { type: String, default: 'open' },
  showStatus: Boolean,
});
const emit = defineEmits(['statusChange']);
const query = ref('');
const router = useRouter();
const route = useRoute();
const store = useStore();
const { t: nativeT } = useI18n();
const { uiSettings, updateUISettings } = useUISettings();
const statuses = computed(() =>
  ['open', 'snoozed', 'resolved'].map(value => ({
    value,
    label: nativeT(`CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${value}.TEXT`),
  }))
);
function selectStatus(value) {
  if (value === props.status) return;
  store.dispatch('setChatStatusFilter', value);
  updateUISettings({
    conversations_filter_by: {
      ...uiSettings.value.conversations_filter_by,
      status: value,
    },
  });
  emit('statusChange', value, 'status');
}
function search() {
  if (!query.value.trim()) return;
  router.push({
    name: 'search',
    params: { accountId: route.params.accountId, tab: 'conversations' },
    query: { q: query.value.trim() },
  });
}
</script>
<template>
  <div class="inclamo-inbox-tools">
    <form class="inclamo-inbox-search" role="search" @submit.prevent="search">
      <span class="i-lucide-search" aria-hidden="true" />
      <Input
        v-model="query"
        type="search"
        :aria-label="inclamoT('WORKSPACE.SEARCH_SUBMIT')"
        :placeholder="inclamoT('WORKSPACE.SEARCH')"
      />
      <button type="submit" :aria-label="inclamoT('WORKSPACE.SEARCH_SUBMIT')">
        <span class="i-lucide-corner-down-left" aria-hidden="true" />
      </button>
    </form>
    <Tabs
      v-if="showStatus"
      :model-value="status"
      class="inclamo-status-tabs"
      @update:model-value="selectStatus"
    >
      <TabsList :aria-label="inclamoT('WORKSPACE.STATUS')">
        <TabsTrigger
          v-for="item in statuses"
          :key="item.value"
          :value="item.value"
          >{{ item.label }}</TabsTrigger
        >
      </TabsList>
    </Tabs>
  </div>
</template>
