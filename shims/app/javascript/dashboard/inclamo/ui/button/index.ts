import type { VariantProps } from 'class-variance-authority';
import { cva } from 'class-variance-authority';

export { default as Button } from './Button.vue';

export const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ui-ring disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0',
  {
    variants: {
      variant: {
        default:
          'bg-ui-primary text-ui-primary-foreground shadow hover:bg-ui-primary/90',
        destructive:
          'bg-ui-destructive text-ui-destructive-foreground shadow-sm hover:bg-ui-destructive/90',
        outline:
          'border border-ui-input bg-ui-background shadow-sm hover:bg-ui-accent hover:text-ui-accent-foreground',
        secondary:
          'bg-ui-secondary text-ui-secondary-foreground shadow-sm hover:bg-ui-secondary/80',
        ghost: 'hover:bg-ui-accent hover:text-ui-accent-foreground',
        link: 'text-ui-primary underline-offset-4 hover:underline',
      },
      size: {
        default: 'h-9 px-4 py-2',
        xs: 'h-7 rounded px-2',
        sm: 'h-8 rounded-md px-3 text-xs',
        lg: 'h-10 rounded-md px-8',
        icon: 'h-9 w-9',
        'icon-sm': 'size-8',
        'icon-lg': 'size-10',
      },
    },
    defaultVariants: {
      variant: 'default',
      size: 'default',
    },
  }
);

export type ButtonVariants = VariantProps<typeof buttonVariants>;
