import animate from "tailwindcss-animate";

export default {
  content: ["./index.html", "./src/**/*.{vue,ts}"],
  theme: {
    extend: {
      colors: Object.fromEntries(
        [
          "background",
          "foreground",
          "border",
          "input",
          "ring",
          "primary",
          "primary-foreground",
          "secondary",
          "secondary-foreground",
          "muted",
          "muted-foreground",
          "accent",
          "accent-foreground",
          "destructive",
          "destructive-foreground",
          "popover",
          "popover-foreground",
          "card",
          "card-foreground",
        ].map((name) => [name, `hsl(var(--${name}) / <alpha-value>)`]),
      ),
      borderRadius: {
        lg: "var(--radius)",
        md: "calc(var(--radius) - 2px)",
        sm: "calc(var(--radius) - 4px)",
      },
      fontFamily: { sans: ["Inter Variable", "sans-serif"] },
    },
  },
  plugins: [animate],
};
