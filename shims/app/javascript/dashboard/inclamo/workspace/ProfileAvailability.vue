<script setup>
import { useI18n } from 'vue-i18n';
import {
  DropdownMenuSub,
  DropdownMenuSubTrigger,
  DropdownMenuSubContent,
  DropdownMenuPortal,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuCheckboxItem,
} from '../ui/dropdown-menu';

defineProps({
  statuses: { type: Array, required: true },
  availability: { type: String, required: true },
  autoOffline: Boolean,
});
const emit = defineEmits(['availability', 'update:autoOffline']);
const { t: nativeT } = useI18n();
</script>

<template>
  <DropdownMenuSub>
    <DropdownMenuSubTrigger
      class="inclamo-profile-status"
      data-testid="inclamo-profile-status"
    >
      <span>{{ nativeT('SIDEBAR.SET_YOUR_AVAILABILITY') }}</span>
      <span
        class="inclamo-profile-current-status"
        :class="statuses.find(status => status.value === availability)?.color"
        aria-hidden="true"
      />
    </DropdownMenuSubTrigger>
    <DropdownMenuPortal>
      <DropdownMenuSubContent
        class="inclamo-profile-status-menu"
        data-popover-content
        :collision-padding="8"
        :side-offset="4"
      >
        <DropdownMenuRadioGroup
          :model-value="availability"
          @update:model-value="emit('availability', $event)"
        >
          <DropdownMenuRadioItem
            v-for="status in statuses"
            :key="status.value"
            :value="status.value"
          >
            <span
              class="size-2 rounded-full me-2 shrink-0"
              :class="status.color"
            />
            {{ status.label }}
          </DropdownMenuRadioItem>
        </DropdownMenuRadioGroup>
      </DropdownMenuSubContent>
    </DropdownMenuPortal>
  </DropdownMenuSub>
  <DropdownMenuCheckboxItem
    :model-value="autoOffline"
    :title="nativeT('SIDEBAR.SET_AUTO_OFFLINE.INFO_SHORT')"
    :aria-description="nativeT('SIDEBAR.SET_AUTO_OFFLINE.INFO_SHORT')"
    class="inclamo-profile-auto-offline"
    @select.prevent
    @update:model-value="emit('update:autoOffline', $event)"
  >
    {{ nativeT('SIDEBAR.SET_AUTO_OFFLINE.TEXT') }}
  </DropdownMenuCheckboxItem>
</template>
