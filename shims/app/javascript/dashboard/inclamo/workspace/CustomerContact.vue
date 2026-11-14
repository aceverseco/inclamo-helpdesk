<!-- The contact of the conversation inside CustomerSidePanel: the profile, the
     contact's actions and fields. Stands where Chatwoot's ContactInfo stood. -->
<script>
import { mapGetters } from 'vuex';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { useAlert } from 'dashboard/composables';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';
import { useAdmin } from 'dashboard/composables/useAdmin';
import ContactInfoRow from 'dashboard/routes/dashboard/conversation/contact/ContactInfoRow.vue';
import CustomerProfile from './CustomerProfile.vue';
import ViewAllConversations from 'dashboard/routes/dashboard/conversation/contact/ViewAllConversations.vue';
import SocialProfileLinks from 'dashboard/components-next/social-profiles/SocialProfileLinks.vue';
import EditContact from 'dashboard/routes/dashboard/conversation/contact/EditContact.vue';
import ContactMergeModal from 'dashboard/modules/contact/ContactMergeModal.vue';
import ContactDeleteModal from 'dashboard/modules/contact/ContactDeleteModal.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';

export default {
  components: {
    NextButton,
    ContactInfoRow,
    CustomerProfile,
    ViewAllConversations,
    EditContact,
    ComposeConversation,
    SocialProfileLinks,
    ContactMergeModal,
    ContactDeleteModal,
    VoiceCallButton,
  },
  props: {
    contact: {
      type: Object,
      default: () => ({}),
    },
    showAvatar: {
      type: Boolean,
      default: true,
    },
  },
  emits: ['panelClose'],
  setup() {
    const { isAdmin } = useAdmin();
    return {
      isAdmin,
    };
  },
  data() {
    return {
      showEditModal: false,
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'contacts/getUIFlags',
      currentChat: 'getSelectedChat',
      isFeatureEnabledOnAccount: 'accounts/isFeatureEnabledonAccount',
    }),
    hasCompaniesFeature() {
      return this.isFeatureEnabledOnAccount(
        Number(this.$route.params.accountId),
        FEATURE_FLAGS.COMPANIES
      );
    },
    contactProfileLink() {
      return `/app/accounts/${this.$route.params.accountId}/contacts/${this.contact.id}`;
    },
    companyLink() {
      return this.hasCompaniesFeature && this.contact.company_id
        ? `/app/accounts/${this.$route.params.accountId}/companies/${this.contact.company_id}`
        : '';
    },
    additionalAttributes() {
      return this.contact.additional_attributes || {};
    },
    location() {
      const {
        country = '',
        city = '',
        country_code: countryCode,
      } = this.additionalAttributes;
      const cityAndCountry = [city, country].filter(item => !!item).join(', ');

      if (!cityAndCountry) {
        return '';
      }
      return this.findCountryFlag(countryCode, cityAndCountry);
    },
    socialProfiles() {
      const {
        social_profiles: socialProfiles,
        screen_name: twitterScreenName,
        social_telegram_user_name: telegramUsername,
      } = this.additionalAttributes;

      const telegram = socialProfiles?.telegram || telegramUsername || '';
      const twitter = socialProfiles?.twitter || twitterScreenName || '';

      return {
        ...(socialProfiles || {}),
        twitter,
        telegram,
      };
    },
    whatsappUsername() {
      const username =
        this.socialProfiles.whatsapp ||
        this.additionalAttributes.social_whatsapp_user_name ||
        '';

      return username.toString().replace(/^@+/, '');
    },
    formattedWhatsappUsername() {
      return this.whatsappUsername ? `@${this.whatsappUsername}` : '';
    },
  },
  watch: {
    'contact.id': {
      handler(id) {
        this.$store.dispatch('contacts/fetchContactableInbox', id);
      },
      immediate: true,
    },
  },
  methods: {
    toggleEditModal() {
      this.showEditModal = !this.showEditModal;
    },
    findCountryFlag(countryCode, cityAndCountry) {
      try {
        if (!countryCode) {
          return `${cityAndCountry} 🌎`;
        }

        const code = countryCode?.toLowerCase();
        return `${cityAndCountry} <span class="fi fi-${code} size-3.5"></span>`;
      } catch (error) {
        return '';
      }
    },
    onFieldUpdate(field, value) {
      this.updateContactField({ [field]: value });
    },
    async updateContactField(attrs) {
      const contactId = this.contact.id;
      try {
        await this.$store.dispatch('contacts/update', {
          id: contactId,
          ...attrs,
        });
        useAlert(this.$t('CONTACT_FORM.SUCCESS_MESSAGE'));
        await this.$store.dispatch('contacts/fetchContactableInbox', contactId);
      } catch (error) {
        if (error instanceof DuplicateContactException) {
          const detail = error.contactErrorDetail;
          if (detail) {
            useAlert(detail);
          } else {
            const invalidAttrs = Array.isArray(error.data) ? error.data : [];
            if (invalidAttrs.includes('email')) {
              useAlert(this.$t('CONTACT_FORM.FORM.EMAIL_ADDRESS.DUPLICATE'));
            } else if (invalidAttrs.includes('phone_number')) {
              useAlert(this.$t('CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'));
            } else {
              useAlert(this.$t('CONTACT_FORM.ERROR_MESSAGE'));
            }
          }
        } else if (error instanceof ExceptionWithMessage) {
          useAlert(error.data);
        } else {
          useAlert(error.message || this.$t('CONTACT_FORM.ERROR_MESSAGE'));
        }
      }
    },
  },
};
</script>

<template>
  <CustomerProfile
    :contact="contact"
    :show-avatar="showAvatar"
    :profile-link="contactProfileLink"
    :location="
      [additionalAttributes.city, additionalAttributes.country]
        .filter(Boolean)
        .join(', ') || additionalAttributes.location
    "
  >
    <template #actions>
      <div class="flex items-center w-full mt-0.5 gap-2">
        <ComposeConversation :contact-id="String(contact.id)">
          <template #trigger>
            <NextButton
              v-tooltip.top-end="$t('CONTACT_PANEL.NEW_MESSAGE')"
              icon="i-lucide-message-circle"
              slate
              faded
              sm
            />
          </template>
        </ComposeConversation>
        <ViewAllConversations />
        <VoiceCallButton
          :phone="contact.phone_number"
          :contact-id="contact.id"
          :conversation-id="currentChat?.id"
          icon="i-lucide-phone"
          sm
          faded
          slate
          :tooltip-label="$t('CONTACT_PANEL.CALL')"
        />
        <NextButton
          v-tooltip.top-end="$t('EDIT_CONTACT.BUTTON_LABEL')"
          :aria-label="$t('EDIT_CONTACT.BUTTON_LABEL')"
          icon="i-lucide-pencil"
          slate
          faded
          sm
          @click="toggleEditModal"
        />
        <ContactMergeModal :primary-contact="contact">
          <template #trigger>
            <NextButton
              v-tooltip.top-end="$t('CONTACT_PANEL.MERGE_CONTACT')"
              icon="i-ph-arrows-merge"
              slate
              faded
              sm
              :disabled="uiFlags.isMerging"
            />
          </template>
        </ContactMergeModal>
        <ContactDeleteModal
          v-if="isAdmin"
          :contact="contact"
          @deleted="$emit('panelClose')"
        >
          <template #trigger>
            <NextButton
              v-tooltip.top-end="$t('DELETE_CONTACT.BUTTON_LABEL')"
              icon="i-ph-trash"
              slate
              faded
              sm
              ruby
              :disabled="uiFlags.isDeleting"
            />
          </template>
        </ContactDeleteModal>
      </div>
    </template>
    <template #fields>
      <div class="flex flex-col items-start w-full gap-2">
        <ContactInfoRow
          :href="contact.email ? `mailto:${contact.email}` : ''"
          :value="contact.email"
          icon="mail"
          emoji="✉️"
          :title="$t('CONTACT_PANEL.EMAIL_ADDRESS')"
          show-copy
          editable
          @update="value => onFieldUpdate('email', value)"
        />
        <ContactInfoRow
          :href="contact.phone_number ? `tel:${contact.phone_number}` : ''"
          :value="contact.phone_number"
          icon="call"
          emoji="📞"
          :title="$t('CONTACT_PANEL.PHONE_NUMBER')"
          show-copy
          editable
          @update="value => onFieldUpdate('phone_number', value)"
        />
        <ContactInfoRow
          v-if="formattedWhatsappUsername"
          :value="formattedWhatsappUsername"
          icon="brand-whatsapp"
          emoji="💬"
          :title="$t('CONTACT_PANEL.WHATSAPP_USERNAME')"
          show-copy
        />
        <ContactInfoRow
          v-if="contact.identifier"
          :value="contact.identifier"
          icon="contact-identify"
          emoji="🪪"
          :title="$t('CONTACT_PANEL.IDENTIFIER')"
        />
        <ContactInfoRow
          :href="companyLink"
          :value="additionalAttributes.company_name"
          icon="building-bank"
          emoji="🏢"
          :title="$t('CONTACT_PANEL.COMPANY')"
          :editable="!hasCompaniesFeature"
          @update="
            value =>
              updateContactField({
                additional_attributes: {
                  ...additionalAttributes,
                  company_name: value,
                },
              })
          "
        />
        <ContactInfoRow
          v-if="location || additionalAttributes.location"
          :value="location || additionalAttributes.location"
          icon="map"
          emoji="🌍"
          :title="$t('CONTACT_PANEL.LOCATION')"
        />
        <SocialProfileLinks :profiles="socialProfiles" class="my-2" />
      </div>
    </template>
  </CustomerProfile>
  <EditContact
    :show="showEditModal"
    :contact="contact"
    @cancel="toggleEditModal"
  />
</template>
