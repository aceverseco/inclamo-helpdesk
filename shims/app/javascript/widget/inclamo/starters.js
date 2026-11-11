// An unsent selection lives only until the native pre-chat form consumes it.
let selectedMessage = '';
export const selectStarter = message => {
  selectedMessage = message;
};
export const takeStarter = () => {
  const value = selectedMessage;
  selectedMessage = '';
  return value;
};
