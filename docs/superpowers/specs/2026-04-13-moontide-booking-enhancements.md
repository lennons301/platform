# Moontide Booking Enhancements — Design Spec

## Overview

Two enhancements to the Phase 2 booking system based on visual review feedback:
1. **Recurring schedule creation** in admin
2. **Calendar-based booking page** replacing the list view

---

## 1. Recurring Schedule Creation (Admin)

### What Changes

The admin schedule form (`/admin/schedule`) gains two optional fields:

- **"Repeat weekly" checkbox** — below the date field
- **"Number of weeks" number input** — visible when checkbox is checked, default 6

### Behaviour

When "Repeat weekly" is unchecked (default): existing single-class creation, no change.

When checked:
- API receives `repeatWeekly: true` and `numberOfWeeks: N`
- API creates N schedule rows, each 7 days apart starting from the selected date
- Each row gets the same class, time, capacity, and location
- Each row stores `recurringRule: "weekly:<group-uuid>"` linking them as a set
- Each schedule is independently bookable and cancellable (no cascade)
- Response returns all created schedules

### Files Changed

- `src/app/admin/schedule/page.tsx` — add checkbox + weeks input to form, update POST body
- `src/app/api/admin/schedules/route.ts` — handle `repeatWeekly`/`numberOfWeeks` in POST, generate N rows
- `tests/admin/schedules.test.ts` — add test for recurring creation

---

## 2. Calendar Booking Page (Public)

### Layout (Stacked — Mobile-First)

Top to bottom:
1. **Page heading** — "Book a Class" with accent divider
2. **Bundle banner** — prominent card: "Save with a 6-Class Bundle", £75 price, "Purchase Bundle →" link to `/book/bundle`. Larger and more visible than current small text link.
3. **Month calendar grid** — custom component, no third-party dependency
4. **Class list for selected date** — appears below calendar when a date is clicked

### Calendar Grid

- Standard month grid (7 columns: Mon–Sun)
- Previous/next month navigation arrows
- **Days with classes:** bright-orange (`#ff7a2f`) background tint, bold text, clickable cursor
- **Days without classes:** soft-moonstone (`#e7e3dc`) text, not clickable
- **Selected date:** solid bright-orange background with dawn-light text
- **Today:** sky-mist (`#dceaf4`) ring/border indicator
- **Past dates:** greyed out (soft-moonstone text), not clickable even if they had classes

### Class List (Below Calendar)

Appears when a date with classes is clicked. Shows heading with formatted date (e.g. "Sunday 5 April").

Each class card shows:
- Class title (e.g. "Prenatal Yoga")
- Time and location (e.g. "10:00–11:00 · Studio A")
- Price (e.g. "£15.00")
- Spots remaining (red text if < 3)
- "View class details →" link to `/classes/[slug]`
- Clicking the card enters the existing booking form (name, email, bundle checkbox)

### Data Flow

- Server component (`/book/page.tsx`) fetches all upcoming open schedules (existing query, unchanged)
- Client component receives the array, groups by date, builds the calendar
- No additional API calls — everything derived from the schedule data already fetched
- Calendar month navigation: if user navigates to a month with no data, show empty calendar with soft-moonstone days

### Colour Palette (from globals.css)

| Token | Hex | Calendar usage |
|-------|-----|----------------|
| `deep-tide-blue` | `#1e3a5f` | Day numbers with classes, headings |
| `deep-ocean` | `#2c3e50` | Secondary text, class card body |
| `ocean-light-blue` | `#5fa8d3` | Borders |
| `bright-orange` | `#ff7a2f` | Dates with classes (highlight), selected date, bundle CTA |
| `soft-moonstone` | `#e7e3dc` | Days without classes, card borders |
| `dawn-light` | `#f7f9fb` | Calendar background, card backgrounds |
| `seagrass` | `#6b8f71` | Spots remaining (healthy) |
| `sky-mist` | `#dceaf4` | Today indicator |

### Files Changed

- `src/app/book/booking-client.tsx` — replace list view with calendar + class list + bundle banner. Significant rewrite of the client component.
- `src/app/book/page.tsx` — no changes (server component query stays the same)

### What Stays The Same

- Booking form (name, email, bundle checkbox, submit) — unchanged
- Empty state ("No upcoming classes") — unchanged
- Bundle purchase page (`/book/bundle`) — unchanged
- Confirmation page — unchanged
- All APIs — unchanged

---

## Out of Scope

- Calendar drag-to-book or multi-day selection
- Week view or day view — month only
- Recurring schedule editing/deletion as a group (delete individually for now)
- Class descriptions on the calendar cards (link to detail page instead)
