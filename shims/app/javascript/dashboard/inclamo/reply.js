// Puts text into the reply the agent is writing, at the cursor, through the
// event Chatwoot's own features use. The editor keeps its mode: in a private
// note the text lands in the note. Nothing is sent.
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

export const insertIntoReply = text => {
  if (text) emitter.emit(BUS_EVENTS.INSERT_INTO_RICH_EDITOR, text);
};
