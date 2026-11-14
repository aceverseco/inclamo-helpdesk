<!-- The customer side of a conversation: profile, orders, labels and Chatwoot's
     own sections under Manage. Stands where Chatwoot's ContactPanel stood;
     ConversationSidebar mounts it. -->
<script setup>
import { computed, watch, onMounted, ref } from 'vue';
import {
  useMapGetter,
  useFunctionGetter,
  useStore,
} from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import AccordionItem from 'dashboard/components/Accordion/AccordionItem.vue';
import ContactConversations from 'dashboard/routes/dashboard/conversation/ContactConversations.vue';
import ConversationAction from 'dashboard/routes/dashboard/conversation/ConversationAction.vue';
import ConversationParticipant from 'dashboard/routes/dashboard/conversation/ConversationParticipant.vue';
import CustomerContact from './CustomerContact.vue';
import ContactNotes from 'dashboard/routes/dashboard/conversation/contact/ContactNotes.vue';
import ConversationInfo from 'dashboard/routes/dashboard/conversation/ConversationInfo.vue';
import CustomAttributes from 'dashboard/routes/dashboard/conversation/customAttributes/CustomAttributes.vue';
import SharedFiles from 'dashboard/routes/dashboard/conversation/SharedFiles.vue';
import Draggable from 'vuedraggable';
import MacrosList from 'dashboard/routes/dashboard/conversation/Macros/List.vue';
import ShopifyOrdersList from 'dashboard/components/widgets/conversation/ShopifyOrdersList.vue';
import CustomerPane from './CustomerPane.vue';
import OrdersSection from '../components/OrdersSection.vue';
import ConversationLabels from 'dashboard/routes/dashboard/conversation/labels/LabelBox.vue';
import LinearIssuesList from 'dashboard/components/widgets/conversation/linear/IssuesList.vue';
import LinearSetupCTA from 'dashboard/components/widgets/conversation/linear/LinearSetupCTA.vue';
import StripeCustomer from 'dashboard/components/widgets/conversation/StripeCustomer.vue';
import extensionSections from 'dashboard/extensions/conversationSidebarSections';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  inboxId: {
    type: Number,
    default: undefined,
  },
});

const {
  updateUISettings,
  isContactSidebarItemOpen,
  conversationSidebarItemsOrder,
  toggleSidebarUIState,
  isOnExpandedLayout,
} = useUISettings();

const dragging = ref(false);
const extensionSection = name =>
  extensionSections.find(section => section.name === name);
const isExtensionSectionShown = name => {
  const { visible } = extensionSection(name);
  return !visible || visible(props.conversationId);
};
const conversationSidebarItems = ref([]);

const shopifyIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'shopify'
);

const isShopifyFeatureEnabled = computed(
  () => shopifyIntegration.value.enabled
);

const { isCloudFeatureEnabled } = useAccount();

const isLinearFeatureEnabled = computed(() =>
  isCloudFeatureEnabled(FEATURE_FLAGS.LINEAR)
);

const linearIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'linear'
);

const isLinearClientIdConfigured = computed(() => {
  return !!linearIntegration.value?.id;
});

const isLinearConnected = computed(
  () => linearIntegration.value?.enabled || false
);

const store = useStore();
const stripeIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'stripe'
);
const currentChat = useMapGetter('getSelectedChat');
const conversationId = computed(() => props.conversationId);
const conversationMetadataGetter = useMapGetter(
  'conversationMetadata/getConversationMetadata'
);
const currentConversationMetaData = computed(() =>
  conversationMetadataGetter.value(conversationId.value)
);
const conversationAdditionalAttributes = computed(
  () => currentConversationMetaData.value.additional_attributes || {}
);

const channelType = computed(() => currentChat.value.meta?.channel);

const contactGetter = useMapGetter('contacts/getContact');
const contactId = computed(() => currentChat.value.meta?.sender?.id);
const contact = computed(() => contactGetter.value(contactId.value));
const contactAdditionalAttributes = computed(
  () => contact.value.additional_attributes || {}
);

const appliedContactFilter = useMapGetter('getAppliedContactFilter');

const isListScopedToContact = computed(
  () =>
    !isOnExpandedLayout.value &&
    appliedContactFilter.value?.id === contactId.value
);

const getContactDetails = () => {
  if (contactId.value) {
    store.dispatch('contacts/show', { id: contactId.value });
  }
};

watch(contactId, (newContactId, prevContactId) => {
  if (newContactId && newContactId !== prevContactId) {
    getContactDetails();
  }
});

const onDragEnd = () => {
  dragging.value = false;
  updateUISettings({
    conversation_sidebar_items_order: conversationSidebarItems.value,
  });
};

const closeContactPanel = () => {
  updateUISettings({
    is_contact_sidebar_open: false,
    is_copilot_panel_open: false,
  });
};

onMounted(() => {
  conversationSidebarItems.value = conversationSidebarItemsOrder.value;
  getContactDetails();
  store.dispatch('attributes/get', 0);
  store.dispatch('integrations/get');
});
</script>

<template>
  <div class="inclamo-contact-panel w-full">
    <CustomerPane :conversation-id="conversationId" :contact-id="contactId" @close="closeContactPanel">
      <template #profile>
        <CustomerContact :contact="contact" :channel-type="channelType" />
      </template>
      <template #commerce>
        <OrdersSection :conversation-id="conversationId" :contact-id="contactId" :account-id="$route.params.accountId" />
      </template>
      <template #labels>
        <section class="reference-customer-tags">
          <div class="section-title"><h4>{{ $t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_LABELS') }}</h4></div>
          <ConversationLabels />
        </section>
      </template>
      <template #manage>
        <div class="px-2 pb-8 list-group">
          <Draggable
            :list="conversationSidebarItems"
            animation="200"
            ghost-class="ghost"
            handle=".drag-handle"
            item-key="name"
            class="flex flex-col gap-3"
            @start="dragging = true"
            @end="onDragEnd"
          >
            <template #item="{ element }">
              <div
                v-if="element.name === 'conversation_actions'"
                class="conversation--actions"
              >
                <AccordionItem
                  :title="
                    $t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_ACTIONS')
                  "
                  :is-open="isContactSidebarItemOpen('is_conv_actions_open')"
                  @toggle="
                    value => toggleSidebarUIState('is_conv_actions_open', value)
                  "
                >
                  <ConversationAction
                    :conversation-id="conversationId"
                    :inbox-id="inboxId"
                  />
                </AccordionItem>
              </div>
              <div
                v-else-if="element.name === 'conversation_participants'"
                class="conversation--actions"
              >
                <AccordionItem
                  :title="$t('CONVERSATION_PARTICIPANTS.SIDEBAR_TITLE')"
                  :is-open="
                    isContactSidebarItemOpen('is_conv_participants_open')
                  "
                  @toggle="
                    value =>
                      toggleSidebarUIState('is_conv_participants_open', value)
                  "
                >
                  <ConversationParticipant
                    :conversation-id="conversationId"
                    :inbox-id="inboxId"
                  />
                </AccordionItem>
              </div>
              <div v-else-if="element.name === 'conversation_info'">
                <AccordionItem
                  :title="
                    $t('CONVERSATION_SIDEBAR.ACCORDION.CONVERSATION_INFO')
                  "
                  :is-open="isContactSidebarItemOpen('is_conv_details_open')"
                  compact
                  @toggle="
                    value => toggleSidebarUIState('is_conv_details_open', value)
                  "
                >
                  <ConversationInfo
                    :conversation-attributes="conversationAdditionalAttributes"
                    :contact-attributes="contactAdditionalAttributes"
                  />
                </AccordionItem>
              </div>
              <div v-else-if="element.name === 'contact_attributes'">
                <AccordionItem
                  :title="
                    $t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_ATTRIBUTES')
                  "
                  :is-open="
                    isContactSidebarItemOpen('is_contact_attributes_open')
                  "
                  compact
                  @toggle="
                    value =>
                      toggleSidebarUIState('is_contact_attributes_open', value)
                  "
                >
                  <CustomAttributes
                    attribute-type="contact_attribute"
                    attribute-from="conversation_contact_panel"
                    :contact-id="contact.id"
                  />
                </AccordionItem>
              </div>
              <div
                v-else-if="
                  element.name === 'previous_conversation' &&
                  !isListScopedToContact
                "
              >
                <AccordionItem
                  v-if="contact.id"
                  :title="
                    $t('CONVERSATION_SIDEBAR.ACCORDION.PREVIOUS_CONVERSATION')
                  "
                  :is-open="isContactSidebarItemOpen('is_previous_conv_open')"
                  compact
                  @toggle="
                    value =>
                      toggleSidebarUIState('is_previous_conv_open', value)
                  "
                >
                  <ContactConversations
                    :contact-id="contact.id"
                    :conversation-id="conversationId"
                  />
                </AccordionItem>
              </div>
              <woot-feature-toggle
                v-else-if="element.name === 'macros'"
                feature-key="macros"
              >
                <AccordionItem
                  :title="$t('CONVERSATION_SIDEBAR.ACCORDION.MACROS')"
                  :is-open="isContactSidebarItemOpen('is_macro_open')"
                  compact
                  @toggle="
                    value => toggleSidebarUIState('is_macro_open', value)
                  "
                >
                  <MacrosList :conversation-id="conversationId" />
                </AccordionItem>
              </woot-feature-toggle>
              <div
                v-else-if="
                  element.name === 'linear_issues' &&
                  isLinearFeatureEnabled &&
                  isLinearClientIdConfigured
                "
              >
                <AccordionItem
                  :title="$t('CONVERSATION_SIDEBAR.ACCORDION.LINEAR_ISSUES')"
                  :is-open="isContactSidebarItemOpen('is_linear_issues_open')"
                  compact
                  @toggle="
                    value =>
                      toggleSidebarUIState('is_linear_issues_open', value)
                  "
                >
                  <LinearSetupCTA v-if="!isLinearConnected" />
                  <LinearIssuesList v-else :conversation-id="conversationId" />
                </AccordionItem>
              </div>
              <div
                v-else-if="
                  element.name === 'shopify_orders' && isShopifyFeatureEnabled
                "
              >
                <AccordionItem
                  :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHOPIFY_ORDERS')"
                  :is-open="isContactSidebarItemOpen('is_shopify_orders_open')"
                  compact
                  @toggle="
                    value =>
                      toggleSidebarUIState('is_shopify_orders_open', value)
                  "
                >
                  <ShopifyOrdersList :contact-id="contactId" />
                </AccordionItem>
              </div>
              <div
                v-else-if="
                  element.name === 'stripe_customer' &&
                  isCloudFeatureEnabled(FEATURE_FLAGS.STRIPE) &&
                  stripeIntegration.enabled
                "
              >
                <AccordionItem
                  :title="$t('STRIPE_INTEGRATION.TITLE')"
                  :is-open="isContactSidebarItemOpen('is_stripe_customer_open')"
                  compact
                  @toggle="
                    value =>
                      toggleSidebarUIState('is_stripe_customer_open', value)
                  "
                >
                  <StripeCustomer
                    v-if="isContactSidebarItemOpen('is_stripe_customer_open')"
                    :conversation-id="conversationId"
                    :contact-email="contact.email"
                  />
                </AccordionItem>
              </div>
              <div v-else-if="element.name === 'contact_notes'">
                <AccordionItem
                  :title="$t('CONVERSATION_SIDEBAR.ACCORDION.CONTACT_NOTES')"
                  :is-open="isContactSidebarItemOpen('is_contact_notes_open')"
                  compact
                  @toggle="
                    value =>
                      toggleSidebarUIState('is_contact_notes_open', value)
                  "
                >
                  <ContactNotes :contact-id="contactId" />
                </AccordionItem>
              </div>
              <div v-else-if="element.name === 'shared_files'">
                <AccordionItem
                  :title="$t('CONVERSATION_SIDEBAR.ACCORDION.SHARED_FILES')"
                  :is-open="isContactSidebarItemOpen('is_shared_files_open')"
                  compact
                  @toggle="
                    value => toggleSidebarUIState('is_shared_files_open', value)
                  "
                >
                  <SharedFiles />
                </AccordionItem>
              </div>
              <div
                v-else-if="
                  element.name !== 'inclamo_orders' &&
                  extensionSection(element.name)
                "
              >
                <AccordionItem
                  v-if="isExtensionSectionShown(element.name)"
                  :title="extensionSection(element.name).title()"
                  :is-open="
                    isContactSidebarItemOpen(
                      extensionSection(element.name).openKey
                    )
                  "
                  compact
                  @toggle="
                    value =>
                      toggleSidebarUIState(
                        extensionSection(element.name).openKey,
                        value
                      )
                  "
                >
                  <component
                    :is="extensionSection(element.name).component"
                    :conversation-id="conversationId"
                    :contact-id="contactId"
                  />
                </AccordionItem>
              </div>
            </template>
          </Draggable>
        </div>
      </template>
    </CustomerPane>
  </div>
</template>

<style lang="scss" scoped>
:deep(.contact--profile) {
  @apply pb-3 border-b border-solid border-n-weak;
}
</style>
