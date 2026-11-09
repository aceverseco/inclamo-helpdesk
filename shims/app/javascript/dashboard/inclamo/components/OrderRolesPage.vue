<script setup>
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import StaffPermissionsEditor from './StaffPermissionsEditor.vue';
import { t } from '../i18n';
</script>

<template>
  <SettingsLayout>
    <template #header>
      <BaseSettingsHeader :title="t('SETTINGS.ORDER_ROLES.TITLE')" :description="t('SETTINGS.ORDER_ROLES.INTRO')" />
    </template>
    <template #body><StaffPermissionsEditor /></template>
  </SettingsLayout>
</template>
