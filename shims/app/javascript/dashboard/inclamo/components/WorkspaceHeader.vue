<script setup>
import { useAccount } from "dashboard/composables/useAccount";
import { useMapGetter } from "dashboard/composables/store";
import Avatar from "dashboard/components-next/avatar/Avatar.vue";
import { t } from "../i18n";
const { currentAccount } = useAccount();
const currentUser = useMapGetter("getCurrentUser");
</script>

<template>
  <header class="inclamo-workspace-header">
    <div class="inclamo-workspace-breadcrumb">
      <span class="i-lucide-panels-top-left" aria-hidden="true" />
      <span>{{ t("BRAND.WORKSPACE") }}</span>
      <span class="i-lucide-chevron-right" aria-hidden="true" />
      <strong>{{ currentAccount?.name }}</strong>
    </div>
    <div v-if="currentUser?.name" class="inclamo-workspace-user">
      <span>{{ currentUser.name }}</span>
      <Avatar
        :name="currentUser.name"
        :src="currentUser.avatar_url"
        :size="24"
      />
    </div>
  </header>
</template>
