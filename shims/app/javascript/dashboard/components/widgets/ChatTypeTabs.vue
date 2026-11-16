<!--
  Stands in for Chatwoot's ChatTypeTabs.vue (kept beside this file as ChatTypeTabs.chatwoot.vue).
  It is Chatwoot's component as the workspace draws it: part of the conversation list.
  When Chatwoot changes its file the build stops (custom/CHATWOOT_FILES);
  carry their change over into this one.
-->
<script setup>
import { computed } from 'vue';
import QueueMenu from 'dashboard/inclamo/components/QueueMenu.vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import wootConstants from 'dashboard/constants/globals';

const props = defineProps({
  items: {
    type: Array,
    default: () => [],
  },
  activeTab: {
    type: String,
    default: wootConstants.ASSIGNEE_TYPE.ME,
  },
});

const emit = defineEmits(['chatTabChange']);

const activeTabIndex = computed(() => {
  return props.items.findIndex(item => item.key === props.activeTab);
});

const onTabChange = selectedTabIndex => {
  if (selectedTabIndex >= 0 && selectedTabIndex < props.items.length) {
    const selectedItem = props.items[selectedTabIndex];
    if (selectedItem.key !== props.activeTab) {
      emit('chatTabChange', selectedItem.key);
    }
  }
};

const keyboardEvents = {
  'Alt+KeyN': {
    action: () => {
      if (props.activeTab === wootConstants.ASSIGNEE_TYPE.ALL) {
        onTabChange(0);
      } else {
        const nextIndex = (activeTabIndex.value + 1) % props.items.length;
        onTabChange(nextIndex);
      }
    },
  },
};

useKeyboardEvents(keyboardEvents);
</script>

<template>
  <QueueMenu :items="items" :active-tab="activeTab" @change="onTabChange" />
</template>
