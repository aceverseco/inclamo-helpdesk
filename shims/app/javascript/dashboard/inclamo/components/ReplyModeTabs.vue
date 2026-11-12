<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { Tabs, TabsList, TabsTrigger } from '../ui/tabs';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
const props = defineProps({
  mode: String,
  disabled: Boolean,
  isReplyRestricted: Boolean,
});
const emit = defineEmits(['toggleMode']);
const { t: nativeT } = useI18n();
const selected = computed(() =>
  props.isReplyRestricted ? REPLY_EDITOR_MODES.NOTE : props.mode
);
function select(mode) {
  if (mode !== selected.value) emit('toggleMode');
}
</script>
<template>
  <Tabs
    :model-value="selected"
    class="inclamo-reply-tabs"
    @update:model-value="select"
  >
    <TabsList>
      <TabsTrigger
        :value="REPLY_EDITOR_MODES.REPLY"
        :disabled="disabled || isReplyRestricted"
        >{{ nativeT('CONVERSATION.REPLYBOX.REPLY') }}</TabsTrigger
      >
      <TabsTrigger :value="REPLY_EDITOR_MODES.NOTE" :disabled="disabled">{{
        nativeT('CONVERSATION.REPLYBOX.PRIVATE_NOTE')
      }}</TabsTrigger>
    </TabsList>
  </Tabs>
</template>
