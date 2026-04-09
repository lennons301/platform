# Moontide — Website Design Spec

## Overview

Website for Moontide, a wellbeing space for women navigating change through yoga, coaching, and embodied connection. The brand centres on the phases of women's lives mirrored in the moon's cycles and the movement of the tides.

**Owner:** Gabrielle Waring (gwaring5@googlemail.com)
**Domain:** gabriellemoontide.co.uk (or similar .com — to be purchased)
**Instagram:** Existing account (URL TBC)

---

## Architecture

### Stack

| Layer | Choice | Notes |
|-------|--------|-------|
| Framework | Next.js 16 (App Router) | React 19, TypeScript 5.7, Node 22 |
| Hosting | Vercel Hobby | Free tier, upgrade to Pro if revenue-generating |
| Database | Neon (Postgres) | Drizzle ORM, local Postgres via Docker for dev |
| Payments | Stripe Checkout | Hosted payment page — PCI handled by Stripe |
| CMS | Sanity | Free tier (3 users, 500k API requests/mo) |
| Auth | Better Auth | Admin-only, single account, email/password |
| UI | shadcn/ui + Tailwind CSS | Platform default |
| Secrets | Doppler | dev/stg/prd configs |
| Email | Resend | Contact form forwarding, future reminders/subscriptions |
| Package manager | npm | |

### System Context

```
                    ┌──────────────┐
                    │   Customer   │
                    │  (browser)   │
                    └──────┬───────┘
                           │
                    ┌──────▼───────┐
                    │   Vercel     │
                    │  Next.js 16  │
                    │              │
                    │ Public Site  │
                    │ Admin Panel  │
                    │ API Routes   │
                    └──┬───┬───┬───┘
                       │   │   │
              ┌────────┘   │   └────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌──────────┐ ┌──────────┐
        │   Neon   │ │  Stripe  │ │  Sanity  │
        │ Postgres │ │ Checkout │ │   CMS    │
        └──────────┘ └──────────┘ └──────────┘
                                        │
                                  ┌─────▼─────┐
                                  │ Gabrielle  │
                                  │ (editor)   │
                                  └────────────┘
```

**Key architectural decisions:**

- **Single Next.js app** with public routes and a protected `/admin` area — no separate admin application.
- **No public-facing authentication.** Customers don't create accounts. They book and pay as guests. Bundle redemption uses email lookup only (no password).
- **Sanity manages editorial content** (page text, images, service descriptions). Transactional data (schedules, bookings, bundles) lives in Neon and is managed via the admin dashboard.
- **Stripe Checkout** handles all payment complexity. Users redirect to Stripe's hosted page, then return. Webhooks update booking status. Supports Apple Pay/Google Pay out of the box.
- **Resend** for transactional email (contact form forwarding at launch, booking confirmations and reminders later).

### GDPR & Data

Minimal personal data surface — no user accounts. Data held:

- **Bookings:** name, email, class booked, payment reference
- **Bundles:** email, purchase date, expiry, credits remaining
- **Contact form:** name, email, subject, message
- **Stripe:** payment data (held by Stripe, not in our DB)

Privacy policy and cookie notice needed but lightweight given no tracking/analytics at launch.

---

## Data Model

### Database Tables (Neon / Drizzle)

**classes** — service types
- `id`, `slug`, `sanity_id` (links to Sanity service document), `category` (class | coaching | community), `booking_type` (stripe | contact), `active`

**schedules** — specific class instances
- `id`, `class_id` (FK), `date`, `start_time`, `end_time`, `capacity`, `booked_count`, `location`, `recurring_rule` (nullable, for future recurring support), `status` (open | full | cancelled)

**bookings** — customer places
- `id`, `schedule_id` (FK), `customer_name`, `customer_email`, `stripe_payment_id` (nullable — null for bundle redemptions), `bundle_id` (nullable — set for bundle redemptions), `status` (confirmed | cancelled | waitlisted), `created_at`

**bundles** — purchased class packs
- `id`, `customer_email`, `credits_total` (6), `credits_remaining`, `stripe_payment_id`, `purchased_at`, `expires_at` (purchased_at + 90 days), `status` (active | expired | exhausted)

**contact_submissions** — contact form entries
- `id`, `name`, `email`, `subject`, `message`, `created_at`, `read` (boolean)

### CMS Schema (Sanity)

**siteSettings** (singleton) — logo, site title, Instagram URL, contact email, footer links

**page** — slug, title, content blocks (rich text, images, CTAs)

**service** — title, slug, description, image, category, booking_type, display_order

**communityEvent** — title, date, description, location

**trainer** — name, bio, photo, qualifications list

### CMS vs Database Boundary

| Sanity (content) | Neon (transactional) |
|---|---|
| Service descriptions & images | Class schedules & times |
| Page text & layout | Bookings & capacity |
| About me / qualifications | Bundle purchases & credits |
| Community event listings | Contact form submissions |
| T&Cs text | Payment records |
| Site settings / links | |

**Rule:** Words and pictures → Sanity. Dates, money, and capacity → database.

---

## Booking Flows

### Individual Class Booking

1. Customer browses classes on site (content from Sanity, schedule from DB)
2. Selects a class instance → sees availability (X of Y spots remaining)
3. Clicks "Book" → redirected to Stripe Checkout (class name, price pre-configured)
4. Pays on Stripe's hosted page
5. Stripe webhook → API route creates booking record, increments `booked_count`
6. Customer receives Stripe payment confirmation email
7. Customer redirected to confirmation page

### Bundle Purchase

1. Customer navigates to bundle purchase page
2. Clicks "Buy 6-Class Bundle" → Stripe Checkout
3. Stripe webhook → creates bundle record (6 credits, 90-day expiry)
4. Customer returns to site with confirmation

### Bundle Redemption

1. Customer selects a class to book, enters email
2. System looks up active bundles for that email (credits > 0, not expired)
3. If valid bundle found → deducts a credit, creates booking (no Stripe redirect)
4. If no bundle found → falls through to standard Stripe Checkout flow

### Cancellation / Rescheduling

Per T&Cs: all purchases non-refundable. Customer contacts Gabrielle directly. Gabrielle handles via admin dashboard:
- Mark booking as cancelled
- Issue credit (for class cancellations by Gabrielle) — manually adjusted in admin

---

## Page Structure

### Public Pages

```
/                       — Homepage (hero, booking options, services, about, contact)
/about                  — About Moontide + About Gabrielle + Qualifications
/classes/prenatal       — Prenatal Yoga detail page
/classes/postnatal      — Postnatal Yoga detail page
/classes/baby-yoga      — Baby Yoga & Massage detail page
/classes/vinyasa        — Vinyasa Yoga Seasonal Flow detail page
/coaching               — Transformational Coaching detail page
/community              — Creating Community + key dates
/private                — Private Classes detail page
/book                   — Class schedule browser + booking flow
/book/bundle            — Bundle purchase page
/terms                  — Terms & Conditions
/contact                — Contact form
```

### Admin Pages

```
/admin                  — Login
/admin/schedule         — Create/edit scheduled classes
/admin/bookings         — View bookings per class
/admin/bundles          — View active bundles
/admin/messages         — Contact form submissions
```

### Navigation (burger menu)

Home, About, Classes (Prenatal, Postnatal, Baby Yoga, Vinyasa), Coaching, Community, Private, Book a Class, Contact

### Homepage Sections (per spec)

1. **Hero** — full-width photography (moon/tide), Moontide title, definition, "Book a Class" + "Learn More" CTAs
2. **Booking options** — individual class (full moon icon) + six-class bundle (moon phases icon) + contact link
3. **Services grid** — each service: photography, title, description, "Book a Class" + "More info" CTAs. Services: Prenatal, Postnatal, Baby Yoga & Massage, Vinyasa, Coaching (CTA: "Contact Me"), Community (CTA: "More info"), Private Classes (CTA: "Contact Me")
4. **About Gabrielle** — photo, short text, "About me" link
5. **Contact form** — name, email, subject, message
6. **Footer** — links (Prenatal, Postnatal, Baby Massage, Private, T&Cs, Instagram)

### Service Detail Pages

Each class/service page: hero image, full description (from Sanity), upcoming schedule (from DB, where applicable), "Book a Class" or "Contact Me" CTA.

### Key UX Decisions

- "Book a Class" buttons on service pages link to `/book` filtered to that class type
- "Contact Me" buttons (coaching, private) link to `/contact` with subject pre-filled
- `/book` is the single entry point for all booking — browse schedule, select, pay or redeem bundle
- Class detail pages pull descriptions/images from Sanity, upcoming schedule from database

---

## Visual Design

### Theme Instruction

> Calm, luminous and gently energising — like light moving across water

### Design Principles

- **Clean and modern** — professional but warm, boutique studio feel
- **Light and inviting** — no dark backgrounds; Foam White and Driftwood alternate for section rhythm
- **Photography-led** — full-width photographic imagery throughout carries the mood
- **Mobile-first** — stacked layouts, full-width photo cards, thumb-friendly tap targets
- **Moon/tide/nature** identity woven into brand touches (palette, icons, subtle motifs) not heavy visual effects

### Colour Palette

| Name | Hex | Role |
|------|-----|------|
| Deep Current | #1e2a38 | Primary text, headings |
| Deep Ocean | #2c3e50 | Secondary text, body copy |
| Shallow Water | #a8c5d6 | Card backgrounds, hover states |
| Lunar Gold | #c8a96a | Accent — CTAs, highlights, dividers |
| Driftwood | #e8ddd3 | Warm neutral, alternating sections |
| Foam White | #f7f4ef | Primary page background |
| Seagrass | #6b8f71 | Success states, confirmation, nature accent (sparingly) |

### Typography

To be confirmed with logo — likely a clean sans-serif (Geist or similar per platform convention) with potential for a light/elegant display font for the Moontide wordmark.

### Photography Required

| Image | Usage |
|-------|-------|
| Moon/tide hero | Homepage hero section |
| Moontide about | About page header |
| Gabrielle portrait | About section, About page |
| Prenatal yoga | Service card + detail page |
| Postnatal yoga | Service card + detail page |
| Baby yoga/massage | Service card + detail page |
| Vinyasa yoga | Service card + detail page |
| Coaching | Service card + detail page |
| Community | Service card + detail page |
| Private classes | Service card + detail page |

### Logo

Pending — to be provided. Positioned top-left in navigation.

---

## Authentication & Admin

- **Better Auth** with email/password — single admin account seeded on first deploy
- Protected behind `/admin/*` routes using Next.js middleware
- No registration page — admin account created via seed script
- Session-based auth stored in Neon database
- Extensible to additional instructors if needed (just another DB row)

---

## Email (Resend)

### Launch

- Contact form submissions forwarded to gwaring5@googlemail.com
- Stripe handles payment confirmation emails natively

### Future

- Booking confirmation emails from the app
- Waitlist notifications
- Class reminders
- Content subscriptions / newsletter

Resend free tier (100 emails/day) covers launch scale comfortably.

---

## Terms & Conditions

As specified:

- **Bookings and cancellations:** All purchases non-refundable. Contact directly to cancel/reschedule. Class cancellations by instructor result in transferable credit, subject to availability.
- **Bundles:** Expire 90 days from purchase date.

---

## Implementation Phases

### Phase 1 — Foundation & Design

- New git repository + Next.js 16 project setup (platform-aligned stack)
- Product YAML registered in platform repo
- Brand assets integration — logo, colour palette finalisation, photography
- Sanity CMS schema and studio setup
- All public pages with CMS-driven content and photography
- Responsive layout (mobile-first), burger menu navigation, footer
- Contact form (DB storage + Resend email forwarding)
- Domain purchase and Vercel deployment
- CLAUDE.md for the project

**Dependencies:** Logo, finalised colour palette, photography

**Deliverable:** Live, fully designed website with all content pages, brand identity in place, contact form working. Gabrielle can edit content in Sanity.

### Phase 2 — Booking & Payments

- Stripe account setup and integration
- Database schema for classes, schedules, bookings, bundles
- Admin dashboard (Better Auth, class/schedule CRUD, booking/bundle views, message inbox)
- Public booking flow (browse schedule → select → Stripe Checkout → confirmation)
- Bundle purchase and redemption (email-based lookup)
- Capacity tracking and display

**Deliverable:** Gabrielle can create classes in admin, customers can book and pay.

### Phase 3 — Polish & Future Features

- Waitlist functionality
- Email reminders and booking confirmations (Resend)
- Recurring schedule generation
- SEO and performance optimisation
- Analytics integration
- Architecture diagrams (C4-PlantUML per platform standard)
- Content subscription / newsletter capability

**Deliverable:** Complete feature set, production-hardened.

---

## Platform Conformance

This project will follow platform standards:

- **Documentation:** CLAUDE.md maintained per standard
- **Testing:** Automated tests, framework TBC in Phase 1 plan
- **Secrets:** Doppler with dev/stg/prd configs
- **Environments:** Local Postgres (Docker), Neon staging branch, Neon production
- **Local development:** docker-compose.yml for Postgres, `doppler run` for secrets
- **Architecture diagrams:** C4-PlantUML in `docs/architecture/` (Phase 3)

Product YAML canonical values:
```yaml
choices:
  hosting: vercel-hobby
  database: neon
  auth: better-auth
  orm: drizzle
  ui: shadcn-tailwind
  secrets: doppler
```

No divergences from platform defaults.
