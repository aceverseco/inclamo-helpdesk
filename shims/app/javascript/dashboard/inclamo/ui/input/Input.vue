<script setup lang="ts">
import type { HTMLAttributes } from 'vue';
import { computed, ref } from 'vue';
import { cn } from 'dashboard/inclamo/ui/utils';

const props = defineProps<{
  defaultValue?: string | number;
  modelValue?: string | number;
  class?: HTMLAttributes['class'];
}>();

const emits = defineEmits<{
  (e: 'update:modelValue', payload: string | number): void;
}>();

// Keep the native field and its primitive on the same Vue reactivity instance.
const modelValue = computed({
  get: () => props.modelValue ?? props.defaultValue ?? '',
  set: value => emits('update:modelValue', value),
});
const inputRef = ref<HTMLInputElement | null>(null);
defineExpose({ focus: () => inputRef.value?.focus() });
</script>

<template>
  <input
    ref="inputRef"
    v-model="modelValue"
    :class="
      cn(
        'reset-base flex h-9 w-full rounded-md border border-ui-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-ui-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ui-ring disabled:cursor-not-allowed disabled:opacity-50',
        props.class
      )
    "
  />
</template>
