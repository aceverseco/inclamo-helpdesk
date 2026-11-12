import type { VariantProps } from 'class-variance-authority';
import { cva } from 'class-variance-authority';

export { default as Badge } from './Badge.vue';

export const badgeVariants = cva(
  'inline-flex gap-1 items-center rounded-md border px-2.5 py-0.5 text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-ui-ring focus:ring-offset-2',
  {
    variants: {
      variant: {
        default:
          'border-transparent bg-ui-primary text-ui-primary-foreground shadow hover:bg-ui-primary/80',
        secondary:
          'border-transparent bg-ui-secondary text-ui-secondary-foreground hover:bg-ui-secondary/80',
        destructive:
          'border-transparent bg-ui-destructive text-ui-destructive-foreground shadow hover:bg-ui-destructive/80',
        outline: 'text-ui-foreground',
      },
    },
    defaultVariants: {
      variant: 'default',
    },
  }
);

export type BadgeVariants = VariantProps<typeof badgeVariants>;
