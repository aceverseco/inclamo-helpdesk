<script setup>
import { ref } from 'vue';
import { ChevronsUpDown } from 'lucide-vue-next';
import { useMapGetter } from 'dashboard/composables/store';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'next/icon/Icon.vue';
import CustomBrandPolicyWrapper from 'dashboard/components/CustomBrandPolicyWrapper.vue';
import { openSupport } from '../support/state';
import { t } from '../i18n';
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
} from '../ui/dropdown-menu';

defineProps({
  user: { type: Object, required: true },
  status: { type: String, required: true },
  statusLabel: { type: String, required: true },
  items: { type: Array, required: true },
  collapsed: Boolean,
});
const emit = defineEmits(['close']);
const open = ref(false);
const isRTL = useMapGetter('accounts/isRTL');
let selectedAction;

function releaseFocus(event) {
  // Native shortcuts/appearance own their focus after this menu closes.
  if (!selectedAction) return;
  event.preventDefault();
  const action = selectedAction;
  selectedAction = undefined;
  requestAnimationFrame(() => action());
}
</script>

<template>
  <DropdownMenu
    v-model:open="open"
    :dir="isRTL ? 'rtl' : 'ltr'"
    @update:open="value => !value && emit('close')"
  >
    <DropdownMenuTrigger as-child>
      <button
        type="button"
        class="inclamo-profile-trigger"
        :class="{ collapsed }"
        :title="collapsed ? user.available_name : undefined"
        :aria-label="user.available_name"
        data-testid="inclamo-profile-trigger"
      >
        <Avatar
          :size="32"
          :name="user.available_name"
          :src="user.avatar_url"
          :status="status"
          class="shrink-0"
        />
        <span v-if="!collapsed" class="inclamo-profile-identity">
          <strong>{{ user.available_name }}</strong>
          <small>{{ statusLabel }}</small>
        </span>
        <ChevronsUpDown v-if="!collapsed" class="size-3.5 shrink-0" />
      </button>
    </DropdownMenuTrigger>
    <DropdownMenuContent
      side="top"
      align="start"
      :side-offset="8"
      :collision-padding="8"
      class="inclamo-profile-menu"
      data-popover-content
      @close-auto-focus="releaseFocus"
    >
      <slot name="availability" />
      <DropdownMenuSeparator />
      <DropdownMenuItem @select="selectedAction = () => openSupport()">
        <Icon icon="i-lucide-life-buoy" class="size-4 shrink-0" />
        <span>{{ t('SUPPORT.TITLE') }}</span>
      </DropdownMenuItem>
      <CustomBrandPolicyWrapper
        v-for="item in items"
        :key="item.label"
        :show-on-custom-branded-instance="item.showOnCustomBrandedInstance"
      >
        <DropdownMenuItem as-child @select="selectedAction = item.click">
          <component
            :is="item.link ? (item.nativeLink ? 'a' : 'RouterLink') : 'button'"
            :to="item.link && !item.nativeLink ? item.link : undefined"
            :href="item.nativeLink ? item.link : undefined"
            :target="item.target"
            :rel="item.target === '_blank' ? 'noopener noreferrer' : undefined"
            :type="!item.link ? 'button' : undefined"
            class="inclamo-profile-action"
          >
            <Icon
              :icon="item.icon"
              class="size-4 shrink-0 text-ui-muted-foreground"
            />
            <span>{{ item.label }}</span>
          </component>
        </DropdownMenuItem>
      </CustomBrandPolicyWrapper>
    </DropdownMenuContent>
  </DropdownMenu>
</template>
