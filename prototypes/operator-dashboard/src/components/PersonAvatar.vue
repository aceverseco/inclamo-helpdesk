<script setup lang="ts">
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
defineProps<{ initials: string; tone?: string; large?: boolean }>();
</script>

<template>
  <Avatar :class="['person-avatar', tone || 'sky', { large }]">
    <AvatarFallback>{{ initials }}</AvatarFallback>
  </Avatar>
</template>
