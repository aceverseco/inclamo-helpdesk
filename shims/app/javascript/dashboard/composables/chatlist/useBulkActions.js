// Stands in for Chatwoot's useBulkActions.js (kept as
// useBulkActions.chatwoot.js): a macro is checked by the overlay before it is
// sent to run on the selected conversations (dashboard/inclamo/macroSteps).
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import macroSteps from 'dashboard/inclamo/macroSteps';
import { useBulkActions as useChatwootBulkActions } from './useBulkActions.chatwoot';

export function useBulkActions() {
  const { t } = useI18n();
  const actions = useChatwootBulkActions();

  // A check that fails is told the way Chatwoot tells a macro that failed.
  const onExecuteMacro = async macro => {
    try {
      const allowed = macroSteps.beforeRun
        ? await macroSteps.beforeRun(macro, actions.selectedConversations.value)
        : true;
      if (!allowed) return;
    } catch (error) {
      useAlert(t('MACROS.ERROR'));
      return;
    }
    await actions.onExecuteMacro(macro);
  };

  return { ...actions, onExecuteMacro };
}
