<!--
  Stands in for Chatwoot's PreChatForm.vue (kept beside this file as PreChatForm.chatwoot.vue).
  It is Chatwoot's component as the workspace draws it: part of the website widget.
  When Chatwoot changes its file the build stops (custom/CHATWOOT_FILES);
  carry their change over into this one.
-->
<script>
import { mapActions } from 'vuex';
import { useRouter } from 'vue-router';
import PreChatForm from '../components/PreChat/Form.vue';
import configMixin from '../mixins/configMixin';
import { ON_CONVERSATION_CREATED } from '../constants/widgetBusEvents';
import { emitter } from 'shared/helpers/mitt';

export default {
  components: {
    PreChatForm,
  },
  mixins: [configMixin],
  data() {
    return { hasDeliveryError: false };
  },
  setup() {
    const router = useRouter();
    return { router };
  },
  mounted() {
    // Register event listener for conversation creation
    emitter.on(ON_CONVERSATION_CREATED, this.handleConversationCreated);
  },
  beforeUnmount() {
    emitter.off(ON_CONVERSATION_CREATED, this.handleConversationCreated);
  },
  methods: {
    ...mapActions('conversation', ['clearConversations']),
    ...mapActions('conversationAttributes', ['clearConversationAttributes']),
    handleConversationCreated() {
      // Redirect to messages page after conversation is created
      this.router.replace({ name: 'messages' });
      // Only after successful navigation, reset the isUpdatingRoute UIflag in app/javascript/widget/router.js
      // See issue: https://github.com/chatwoot/chatwoot/issues/10736
    },

    async onSubmit({
      fullName,
      emailAddress,
      message,
      activeCampaignId,
      phoneNumber,
      contactCustomAttributes,
      conversationCustomAttributes,
    }) {
      this.hasDeliveryError = false;
      // Contact custom attributes are sent within the same request that
      // identifies the contact. A separate update call would race the contact
      // merge on the server (matching email/phone) and write the values to
      // the destroyed contact, silently losing them.
      if (activeCampaignId) {
        emitter.emit('execute-campaign', {
          campaignId: activeCampaignId,
          customAttributes: conversationCustomAttributes,
        });
        this.$store.dispatch('contacts/update', {
          user: {
            email: emailAddress,
            name: fullName,
            phone_number: phoneNumber,
            custom_attributes: contactCustomAttributes,
          },
        });
      } else {
        this.clearConversations();
        this.clearConversationAttributes();
        const sent = await this.$store.dispatch(
          'conversation/createConversation',
          {
            fullName: fullName,
            emailAddress: emailAddress,
            message: message,
            phoneNumber: phoneNumber,
            customAttributes: conversationCustomAttributes,
            contactCustomAttributes: contactCustomAttributes,
          }
        );
        this.hasDeliveryError = sent === false;
      }
    },
  },
};
</script>

<template>
  <div class="flex flex-col flex-1 overflow-auto">
    <p
      v-if="hasDeliveryError"
      role="alert"
      class="px-6 pt-3 text-sm text-n-ruby-10"
    >
      {{ $t('COMPONENTS.MESSAGE_BUBBLE.ERROR_MESSAGE') }}
    </p>
    <PreChatForm :options="preChatFormOptions" @submit-pre-chat="onSubmit" />
  </div>
</template>
