<script setup>
import { Mail, MessageCircle, Phone, Instagram } from 'lucide-vue-next';
import { computed } from 'vue';
const props = defineProps({
  name: String,
  subject: String,
  selected: Boolean,
  unread: Boolean,
  channel: String,
});
const icon = computed(
  () =>
    ({
      'Channel::Email': Mail,
      'Channel::Instagram': Instagram,
      'Channel::Voice': Phone,
    })[props.channel] || MessageCircle
);
</script>

<template>
  <div class="inclamo-ref">
    <div class="conversation-row" :class="{ selected, unread }">
      <div class="row-avatar">
        <slot name="avatar" />
        <span class="channel-bubble"><component :is="icon" /></span>
      </div>
      <div class="row-content">
        <div class="row-first">
          <strong>{{ name }}</strong>
          <slot name="time" />
        </div>
        <div v-if="subject" class="row-subject">{{ subject }}</div>
        <div class="row-preview"><slot name="preview" /></div>
        <div class="row-bottom">
          <slot name="labels" />
          <slot name="meta" />
          <i v-if="unread" class="unread-dot" />
        </div>
      </div>
    </div>
  </div>
</template>
