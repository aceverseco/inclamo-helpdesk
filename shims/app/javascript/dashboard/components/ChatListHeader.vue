<!--
  Stands in for Chatwoot's ChatListHeader.vue (kept beside this file as ChatListHeader.chatwoot.vue).
  It is Chatwoot's component as the workspace draws it: part of the conversation list.
  When Chatwoot changes its file the build stops (custom/CHATWOOT_FILES);
  carry their change over into this one.
-->
<script setup>
import { computed } from 'vue';
import { t as inclamoT } from 'dashboard/inclamo/i18n';
import { useI18n } from 'vue-i18n';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { formatNumber } from '@chatwoot/utils';
import wootConstants from 'dashboard/constants/globals';

import SwitchLayout from 'dashboard/routes/dashboard/conversation/search/SwitchLayout.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  pageTitle: { type: String, required: true },
  contactFilter: { type: Object, default: null },
  hasAppliedFilters: { type: Boolean, required: true },
  hasActiveFolders: { type: Boolean, required: true },
  folderLocked: { type: Boolean, default: false },
  isOnExpandedLayout: { type: Boolean, required: true },
  conversationStats: { type: Object, required: true },
  isListLoading: { type: Boolean, required: true },
});

const emit = defineEmits([
  'addFolders',
  'deleteFolders',
  'resetFilters',
  'filtersModal',
]);

const { uiSettings, updateUISettings } = useUISettings();
const { t } = useI18n();

const hasAppliedFiltersOrActiveFolders = computed(() => {
  return props.hasAppliedFilters || props.hasActiveFolders;
});

const allCount = computed(() => props.conversationStats?.allCount || 0);
const formattedAllCount = computed(() => formatNumber(allCount.value));

// While filters narrow the list, the header names it and the back button exits.
const showFilterScope = computed(
  () => props.hasAppliedFilters && !props.hasActiveFolders
);

// The contact scope is set from the contact panel; it is exited, not edited.
const isContactScoped = computed(
  () => showFilterScope.value && !!props.contactFilter
);

const title = computed(
  () =>
    (isContactScoped.value && props.contactFilter.name) ||
    (props.pageTitle === t('CHAT_LIST.TAB_HEADING')
      ? inclamoT('WORKSPACE.INBOX')
      : props.pageTitle)
);

const toggleConversationLayout = () => {
  const { LAYOUT_TYPES } = wootConstants;
  const {
    conversation_display_type: conversationDisplayType = LAYOUT_TYPES.CONDENSED,
  } = uiSettings.value;
  const newViewType =
    conversationDisplayType === LAYOUT_TYPES.CONDENSED
      ? LAYOUT_TYPES.EXPANDED
      : LAYOUT_TYPES.CONDENSED;
  updateUISettings({
    conversation_display_type: newViewType,
    previously_used_conversation_display_type: newViewType,
  });
};
</script>

<template>
  <div
    class="inclamo-list-heading flex items-center justify-between gap-2 px-3 h-[3.25rem]"
    :class="{
      'border-b border-n-strong': hasAppliedFiltersOrActiveFolders,
    }"
  >
    <div class="flex items-center justify-center min-w-0">
      <NextButton
        v-if="showFilterScope"
        v-tooltip.right="$t('FILTER.CLEAR_BUTTON_LABEL')"
        :aria-label="$t('FILTER.CLEAR_BUTTON_LABEL')"
        icon="i-lucide-chevron-left"
        class="shrink-0 -ms-2 !h-6 !w-6 me-1"
        slate
        sm
        ghost
        @click="emit('resetFilters')"
      />
      <h1 class="text-base font-medium truncate text-n-slate-12" :title="title">
        {{ title }}
      </h1>
      <span
        v-if="allCount > 0 && !isListLoading"
        class="px-2 py-1 my-0.5 mx-1 rounded-md capitalize bg-n-slate-3 text-xxs text-n-slate-12 shrink-0"
        :title="allCount"
      >
        {{ formattedAllCount }}
      </span>
    </div>
    <div class="flex items-center gap-1">
      <template v-if="hasAppliedFilters && !hasActiveFolders">
        <div class="relative">
          <NextButton
            v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.ADD.SAVE_BUTTON')"
            icon="i-lucide-save"
            slate
            xs
            faded
            @click="emit('addFolders')"
          />
          <div
            id="saveFilterTeleportTarget"
            class="absolute z-50 mt-2"
            :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
          />
        </div>
      </template>
      <template v-if="folderLocked" />
      <template v-else-if="hasActiveFolders">
        <div class="relative">
          <NextButton
            id="toggleConversationFilterButton"
            v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.EDIT.EDIT_BUTTON')"
            icon="i-lucide-pen-line"
            slate
            xs
            faded
            @click="emit('filtersModal')"
          />
          <div
            id="conversationFilterTeleportTarget"
            class="absolute z-50 mt-2"
            :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
          />
        </div>
        <NextButton
          id="toggleConversationFilterButton"
          v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.DELETE.DELETE_BUTTON')"
          icon="i-lucide-trash-2"
          ruby
          xs
          faded
          @click="emit('deleteFolders')"
        />
      </template>
      <div v-else-if="!isContactScoped" class="relative">
        <NextButton
          id="toggleConversationFilterButton"
          v-tooltip.right="$t('FILTER.TOOLTIP_LABEL')"
          icon="i-lucide-list-filter"
          slate
          xs
          faded
          @click="emit('filtersModal')"
        />
        <div
          id="conversationFilterTeleportTarget"
          class="absolute z-50 mt-2"
          :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
        />
      </div>
      <SwitchLayout
        :is-on-expanded-layout="isOnExpandedLayout"
        @toggle="toggleConversationLayout"
      />
    </div>
  </div>
</template>
