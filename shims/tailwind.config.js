// Stands in for Chatwoot's tailwind.config.js (kept as
// tailwind.config.chatwoot.js): Chatwoot's configuration, with the workspace's
// font token ahead of the system fonts, its colours beside Chatwoot's, and the
// overlay's scripts among the files scanned for classes.
import { inclamoColors } from './app/javascript/dashboard/inclamo/ui/theme.js';

const chatwoot = require('./tailwind.config.chatwoot');

const withFontToken = fonts =>
  fonts.map(font =>
    font === '-apple-system' ? 'var(--inclamo-font-family, -apple-system)' : font
  );

module.exports = {
  ...chatwoot,
  content: [
    ...chatwoot.content,
    './app/javascript/dashboard/inclamo/**/*.{js,ts}',
  ],
  theme: {
    ...chatwoot.theme,
    extend: {
      ...chatwoot.theme.extend,
      textColor: {
        n: {
          brand: 'rgb(var(--inclamo-brand-text, 39 129 246) / <alpha-value>)',
        },
      },
      fontFamily: Object.fromEntries(
        Object.entries(chatwoot.theme.extend.fontFamily).map(
          ([name, fonts]) => [name, withFontToken(fonts)]
        )
      ),
    },
    colors: {
      ...chatwoot.theme.colors,
      ...inclamoColors,
      body: chatwoot.theme.colors.body,
    },
  },
};
