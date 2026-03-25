# UI Choice

**Current default:** shadcn/ui + Tailwind CSS

## Decision

All frontend projects use shadcn/ui components with Tailwind CSS for styling. This provides consistent design language across the estate with full customisation control (components are source code, not a dependency).

## Conventions

- Use `cn()` utility (clsx + tailwind-merge) for conditional classes
- Dark mode via `className="dark"` on `<html>`
- Geist Sans for interface text, Geist Mono for code/metrics

## Canonical values

For use in `products/*.yaml` under `choices.ui`:
- `shadcn-tailwind` — shadcn/ui + Tailwind CSS (default)
