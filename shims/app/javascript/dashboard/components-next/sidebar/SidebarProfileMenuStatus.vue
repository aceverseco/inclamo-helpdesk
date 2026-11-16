<!--
  Stands in for Chatwoot's SidebarProfileMenuStatus.vue (kept beside this file as SidebarProfileMenuStatus.chatwoot.vue).
  It is Chatwoot's component as the workspace draws it: part of the workspace navigation.
  When Chatwoot changes its file the build stops (custom/CHATWOOT_FILES);
  carry their change over into this one.
-->
<script setup>
import { computed } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import wootConstants from 'dashboard/constants/globals';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useImpersonation } from 'dashboard/composables/useImpersonation';

import ProfileAvailability from 'dashboard/inclamo/workspace/ProfileAvailability.vue';

const { t } = useI18n();
const store = useStore();
const currentUserAvailability = useMapGetter('getCurrentUserAvailability');
const currentAccountId = useMapGetter('getCurrentAccountId');
const currentUserAutoOffline = useMapGetter('getCurrentUserAutoOffline');

const { isImpersonating } = useImpersonation();

const { AVAILABILITY_STATUS_KEYS } = wootConstants;
const statusList = computed(() => {
  return [
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.ONLINE'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.BUSY'),
    t('PROFILE_SETTINGS.FORM.AVAILABILITY.STATUS.OFFLINE'),
  ];
});

const statusColors = ['bg-n-teal-9', 'bg-n-amber-9', 'bg-n-slate-9'];

const availabilityStatuses = computed(() => {
  return statusList.value.map((statusLabel, index) => ({
    label: statusLabel,
    value: AVAILABILITY_STATUS_KEYS[index],
    color: statusColors[index],
    active: currentUserAvailability.value === AVAILABILITY_STATUS_KEYS[index],
  }));
});

const autoOfflineToggle = computed({
  get: () => currentUserAutoOffline.value,
  set: autoOffline => {
    store.dispatch('updateAutoOffline', {
      accountId: currentAccountId.value,
      autoOffline,
    });
  },
});

function changeAvailabilityStatus(availability) {
  if (isImpersonating.value) {
    useAlert(t('PROFILE_SETTINGS.FORM.AVAILABILITY.IMPERSONATING_ERROR'));
    return;
  }
  try {
    store.dispatch('updateAvailability', {
      availability,
      account_id: currentAccountId.value,
    });
  } catch (error) {
    useAlert(t('PROFILE_SETTINGS.FORM.AVAILABILITY.SET_AVAILABILITY_ERROR'));
  }
}
</script>

<template>
  <ProfileAvailability
    v-model:auto-offline="autoOfflineToggle"
    :statuses="availabilityStatuses"
    :availability="currentUserAvailability"
    @availability="changeAvailabilityStatus"
  />
</template>
