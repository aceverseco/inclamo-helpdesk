<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  Mail,
  Phone,
  MapPin,
  MoreHorizontal,
  ExternalLink,
} from 'lucide-vue-next';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { Button } from '../ui/button';
import { t } from '../i18n';
const props = defineProps({
  contact: { type: Object, required: true },
  showAvatar: { type: Boolean, default: true },
  profileLink: String,
  location: String,
});
const { locale } = useI18n();
const expanded = ref(false);
const actionsId = useId();
const since = computed(() =>
  props.contact?.created_at
    ? new Intl.DateTimeFormat(locale.value, {
        month: 'long',
        year: 'numeric',
      }).format(new Date(props.contact.created_at * 1000))
    : ''
);
</script>

<template>
  <div class="inclamo-ref">
    <div class="customer-profile">
      <div v-if="showAvatar" class="profile-avatar-wrap">
        <Avatar
          :name="contact.name"
          :src="contact.thumbnail"
          :size="58"
          rounded-full
        />
      </div>
      <div class="reference-profile-name">
        <h3>{{ contact.name }}</h3>
        <Button
          variant="ghost"
          size="icon-sm"
          :aria-label="t('WORKSPACE.CUSTOMER_ACTIONS')"
          :aria-expanded="expanded"
          :aria-controls="actionsId"
          @click="expanded = !expanded"
        >
          <MoreHorizontal />
        </Button>
      </div>
      <p v-if="since">{{ t('WORKSPACE.CUSTOMER_SINCE', { date: since }) }}</p>
      <div class="customer-contact">
        <a v-if="contact.email" :href="`mailto:${contact.email}`">
          <Mail />
          <span>{{ contact.email }}</span>
        </a>
        <a v-if="contact.phone_number" :href="`tel:${contact.phone_number}`">
          <Phone />
          <span>{{ contact.phone_number }}</span>
        </a>
        <div v-if="location">
          <MapPin />
          <span>{{ location }}</span>
        </div>
      </div>
      <div v-if="expanded" :id="actionsId" class="reference-contact-actions">
        <slot name="actions" />
        <a :href="profileLink" target="_blank" rel="noopener noreferrer">
          <ExternalLink />
          {{ t('WORKSPACE.VIEW_PROFILE') }}
        </a>
        <slot name="fields" />
      </div>
    </div>
  </div>
</template>
