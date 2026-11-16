// Stands in for Chatwoot's conversation.routes.js (kept as
// conversation.routes.chatwoot.js): a folder route also opens a team queue
// (dashboard/inclamo/teamQueues). Chatwoot guards these routes by its saved
// folders; a queue the user may open passes, anything else is left to
// Chatwoot's own guard.
import {
  isTeamQueueId,
  teamQueueAvailable,
} from 'dashboard/inclamo/teamQueues';
import chatwoot from './conversation.routes.chatwoot';

const openingTeamQueues = guard => async (to, from, next) => {
  if (isTeamQueueId(to.params.id) && (await teamQueueAvailable(to.params.id))) {
    next();
    return;
  }
  await guard(to, from, next);
};

export default {
  ...chatwoot,
  routes: chatwoot.routes.map(route =>
    route.beforeEnter
      ? { ...route, beforeEnter: openingTeamQueues(route.beforeEnter) }
      : route
  ),
};
