// The order steps the overlay adds to macros, and the confirmation before a
// macro with order steps runs. Chatwoot reads this through its macro seam
// (dashboard/extensions/macroSteps.js). The server runs such a macro from the
// dashboard only after the agent's "Run" in the confirmation, and checks every
// step again when it runs.
import { createApp, reactive } from 'vue';
import { useAlert } from 'dashboard/composables';
import InclamoAPI from './api';
import { t } from './i18n';

export const STEP_KEYS = ['inclamo_refund_full', 'inclamo_refund_shipping', 'inclamo_cancel_order', 'inclamo_replacement'];
const ICONS = {
  inclamo_refund_full: 'i-lucide-undo-2',
  inclamo_refund_shipping: 'i-lucide-truck',
  inclamo_cancel_order: 'i-lucide-circle-x',
  inclamo_replacement: 'i-lucide-package',
};
// The editor asks when it opens; one answer serves the renders right after it.
const FRESH_FOR = 2_000;

const connection = reactive({ working: false });
let checkedAt = 0;
let checking = null;
// Counts the answers forgotten: one that comes back after it is dropped.
let round = 0;

// Asks whether the account has a working store connection, unless it was asked a moment ago.
export const checkConnection = () => {
  if (checking || Date.now() - checkedAt < FRESH_FOR) return checking;
  const asked = round;
  const settle = working => {
    if (asked !== round) return;
    connection.working = working;
    checkedAt = Date.now();
    checking = null;
  };
  checking = Promise.resolve()
    .then(() => InclamoAPI.getConnection())
    .then(
      ({ data }) => settle(data?.connected === true && data.status === 'working'),
      () => settle(false)
    );
  return checking;
};

export const forgetConnection = () => {
  round += 1;
  checkedAt = 0;
  checking = null;
  connection.working = false;
};

export const hasOrderSteps = macro => (macro?.actions || []).some(action => STEP_KEYS.includes(action.action_name));

// Offered in the macro editor only while the store connection works; named in previews always.
const steps = STEP_KEYS.map(key => ({
  key,
  icon: ICONS[key],
  label: () => t(`MACRO_STEPS.STEPS.${key}.LABEL`),
  description: () => t(`MACRO_STEPS.STEPS.${key}.DESCRIPTION`),
  get available() {
    checkConnection();
    return connection.working;
  },
}));

// Shows the confirmation in an app of its own: a macro is run from places
// (the sidebar, the reply box, a shortcut, the bulk bar) that have no room
// for a dialog of ours.
const confirmRun = async (macro, conversationId) => {
  const [{ createI18n }, { default: store }, { default: MacroConfirmation }] = await Promise.all([
    import('vue-i18n'),
    import('dashboard/store'),
    import('./components/MacroConfirmation.vue'),
  ]);
  return new Promise(resolve => {
    const host = document.createElement('div');
    document.body.appendChild(host);
    const app = createApp(MacroConfirmation, {
      macro,
      conversationId,
      onAnswer: answer => {
        resolve(answer === true);
        setTimeout(() => {
          app.unmount();
          host.remove();
        }, 0);
      },
    });
    app.use(store);
    app.use(createI18n({ legacy: false, locale: 'en', messages: {} }));
    app.mount(host);
  });
};

// The macro as the server holds it now: the copy this page loaded may be
// older than an order step added since. Without an answer the page's copy is
// used, and the server refuses order steps that were not confirmed.
const latest = async macro => {
  try {
    const { data } = await InclamoAPI.getMacro(macro.id);
    return data?.payload?.actions ? data.payload : macro;
  } catch (error) {
    return macro;
  }
};

// A macro without order steps runs as before. One with order steps runs in
// one conversation at a time, after the agent confirms. Never rejects: what
// fails here leaves the macro not run, and says so.
const beforeRun = async (macro, conversationIds) => {
  try {
    const current = await latest(macro);
    if (!hasOrderSteps(current)) return true;
    const ids = [].concat(conversationIds ?? []);
    if (ids.length !== 1) {
      useAlert(t('MACRO_STEPS.ONE_AT_A_TIME'));
      return false;
    }
    return await confirmRun(current, ids[0]);
  } catch (error) {
    useAlert(t('MACRO_STEPS.CONFIRM.NOT_OPENED'));
    return false;
  }
};

export default { steps, beforeRun };
