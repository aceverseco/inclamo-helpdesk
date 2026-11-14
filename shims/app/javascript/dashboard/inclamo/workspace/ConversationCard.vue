<!-- One conversation in a list. Stands where Chatwoot's ConversationCard stood;
     ConversationItem and ContactConversations mount it. -->
<script setup>
import { computed, ref, watch } from 'vue';
import { getLastMessage } from 'dashboard/helper/conversationHelper';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import MessagePreview from 'dashboard/components/widgets/conversation/MessagePreview.vue';
import ActivityTime from './ActivityTime.vue';
import ConversationRow from './ConversationRow.vue';
import CardLabels from 'dashboard/components/widgets/conversation/conversationCardComponents/CardLabels.vue';
import CardPriorityIcon from 'dashboard/components-next/Conversation/ConversationCard/CardPriorityIcon.vue';
import SLACardLabel from 'dashboard/components/widgets/conversation/components/SLACardLabel.vue';
import InclamoSlaBadge from '../components/SlaBadge.vue';
import VoiceCallStatus from 'dashboard/components/widgets/conversation/VoiceCallStatus.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

const props = defineProps({
  chat: { type: Object, required: true },
  currentContact: { type: Object, required: true },
  assignee: { type: Object, default: () => ({}) },
  inbox: { type: Object, default: () => ({}) },
  selected: { type: Boolean, default: false },
  isActiveChat: { type: Boolean, default: false },
  showAssignee: { type: Boolean, default: false },
  showInboxName: { type: Boolean, default: false },
  hideThumbnail: { type: Boolean, default: false },
  compact: { type: Boolean, default: false },
});

const emit = defineEmits([
  'click',
  'contextmenu',
  'selectConversation',
  'deSelectConversation',
]);

const hovered = ref(false);

const unreadCount = computed(() => props.chat.unread_count);
const hasUnread = computed(() => unreadCount.value > 0);
const lastMessageInChat = computed(() => getLastMessage(props.chat));

const voiceCallData = computed(() => {
  const last = lastMessageInChat.value;
  if (last?.content_type !== 'voice_call' || !last.call) {
    return { status: null, direction: null };
  }
  return {
    status: last.call.status,
    direction: last.call.direction === 'outgoing' ? 'outbound' : 'inbound',
  };
});

const isAIAssignee = computed(() =>
  ['AgentBot', 'Captain::Assistant'].includes(props.chat?.meta?.assignee_type)
);

const hasSlaPolicyId = computed(
  () => props.chat?.applied_sla?.id && !props.currentContact?.blocked
);

const showLabelsSection = computed(() => {
  return props.chat.labels?.length > 0 || hasSlaPolicyId.value;
});

const messagePreviewClass = computed(() => {
  return [
    hasUnread.value ? 'font-medium text-n-slate-12' : 'text-n-slate-11',
    !props.compact && hasUnread.value ? 'ltr:pr-4 rtl:pl-4' : '',
    props.compact && hasUnread.value ? 'ltr:pr-6 rtl:pl-6' : '',
  ];
});

const onThumbnailHover = () => {
  hovered.value = !props.hideThumbnail;
};

const onThumbnailLeave = () => {
  hovered.value = false;
};

const onSelectConversation = checked => {
  if (checked) {
    emit('selectConversation', props.chat.id, props.inbox.id);
  } else {
    emit('deSelectConversation', props.chat.id, props.inbox.id);
  }
};

const selectedModel = computed({
  get: () => props.selected,
  set: value => onSelectConversation(value),
});

watch(
  () => props.chat.id,
  () => {
    hovered.value = false;
  }
);
</script>

<template>
  <div
    class="reference-row-host"
    :class="{ selected }"
    role="button"
    tabindex="0"
    :aria-pressed="isActiveChat"
    :aria-label="currentContact.name"
    @click="$emit('click', $event)"
    @keydown.enter.prevent="$emit('click', $event)"
    @contextmenu="$emit('contextmenu', $event)"
  >
    <ConversationRow
      :name="currentContact.name"
      :subject="chat.additional_attributes?.mail_subject || inbox.name"
      :selected="isActiveChat"
      :unread="hasUnread"
      :channel="inbox.channel_type"
    >
      <template #avatar>
        <div @mouseenter="onThumbnailHover" @mouseleave="onThumbnailLeave">
          <Avatar
            v-if="!hideThumbnail"
            :name="currentContact.name"
            :src="currentContact.thumbnail"
            :size="31"
            rounded-full
          >
            <template #overlay="{ size }">
              <label
                v-if="hovered || selected"
                class="absolute inset-0 grid place-items-center rounded-full backdrop-blur-sm"
                :style="{ width: `${size}px`, height: `${size}px` }"
                @click.stop
              >
                <Checkbox v-model="selectedModel" />
              </label>
            </template>
          </Avatar>
        </div>
      </template>
      <template #time>
        <ActivityTime :timestamp="chat.timestamp" />
      </template>
      <template #preview>
        <VoiceCallStatus
          v-if="voiceCallData.status"
          :status="voiceCallData.status"
          :direction="voiceCallData.direction"
          :message-preview-class="messagePreviewClass"
        />
        <MessagePreview
          v-else-if="lastMessageInChat"
          :message="lastMessageInChat"
        />
        <span v-else>{{ $t('CHAT_LIST.NO_MESSAGES') }}</span>
      </template>
      <template #sla>
        <InclamoSlaBadge
          :conversation-id="chat.id"
          :status="chat.status"
          :activity="chat.timestamp"
        />
      </template>
      <template #labels>
        <CardLabels v-if="showLabelsSection" :conversation-labels="chat.labels">
          <template v-if="hasSlaPolicyId" #before>
            <SLACardLabel :chat="chat" />
          </template>
        </CardLabels>
        <span
          v-else-if="showInboxName && inbox.name"
          class="conversation-tag"
          >{{ inbox.name }}</span
        >
      </template>
      <template #meta>
        <Icon
          v-if="showAssignee && assignee.name"
          :icon="isAIAssignee ? 'i-lucide-bot' : 'i-lucide-user-round'"
          :title="assignee.name"
          class="size-3"
        />
        <CardPriorityIcon :priority="chat.priority" class="priority-flag" />
      </template>
    </ConversationRow>
  </div>
</template>
