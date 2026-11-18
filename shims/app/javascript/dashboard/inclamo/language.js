// Keeps the overlay's own screens in the interface language Chatwoot chooses.
// Chatwoot writes its choice (the staff member's language, else the account's)
// to the application's translation instance: on load, when the account is
// read, and when either setting is saved. This follows that one place.
import { watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { setLanguage } from './i18n';
import { installPluralRules } from './plural';

export const useInterfaceLanguage = () => {
  const application = useI18n({ useScope: 'global' });
  installPluralRules(application);
  watch(application.locale, setLanguage, { immediate: true });
};
