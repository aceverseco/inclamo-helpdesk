<script setup lang="ts">
import type { TabsContentProps } from 'reka-ui';
import type { HTMLAttributes } from 'vue';
import { reactiveOmit } from '@vueuse/core';
import { TabsContent } from 'reka-ui';
import { cn } from 'dashboard/inclamo/ui/utils';

const props = defineProps<
  TabsContentProps & { class?: HTMLAttributes['class'] }
>();

const delegatedProps = reactiveOmit(props, 'class');
</script>

<template>
  <TabsContent
    :class="
      cn(
        'mt-2 ring-offset-ui-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ui-ring focus-visible:ring-offset-2',
        props.class
      )
    "
    v-bind="delegatedProps"
  >
    <slot />
  </TabsContent>
</template>
