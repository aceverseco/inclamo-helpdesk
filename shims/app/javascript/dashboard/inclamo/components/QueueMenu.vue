<script setup>
import { computed } from 'vue';
import { Button } from '../ui/button';
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
} from '../ui/dropdown-menu';
import { t } from '../i18n';
const props = defineProps({
  items: { type: Array, default: () => [] },
  activeTab: String,
});
const emit = defineEmits(['change']);
const selected = computed(() =>
  props.items.find(item => item.key === props.activeTab)
);
const labels = { me: 'MINE', all: 'ALL', unassigned: 'UNASSIGNED' };
const label = item =>
  labels[item?.key] ? t(`WORKSPACE.${labels[item.key]}`) : item?.name;
</script>
<template>
  <div class="inclamo-queue-menu">
    <DropdownMenu>
      <DropdownMenuTrigger as-child>
        <Button variant="ghost" size="sm" :aria-label="t('WORKSPACE.QUEUES')"
          >{{ label(selected)
          }}<span class="i-lucide-chevron-down" aria-hidden="true"
        /></Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="start" class="inclamo-menu-surface">
        <DropdownMenuRadioGroup
          :model-value="activeTab"
          @update:model-value="
            emit(
              'change',
              items.findIndex(item => item.key === $event)
            )
          "
        >
          <DropdownMenuRadioItem
            v-for="item in items"
            :key="item.key"
            :value="item.key"
            >{{ label(item) }}
            <span class="ms-auto ps-3">{{
              item.count
            }}</span></DropdownMenuRadioItem
          >
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  </div>
</template>
