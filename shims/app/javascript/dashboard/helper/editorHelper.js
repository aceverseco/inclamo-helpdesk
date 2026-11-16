// Stands in for Chatwoot's editorHelper.js (kept as editorHelper.chatwoot.js):
// a reply also resolves the overlay's variables (dashboard/inclamo/replyVariables).
import replyVariables from 'dashboard/inclamo/replyVariables';
import { getReplyVariables as getChatwootReplyVariables } from './editorHelper.chatwoot';

export const getReplyVariables = context => ({
  ...getChatwootReplyVariables(context),
  ...Object.assign({}, ...replyVariables.map(entry => entry.values(context))),
});

// The rest is Chatwoot's, as it is.
export {
  extractTextFromMarkdown,
  stripInlineBase64Images,
  stripUnsupportedMarkdown,
  SIGNATURE_DELIMITER,
  cleanSignature,
  findSignatureInBody,
  getEffectiveChannelType,
  appendSignature,
  removeSignature,
  replaceSignature,
  scrollCursorIntoView,
  collapseSelection,
  insertAtCursor,
  findNodeToInsertImage,
  stripUnsupportedFormatting,
  resolveVariableText,
  resolveVariablesInMessage,
  getAgentVariables,
  getContactVariables,
  createVariableInputRule,
  getContentNode,
  getFormattingForEditor,
  getSelectionCoords,
  getMenuAnchor,
  calculateMenuPosition,
} from './editorHelper.chatwoot';
