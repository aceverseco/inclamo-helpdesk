<script setup lang="ts">
import { useAttrs } from "vue";
import { Button } from "@/components/ui/button";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
defineOptions({ inheritAttrs: false });
const attrs = useAttrs();
defineProps<{ label: string; active?: boolean }>();
</script>

<template>
  <Tooltip>
    <TooltipTrigger as-child>
      <Button
        v-bind="attrs"
        variant="ghost"
        size="icon"
        :aria-label="label"
        :class="cn('icon-button', { active }, attrs.class as string)"
      >
        <slot />
      </Button>
    </TooltipTrigger>
    <TooltipContent>{{ label }}</TooltipContent>
  </Tooltip>
</template>
