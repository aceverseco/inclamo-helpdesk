// Stands in for Chatwoot's tailwind.superadmin.config.js (kept as
// tailwind.superadmin.config.chatwoot.js): the administration stylesheet is
// also built from the overlay's templates that stand in for Chatwoot's.
const chatwoot = require('./tailwind.superadmin.config.chatwoot');

module.exports = {
  ...chatwoot,
  content: [
    ...chatwoot.content,
    './custom/app/views/layouts/super_admin/**/*.erb',
    './custom/app/views/super_admin/**/*.erb',
    './custom/app/views/installation/**/*.erb',
  ],
};
