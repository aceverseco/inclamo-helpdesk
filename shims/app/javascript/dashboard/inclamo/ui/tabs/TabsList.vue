<script setup lang="ts">
import type { TabsListProps } from 'reka-ui';
import type { HTMLAttributes } from 'vue';
import { reactiveOmit } from '@vueuse/core';
import { TabsList } from 'reka-ui';
import { cn } from 'dashboard/inclamo/ui/utils';

const props = defineProps<
  TabsListProps & { class?: HTMLAttributes['class'] }
>();

const delegatedProps = reactiveOmit(props, 'class');
</script>

<template>
  <TabsList
    v-bind="delegatedProps"
    :class="
      cn(
        'inline-flex items-center justify-center rounded-lg bg-ui-muted p-1 text-ui-muted-foreground',
        props.class
      )
    "
  >
    <slot />
  </TabsList>
</template>
