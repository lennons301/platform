# Moontide Phase 2: Booking & Payments — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable Gabrielle to create class schedules and accept bookings/payments — individual classes via Stripe Checkout, six-class bundles with email-based redemption, and an admin dashboard for managing everything.

**Architecture:** Extend the existing Next.js 16 app with new Drizzle tables (classes, schedules, bookings, bundles), Stripe Checkout for payments via webhooks, Better Auth for admin-only authentication, and server-rendered admin pages behind middleware protection.

**Tech Stack:** Stripe Checkout + webhooks, Better Auth (email/password), Drizzle ORM (existing), Neon Postgres (existing), Next.js 16 App Router (existing)

**Spec:** `docs/superpowers/specs/2026-04-09-moontide-design.md` — sections: Data Model, Booking Flows, Page Structure (Admin Pages), Authentication & Admin

**Phase 1 codebase:** `~/code/moontide` — Next.js 16, Tailwind v4, Sanity CMS, Drizzle with `contact_submissions` table, Vitest, Doppler secrets

**Human review gates:** Tasks involving UI/UX (public booking pages, admin dashboard) require human review before proceeding.

---

## File Structure

```
src/
├── app/
│   ├── admin/
│   │   ├── layout.tsx              # Admin layout (sidebar nav, auth check)
│   │   ├── page.tsx                # Admin dashboard home (redirect to schedule)
│   │   ├── login/
│   │   │   └── page.tsx            # Admin login page
│   │   ├── schedule/
│   │   │   └── page.tsx            # Class schedule management (CRUD)
│   │   ├── bookings/
│   │   │   └── page.tsx            # View bookings per class
│   │   ├── bundles/
│   │   │   └── page.tsx            # View active bundles
│   │   └── messages/
│   │       └── page.tsx            # Contact form submissions inbox
│   ├── api/
│   │   ├── auth/
│   │   │   └── [...all]/
│   │   │       └── route.ts        # Better Auth API handler
│   │   ├── stripe/
│   │   │   └── webhook/
│   │   │       └── route.ts        # Stripe webhook handler
│   │   ├── admin/
│   │   │   ├── schedules/
│   │   │   │   └── route.ts        # CRUD API for schedules
│   │   │   ├── bookings/
│   │   │   │   └── route.ts        # Bookings API (list, cancel)
│   │   │   └── bundles/
│   │   │       └── route.ts        # Bundles API (list)
│   │   ├── book/
│   │   │   ├── checkout/
│   │   │   │   └── route.ts        # Create Stripe Checkout session
│   │   │   └── redeem/
│   │   │       └── route.ts        # Redeem bundle credit
│   │   └── contact/
│   │       └── route.ts            # Existing contact form
│   ├── book/
│   │   ├── page.tsx                # Class schedule browser + booking flow
│   │   ├── bundle/
│   │   │   └── page.tsx            # Bundle purchase page
│   │   └── confirmation/
│   │       └── page.tsx            # Post-payment confirmation
│   └── ...existing pages
├── lib/
│   ├── auth.ts                     # Better Auth server config
│   ├── auth-client.ts              # Better Auth client config
│   ├── stripe.ts                   # Stripe client
│   ├── db/
│   │   ├── index.ts                # Existing Drizzle client
│   │   └── schema.ts               # Extended with new tables
│   └── ...existing
├── middleware.ts                    # Admin route protection
└── ...existing

tests/
├── api/
│   ├── contact.test.ts             # Existing
│   ├── stripe-webhook.test.ts      # Webhook handler tests
│   ├── book-checkout.test.ts       # Checkout session tests
│   └── book-redeem.test.ts         # Bundle redemption tests
├── lib/
│   ├── email.test.ts               # Existing
│   └── stripe.test.ts              # Stripe helper tests
└── admin/
    └── schedules.test.ts           # Admin schedule API tests
```

---

### Task 1: Install Dependencies

**Files:**
- Modify: `~/code/moontide/package.json`

- [ ] **Step 1: Install Stripe and Better Auth**

```bash
cd ~/code/moontide
npm install stripe better-auth
```

- [ ] **Step 2: Add Stripe env vars to Doppler**

```bash
# These will be set once Stripe account is created
# For now, add placeholders to .env.example
```

Add to `~/code/moontide/.env.example`:

```bash
# Stripe
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=
```

- [ ] **Step 3: Commit**

```bash
cd ~/code/moontide
git add .
git commit -m "feat: install Stripe and Better Auth dependencies"
```

---

### Task 2: Extend Database Schema

**Files:**
- Modify: `~/code/moontide/src/lib/db/schema.ts`

- [ ] **Step 1: Add new tables to schema**

Replace `src/lib/db/schema.ts` with the full schema including new tables:

```ts
import {
  pgTable,
  text,
  timestamp,
  boolean,
  serial,
  integer,
  date,
  time,
  pgEnum,
} from "drizzle-orm/pg-core";

// Enums
export const classCategory = pgEnum("class_category", [
  "class",
  "coaching",
  "community",
]);

export const bookingType = pgEnum("booking_type", ["stripe", "contact"]);

export const scheduleStatus = pgEnum("schedule_status", [
  "open",
  "full",
  "cancelled",
]);

export const bookingStatus = pgEnum("booking_status", [
  "confirmed",
  "cancelled",
  "waitlisted",
]);

export const bundleStatus = pgEnum("bundle_status", [
  "active",
  "expired",
  "exhausted",
]);

// Existing table
export const contactSubmissions = pgTable("contact_submissions", {
  id: serial("id").primaryKey(),
  name: text("name").notNull(),
  email: text("email").notNull(),
  subject: text("subject").notNull(),
  message: text("message").notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  read: boolean("read").default(false).notNull(),
});

// New tables
export const classes = pgTable("classes", {
  id: serial("id").primaryKey(),
  slug: text("slug").notNull().unique(),
  sanityId: text("sanity_id"),
  category: classCategory("category").notNull(),
  bookingType: bookingType("booking_type").notNull().default("stripe"),
  active: boolean("active").default(true).notNull(),
  priceInPence: integer("price_in_pence").notNull(),
  title: text("title").notNull(),
});

export const schedules = pgTable("schedules", {
  id: serial("id").primaryKey(),
  classId: integer("class_id")
    .references(() => classes.id)
    .notNull(),
  date: date("date").notNull(),
  startTime: time("start_time").notNull(),
  endTime: time("end_time").notNull(),
  capacity: integer("capacity").notNull().default(8),
  bookedCount: integer("booked_count").notNull().default(0),
  location: text("location"),
  recurringRule: text("recurring_rule"),
  status: scheduleStatus("status").notNull().default("open"),
});

export const bookings = pgTable("bookings", {
  id: serial("id").primaryKey(),
  scheduleId: integer("schedule_id")
    .references(() => schedules.id)
    .notNull(),
  customerName: text("customer_name").notNull(),
  customerEmail: text("customer_email").notNull(),
  stripePaymentId: text("stripe_payment_id"),
  bundleId: integer("bundle_id").references(() => bundles.id),
  status: bookingStatus("status").notNull().default("confirmed"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

export const bundles = pgTable("bundles", {
  id: serial("id").primaryKey(),
  customerEmail: text("customer_email").notNull(),
  creditsTotal: integer("credits_total").notNull().default(6),
  creditsRemaining: integer("credits_remaining").notNull().default(6),
  stripePaymentId: text("stripe_payment_id").notNull(),
  purchasedAt: timestamp("purchased_at").defaultNow().notNull(),
  expiresAt: timestamp("expires_at").notNull(),
  status: bundleStatus("status").notNull().default("active"),
});
```

**Note:** The `bookings.bundleId` references `bundles.id` — Drizzle handles forward references within the same file. If it causes issues, use a string reference instead.

- [ ] **Step 2: Generate migration**

```bash
cd ~/code/moontide
doppler run -- npx drizzle-kit generate
```

Expected: New migration file in `drizzle/migrations/` with CREATE TABLE statements for classes, schedules, bookings, bundles, and the enum types.

- [ ] **Step 3: Apply migration locally**

```bash
cd ~/code/moontide
docker compose up -d
doppler run -- npx drizzle-kit migrate
```

Expected: All tables created. Verify with:
```bash
docker exec -it $(docker ps -q -f name=postgres) psql -U postgres -d moontide_dev -c "\dt"
```

- [ ] **Step 4: Apply migration to Neon production**

```bash
cd ~/code/moontide
doppler run --config prd -- npx drizzle-kit migrate
```

- [ ] **Step 5: Commit**

```bash
cd ~/code/moontide
git add .
git commit -m "feat: add database schema for classes, schedules, bookings, and bundles"
```

---

### Task 3: Stripe Client & Webhook Handler

**Files:**
- Create: `~/code/moontide/src/lib/stripe.ts`
- Create: `~/code/moontide/src/app/api/stripe/webhook/route.ts`
- Create: `~/code/moontide/tests/api/stripe-webhook.test.ts`

- [ ] **Step 1: Create Stripe client**

Create `src/lib/stripe.ts`:

```ts
import Stripe from "stripe";

export const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);
```

- [ ] **Step 2: Write failing test for webhook handler**

Create `tests/api/stripe-webhook.test.ts`:

```ts
import { describe, it, expect, vi, beforeEach } from "vitest";

// Mock Stripe
vi.mock("@/lib/stripe", () => ({
  stripe: {
    webhooks: {
      constructEvent: vi.fn(),
    },
  },
}));

// Mock DB
vi.mock("@/lib/db", () => ({
  db: {
    insert: vi.fn().mockReturnValue({
      values: vi.fn().mockReturnValue({
        returning: vi.fn().mockResolvedValue([{ id: 1 }]),
      }),
    }),
    update: vi.fn().mockReturnValue({
      set: vi.fn().mockReturnValue({
        where: vi.fn().mockResolvedValue([]),
      }),
    }),
  },
}));

vi.mock("@/lib/db/schema", () => ({
  bookings: { id: "id", scheduleId: "schedule_id" },
  bundles: { id: "id" },
  schedules: { id: "id", bookedCount: "booked_count" },
}));

import { POST } from "@/app/api/stripe/webhook/route";
import { stripe } from "@/lib/stripe";

describe("POST /api/stripe/webhook", () => {
  it("returns 400 for invalid signature", async () => {
    vi.mocked(stripe.webhooks.constructEvent).mockImplementation(() => {
      throw new Error("Invalid signature");
    });

    const request = new Request("http://localhost:3000/api/stripe/webhook", {
      method: "POST",
      headers: { "stripe-signature": "invalid" },
      body: "{}",
    });

    const response = await POST(request);
    expect(response.status).toBe(400);
  });

  it("returns 200 for valid checkout.session.completed event", async () => {
    vi.mocked(stripe.webhooks.constructEvent).mockReturnValue({
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_test_123",
          metadata: {
            type: "individual",
            scheduleId: "1",
            customerName: "Jane Doe",
            customerEmail: "jane@example.com",
          },
        },
      },
    } as any);

    const request = new Request("http://localhost:3000/api/stripe/webhook", {
      method: "POST",
      headers: { "stripe-signature": "valid" },
      body: "{}",
    });

    const response = await POST(request);
    expect(response.status).toBe(200);
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd ~/code/moontide
npm test -- tests/api/stripe-webhook.test.ts
```

Expected: FAIL — `POST` not found.

- [ ] **Step 4: Implement webhook handler**

Create `src/app/api/stripe/webhook/route.ts`:

```ts
import { NextResponse } from "next/server";
import { stripe } from "@/lib/stripe";
import { db } from "@/lib/db";
import { bookings, bundles, schedules } from "@/lib/db/schema";
import { eq, sql } from "drizzle-orm";

export async function POST(request: Request) {
  const body = await request.text();
  const signature = request.headers.get("stripe-signature")!;

  let event;
  try {
    event = stripe.webhooks.constructEvent(
      body,
      signature,
      process.env.STRIPE_WEBHOOK_SECRET!
    );
  } catch {
    return NextResponse.json({ error: "Invalid signature" }, { status: 400 });
  }

  if (event.type === "checkout.session.completed") {
    const session = event.data.object;
    const metadata = session.metadata;

    if (metadata?.type === "individual") {
      // Individual class booking
      const scheduleId = parseInt(metadata.scheduleId);
      await db.insert(bookings).values({
        scheduleId,
        customerName: metadata.customerName,
        customerEmail: metadata.customerEmail,
        stripePaymentId: session.id,
      });
      await db
        .update(schedules)
        .set({ bookedCount: sql`${schedules.bookedCount} + 1` })
        .where(eq(schedules.id, scheduleId));
    } else if (metadata?.type === "bundle") {
      // Bundle purchase
      const expiresAt = new Date();
      expiresAt.setDate(expiresAt.getDate() + 90);
      await db.insert(bundles).values({
        customerEmail: metadata.customerEmail,
        stripePaymentId: session.id,
        expiresAt,
      });
    }
  }

  return NextResponse.json({ received: true });
}
```

- [ ] **Step 5: Run tests**

```bash
cd ~/code/moontide
npm test -- tests/api/stripe-webhook.test.ts
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
cd ~/code/moontide
git add .
git commit -m "feat: add Stripe client and webhook handler for bookings and bundles"
```

---

### Task 4: Checkout & Bundle Redemption APIs

**Files:**
- Create: `~/code/moontide/src/app/api/book/checkout/route.ts`
- Create: `~/code/moontide/src/app/api/book/redeem/route.ts`
- Create: `~/code/moontide/tests/api/book-checkout.test.ts`
- Create: `~/code/moontide/tests/api/book-redeem.test.ts`

- [ ] **Step 1: Write failing test for checkout API**

Create `tests/api/book-checkout.test.ts`:

```ts
import { describe, it, expect, vi } from "vitest";

vi.mock("@/lib/stripe", () => ({
  stripe: {
    checkout: {
      sessions: {
        create: vi.fn().mockResolvedValue({
          url: "https://checkout.stripe.com/test",
        }),
      },
    },
  },
}));

vi.mock("@/lib/db", () => ({
  db: {
    select: vi.fn().mockReturnValue({
      from: vi.fn().mockReturnValue({
        innerJoin: vi.fn().mockReturnValue({
          where: vi.fn().mockResolvedValue([
            {
              schedules: {
                id: 1,
                capacity: 8,
                bookedCount: 3,
                status: "open",
              },
              classes: {
                title: "Prenatal Yoga",
                priceInPence: 1500,
              },
            },
          ]),
        }),
      }),
    }),
  },
}));

vi.mock("@/lib/db/schema", () => ({
  schedules: { id: "id", classId: "class_id" },
  classes: { id: "id" },
}));

import { POST } from "@/app/api/book/checkout/route";

describe("POST /api/book/checkout", () => {
  it("returns checkout URL for valid booking", async () => {
    const request = new Request("http://localhost:3000/api/book/checkout", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        scheduleId: 1,
        customerName: "Jane Doe",
        customerEmail: "jane@example.com",
      }),
    });

    const response = await POST(request);
    const data = await response.json();
    expect(response.status).toBe(200);
    expect(data.url).toBe("https://checkout.stripe.com/test");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd ~/code/moontide
npm test -- tests/api/book-checkout.test.ts
```

Expected: FAIL

- [ ] **Step 3: Implement checkout API**

Create `src/app/api/book/checkout/route.ts`:

```ts
import { NextResponse } from "next/server";
import { stripe } from "@/lib/stripe";
import { db } from "@/lib/db";
import { schedules, classes } from "@/lib/db/schema";
import { eq } from "drizzle-orm";

export async function POST(request: Request) {
  const { scheduleId, customerName, customerEmail } = await request.json();

  if (!scheduleId || !customerName || !customerEmail) {
    return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
  }

  // Fetch schedule with class info
  const result = await db
    .select()
    .from(schedules)
    .innerJoin(classes, eq(schedules.classId, classes.id))
    .where(eq(schedules.id, scheduleId));

  if (result.length === 0) {
    return NextResponse.json({ error: "Schedule not found" }, { status: 404 });
  }

  const schedule = result[0].schedules;
  const classInfo = result[0].classes;

  if (schedule.status !== "open") {
    return NextResponse.json({ error: "Class is not available" }, { status: 400 });
  }

  if (schedule.bookedCount >= schedule.capacity) {
    return NextResponse.json({ error: "Class is full" }, { status: 400 });
  }

  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    line_items: [
      {
        price_data: {
          currency: "gbp",
          product_data: {
            name: classInfo.title,
            description: `${schedule.date} ${schedule.startTime}–${schedule.endTime}`,
          },
          unit_amount: classInfo.priceInPence,
        },
        quantity: 1,
      },
    ],
    metadata: {
      type: "individual",
      scheduleId: String(scheduleId),
      customerName,
      customerEmail,
    },
    customer_email: customerEmail,
    success_url: `${process.env.BETTER_AUTH_URL}/book/confirmation?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${process.env.BETTER_AUTH_URL}/book`,
  });

  return NextResponse.json({ url: session.url });
}
```

- [ ] **Step 4: Run checkout test**

```bash
cd ~/code/moontide
npm test -- tests/api/book-checkout.test.ts
```

Expected: PASS

- [ ] **Step 5: Write failing test for bundle redemption**

Create `tests/api/book-redeem.test.ts`:

```ts
import { describe, it, expect, vi } from "vitest";

vi.mock("@/lib/db", () => ({
  db: {
    select: vi.fn().mockReturnValue({
      from: vi.fn().mockReturnValue({
        where: vi.fn().mockResolvedValue([
          {
            id: 1,
            customerEmail: "jane@example.com",
            creditsRemaining: 4,
            status: "active",
            expiresAt: new Date(Date.now() + 86400000), // tomorrow
          },
        ]),
      }),
    }),
    insert: vi.fn().mockReturnValue({
      values: vi.fn().mockResolvedValue([]),
    }),
    update: vi.fn().mockReturnValue({
      set: vi.fn().mockReturnValue({
        where: vi.fn().mockResolvedValue([]),
      }),
    }),
  },
}));

vi.mock("@/lib/db/schema", () => ({
  bundles: { id: "id", customerEmail: "customer_email", status: "status" },
  bookings: { id: "id" },
  schedules: { id: "id", bookedCount: "booked_count" },
}));

import { POST } from "@/app/api/book/redeem/route";

describe("POST /api/book/redeem", () => {
  it("returns 200 for valid bundle redemption", async () => {
    const request = new Request("http://localhost:3000/api/book/redeem", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        scheduleId: 1,
        customerName: "Jane Doe",
        customerEmail: "jane@example.com",
      }),
    });

    const response = await POST(request);
    expect(response.status).toBe(200);
  });
});
```

- [ ] **Step 6: Implement bundle redemption API**

Create `src/app/api/book/redeem/route.ts`:

```ts
import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { bundles, bookings, schedules } from "@/lib/db/schema";
import { eq, and, gt, sql } from "drizzle-orm";

export async function POST(request: Request) {
  const { scheduleId, customerName, customerEmail } = await request.json();

  if (!scheduleId || !customerName || !customerEmail) {
    return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
  }

  // Find active bundle with credits remaining
  const activeBundles = await db
    .select()
    .from(bundles)
    .where(
      and(
        eq(bundles.customerEmail, customerEmail),
        eq(bundles.status, "active"),
        gt(bundles.creditsRemaining, 0),
        gt(bundles.expiresAt, new Date())
      )
    );

  if (activeBundles.length === 0) {
    return NextResponse.json({ error: "No active bundle found" }, { status: 404 });
  }

  const bundle = activeBundles[0];

  // Create booking
  await db.insert(bookings).values({
    scheduleId,
    customerName,
    customerEmail,
    bundleId: bundle.id,
  });

  // Decrement bundle credits
  const newCredits = bundle.creditsRemaining - 1;
  await db
    .update(bundles)
    .set({
      creditsRemaining: newCredits,
      status: newCredits === 0 ? "exhausted" : "active",
    })
    .where(eq(bundles.id, bundle.id));

  // Increment schedule booked count
  await db
    .update(schedules)
    .set({ bookedCount: sql`${schedules.bookedCount} + 1` })
    .where(eq(schedules.id, scheduleId));

  return NextResponse.json({ success: true, creditsRemaining: newCredits });
}
```

- [ ] **Step 7: Run all tests**

```bash
cd ~/code/moontide
npm test
```

Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
cd ~/code/moontide
git add .
git commit -m "feat: add checkout and bundle redemption APIs"
```

---

### Task 5: Bundle Purchase API

**Files:**
- Modify: `~/code/moontide/src/app/api/book/checkout/route.ts`

The bundle purchase also uses Stripe Checkout but with different metadata and a fixed bundle price. Rather than a separate endpoint, extend the existing checkout route to handle both types.

- [ ] **Step 1: Update checkout route to handle bundle purchases**

Modify `src/app/api/book/checkout/route.ts` — add bundle handling. The request will include `type: "bundle"` or `type: "individual"`:

```ts
import { NextResponse } from "next/server";
import { stripe } from "@/lib/stripe";
import { db } from "@/lib/db";
import { schedules, classes } from "@/lib/db/schema";
import { eq } from "drizzle-orm";

const BUNDLE_PRICE_PENCE = 7500; // £75 for 6 classes — Gabrielle to confirm
const BUNDLE_CREDITS = 6;

export async function POST(request: Request) {
  const body = await request.json();
  const { type, scheduleId, customerName, customerEmail } = body;

  if (!customerEmail) {
    return NextResponse.json({ error: "Email is required" }, { status: 400 });
  }

  if (type === "bundle") {
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      line_items: [
        {
          price_data: {
            currency: "gbp",
            product_data: {
              name: `${BUNDLE_CREDITS}-Class Bundle`,
              description: `${BUNDLE_CREDITS} classes, valid for 90 days from purchase`,
            },
            unit_amount: BUNDLE_PRICE_PENCE,
          },
          quantity: 1,
        },
      ],
      metadata: {
        type: "bundle",
        customerEmail,
      },
      customer_email: customerEmail,
      success_url: `${process.env.BETTER_AUTH_URL}/book/confirmation?session_id={CHECKOUT_SESSION_ID}&type=bundle`,
      cancel_url: `${process.env.BETTER_AUTH_URL}/book/bundle`,
    });

    return NextResponse.json({ url: session.url });
  }

  // Individual class booking
  if (!scheduleId || !customerName) {
    return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
  }

  const result = await db
    .select()
    .from(schedules)
    .innerJoin(classes, eq(schedules.classId, classes.id))
    .where(eq(schedules.id, scheduleId));

  if (result.length === 0) {
    return NextResponse.json({ error: "Schedule not found" }, { status: 404 });
  }

  const schedule = result[0].schedules;
  const classInfo = result[0].classes;

  if (schedule.status !== "open") {
    return NextResponse.json({ error: "Class is not available" }, { status: 400 });
  }

  if (schedule.bookedCount >= schedule.capacity) {
    return NextResponse.json({ error: "Class is full" }, { status: 400 });
  }

  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    line_items: [
      {
        price_data: {
          currency: "gbp",
          product_data: {
            name: classInfo.title,
            description: `${schedule.date} ${schedule.startTime}–${schedule.endTime}`,
          },
          unit_amount: classInfo.priceInPence,
        },
        quantity: 1,
      },
    ],
    metadata: {
      type: "individual",
      scheduleId: String(scheduleId),
      customerName,
      customerEmail,
    },
    customer_email: customerEmail,
    success_url: `${process.env.BETTER_AUTH_URL}/book/confirmation?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${process.env.BETTER_AUTH_URL}/book`,
  });

  return NextResponse.json({ url: session.url });
}
```

- [ ] **Step 2: Run all tests**

```bash
cd ~/code/moontide
npm test
```

Expected: All tests PASS

- [ ] **Step 3: Commit**

```bash
cd ~/code/moontide
git add .
git commit -m "feat: extend checkout API to handle bundle purchases"
```

---

### Task 6: Better Auth Setup

**Files:**
- Create: `~/code/moontide/src/lib/auth.ts`
- Create: `~/code/moontide/src/lib/auth-client.ts`
- Create: `~/code/moontide/src/app/api/auth/[...all]/route.ts`
- Create: `~/code/moontide/src/middleware.ts`
- Create: `~/code/moontide/scripts/seed-admin.ts`

- [ ] **Step 1: Create Better Auth server config**

Create `src/lib/auth.ts`:

```ts
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { db } from "@/lib/db";

export const auth = betterAuth({
  database: drizzleAdapter(db, { provider: "pg" }),
  emailAndPassword: {
    enabled: true,
  },
});
```

- [ ] **Step 2: Create Better Auth client config**

Create `src/lib/auth-client.ts`:

```ts
import { createAuthClient } from "better-auth/react";

export const authClient = createAuthClient({
  baseURL: process.env.NEXT_PUBLIC_BETTER_AUTH_URL || process.env.BETTER_AUTH_URL,
});
```

- [ ] **Step 3: Create auth API route**

Create `src/app/api/auth/[...all]/route.ts`:

```ts
import { auth } from "@/lib/auth";
import { toNextJsHandler } from "better-auth/next-js";

export const { GET, POST } = toNextJsHandler(auth);
```

- [ ] **Step 4: Generate Better Auth tables**

Better Auth needs its own tables (users, sessions, etc.). Run the CLI to generate them:

```bash
cd ~/code/moontide
doppler run -- npx @better-auth/cli generate --config src/lib/auth.ts --output src/lib/db/auth-schema.ts
```

Then merge the generated schema into the main schema file or import it. Check what Better Auth generates and integrate accordingly.

After integrating, generate and apply a new Drizzle migration:

```bash
cd ~/code/moontide
doppler run -- npx drizzle-kit generate
doppler run -- npx drizzle-kit migrate
```

- [ ] **Step 5: Create middleware for admin protection**

Create `src/middleware.ts`:

```ts
import { auth } from "@/lib/auth";
import { headers } from "next/headers";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export async function middleware(request: NextRequest) {
  // Only protect /admin routes (except /admin/login)
  if (
    request.nextUrl.pathname.startsWith("/admin") &&
    !request.nextUrl.pathname.startsWith("/admin/login")
  ) {
    const session = await auth.api.getSession({
      headers: await headers(),
    });

    if (!session) {
      return NextResponse.redirect(new URL("/admin/login", request.url));
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/admin/:path*"],
};
```

- [ ] **Step 6: Create admin seed script**

Create `scripts/seed-admin.ts`:

```ts
import { auth } from "../src/lib/auth";

async function seedAdmin() {
  console.log("Creating admin user...");

  await auth.api.signUpEmail({
    body: {
      email: "gwaring5@googlemail.com",
      password: process.env.ADMIN_PASSWORD || "changeme123",
      name: "Gabrielle",
    },
  });

  console.log("✓ Admin user created: gwaring5@googlemail.com");
}

seedAdmin().catch(console.error);
```

Add to package.json scripts:
```json
"db:seed-admin": "tsx scripts/seed-admin.ts"
```

- [ ] **Step 7: Run admin seed**

```bash
cd ~/code/moontide
doppler run -- npx tsx scripts/seed-admin.ts
```

- [ ] **Step 8: Commit**

```bash
cd ~/code/moontide
git add .
git commit -m "feat: add Better Auth with admin-only email/password authentication"
```

---

### Task 7: Admin Layout & Login Page 🔍 HUMAN REVIEW

**Files:**
- Create: `~/code/moontide/src/app/admin/layout.tsx`
- Create: `~/code/moontide/src/app/admin/page.tsx`
- Create: `~/code/moontide/src/app/admin/login/page.tsx`

- [ ] **Step 1: Create admin login page**

Create `src/app/admin/login/page.tsx`:

```tsx
"use client";

import { useState } from "react";
import { authClient } from "@/lib/auth-client";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export default function AdminLoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const router = useRouter();

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");

    const result = await authClient.signIn.email({ email, password });

    if (result.error) {
      setError("Invalid email or password");
      setLoading(false);
    } else {
      router.push("/admin/schedule");
    }
  }

  return (
    <div className="min-h-screen bg-foam-white flex items-center justify-center px-6">
      <div className="w-full max-w-sm">
        <h1 className="text-2xl font-semibold text-deep-current text-center mb-1">
          Moontide Admin
        </h1>
        <div className="w-8 h-0.5 bg-lunar-gold mx-auto mb-8" />
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className="mt-1"
            />
          </div>
          <div>
            <Label htmlFor="password">Password</Label>
            <Input
              id="password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              className="mt-1"
            />
          </div>
          {error && <p className="text-red-600 text-sm">{error}</p>}
          <Button
            type="submit"
            disabled={loading}
            className="w-full bg-lunar-gold text-deep-current hover:bg-lunar-gold/90 font-semibold"
          >
            {loading ? "Signing in..." : "Sign In"}
          </Button>
        </form>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Create admin layout**

Create `src/app/admin/layout.tsx`:

```tsx
import Link from "next/link";

const adminLinks = [
  { label: "Schedule", href: "/admin/schedule" },
  { label: "Bookings", href: "/admin/bookings" },
  { label: "Bundles", href: "/admin/bundles" },
  { label: "Messages", href: "/admin/messages" },
];

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-foam-white">
      <nav className="bg-deep-current text-foam-white px-6 py-3">
        <div className="flex items-center justify-between">
          <Link href="/admin" className="font-semibold tracking-wider text-sm">
            MOONTIDE ADMIN
          </Link>
          <div className="flex gap-4 text-sm">
            {adminLinks.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                className="hover:text-lunar-gold transition-colors"
              >
                {link.label}
              </Link>
            ))}
          </div>
        </div>
      </nav>
      <div className="p-6">{children}</div>
    </div>
  );
}
```

- [ ] **Step 3: Create admin home redirect**

Create `src/app/admin/page.tsx`:

```tsx
import { redirect } from "next/navigation";

export default function AdminPage() {
  redirect("/admin/schedule");
}
```

- [ ] **Step 4: Verify admin login flow**

```bash
cd ~/code/moontide
doppler run -- npm run dev
```

Navigate to `http://localhost:3000/admin`. Expected: redirected to `/admin/login`. Login with the seeded admin credentials. Expected: redirected to `/admin/schedule` (which will be empty for now).

- [ ] **Step 5: Commit**

```bash
cd ~/code/moontide
git add .
git commit -m "feat: add admin layout, login page, and route protection"
```

---

### Task 8: Admin Schedule Management 🔍 HUMAN REVIEW

**Files:**
- Create: `~/code/moontide/src/app/api/admin/schedules/route.ts`
- Create: `~/code/moontide/src/app/admin/schedule/page.tsx`
- Create: `~/code/moontide/tests/admin/schedules.test.ts`

- [ ] **Step 1: Write failing test for schedule API**

Create `tests/admin/schedules.test.ts`:

```ts
import { describe, it, expect, vi } from "vitest";

vi.mock("@/lib/db", () => ({
  db: {
    select: vi.fn().mockReturnValue({
      from: vi.fn().mockReturnValue({
        innerJoin: vi.fn().mockReturnValue({
          orderBy: vi.fn().mockResolvedValue([]),
        }),
      }),
    }),
    insert: vi.fn().mockReturnValue({
      values: vi.fn().mockReturnValue({
        returning: vi.fn().mockResolvedValue([{ id: 1 }]),
      }),
    }),
  },
}));

vi.mock("@/lib/db/schema", () => ({
  schedules: { id: "id", classId: "class_id", date: "date" },
  classes: { id: "id" },
}));

import { GET, POST } from "@/app/api/admin/schedules/route";

describe("Admin Schedules API", () => {
  it("GET returns schedule list", async () => {
    const request = new Request("http://localhost:3000/api/admin/schedules");
    const response = await GET(request);
    expect(response.status).toBe(200);
  });

  it("POST creates a new schedule", async () => {
    const request = new Request("http://localhost:3000/api/admin/schedules", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        classId: 1,
        date: "2026-05-01",
        startTime: "10:00",
        endTime: "11:00",
        capacity: 8,
        location: "Studio A",
      }),
    });

    const response = await POST(request);
    expect(response.status).toBe(201);
  });
});
```

- [ ] **Step 2: Implement schedule API**

Create `src/app/api/admin/schedules/route.ts`:

```ts
import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { schedules, classes } from "@/lib/db/schema";
import { eq, desc } from "drizzle-orm";

export async function GET() {
  const result = await db
    .select()
    .from(schedules)
    .innerJoin(classes, eq(schedules.classId, classes.id))
    .orderBy(desc(schedules.date));

  return NextResponse.json(result);
}

export async function POST(request: Request) {
  const body = await request.json();
  const { classId, date, startTime, endTime, capacity, location } = body;

  if (!classId || !date || !startTime || !endTime) {
    return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
  }

  const result = await db
    .insert(schedules)
    .values({
      classId,
      date,
      startTime,
      endTime,
      capacity: capacity || 8,
      location,
    })
    .returning();

  return NextResponse.json(result[0], { status: 201 });
}
```

- [ ] **Step 3: Create admin schedule page**

Create `src/app/admin/schedule/page.tsx`:

This is a client-side page that fetches schedules and provides a form to create new ones. It should:
- List all scheduled classes with date, time, class name, capacity, booked count, status
- Provide a form to create a new scheduled class (select class type, date, time, capacity, location)
- Allow cancelling a schedule

```tsx
"use client";

import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

interface Schedule {
  schedules: {
    id: number;
    date: string;
    startTime: string;
    endTime: string;
    capacity: number;
    bookedCount: number;
    location: string | null;
    status: string;
  };
  classes: {
    id: number;
    title: string;
    slug: string;
  };
}

interface ClassType {
  id: number;
  title: string;
  slug: string;
}

export default function AdminSchedulePage() {
  const [scheduleList, setScheduleList] = useState<Schedule[]>([]);
  const [classTypes, setClassTypes] = useState<ClassType[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);

  // Form state
  const [classId, setClassId] = useState("");
  const [date, setDate] = useState("");
  const [startTime, setStartTime] = useState("");
  const [endTime, setEndTime] = useState("");
  const [capacity, setCapacity] = useState("8");
  const [location, setLocation] = useState("");

  useEffect(() => {
    fetchData();
  }, []);

  async function fetchData() {
    const [schedRes, classRes] = await Promise.all([
      fetch("/api/admin/schedules"),
      fetch("/api/admin/classes"),
    ]);
    setScheduleList(await schedRes.json());
    setClassTypes(await classRes.json());
    setLoading(false);
  }

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    await fetch("/api/admin/schedules", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        classId: parseInt(classId),
        date,
        startTime,
        endTime,
        capacity: parseInt(capacity),
        location: location || null,
      }),
    });
    setShowForm(false);
    setClassId("");
    setDate("");
    setStartTime("");
    setEndTime("");
    setCapacity("8");
    setLocation("");
    fetchData();
  }

  if (loading) return <p className="text-deep-ocean">Loading...</p>;

  return (
    <div className="max-w-4xl mx-auto">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-semibold text-deep-current">Schedule</h1>
        <Button
          onClick={() => setShowForm(!showForm)}
          className="bg-lunar-gold text-deep-current hover:bg-lunar-gold/90 font-semibold"
        >
          {showForm ? "Cancel" : "New Class"}
        </Button>
      </div>

      {showForm && (
        <form onSubmit={handleCreate} className="bg-driftwood/50 rounded-lg p-6 mb-6 space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label htmlFor="classId">Class Type</Label>
              <select
                id="classId"
                value={classId}
                onChange={(e) => setClassId(e.target.value)}
                required
                className="mt-1 w-full rounded-md border border-driftwood bg-white px-3 py-2 text-sm"
              >
                <option value="">Select class...</option>
                {classTypes.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.title}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <Label htmlFor="date">Date</Label>
              <Input
                id="date"
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
                required
                className="mt-1"
              />
            </div>
            <div>
              <Label htmlFor="startTime">Start Time</Label>
              <Input
                id="startTime"
                type="time"
                value={startTime}
                onChange={(e) => setStartTime(e.target.value)}
                required
                className="mt-1"
              />
            </div>
            <div>
              <Label htmlFor="endTime">End Time</Label>
              <Input
                id="endTime"
                type="time"
                value={endTime}
                onChange={(e) => setEndTime(e.target.value)}
                required
                className="mt-1"
              />
            </div>
            <div>
              <Label htmlFor="capacity">Capacity</Label>
              <Input
                id="capacity"
                type="number"
                value={capacity}
                onChange={(e) => setCapacity(e.target.value)}
                required
                className="mt-1"
              />
            </div>
            <div>
              <Label htmlFor="location">Location</Label>
              <Input
                id="location"
                type="text"
                value={location}
                onChange={(e) => setLocation(e.target.value)}
                placeholder="Optional"
                className="mt-1"
              />
            </div>
          </div>
          <Button type="submit" className="bg-lunar-gold text-deep-current hover:bg-lunar-gold/90 font-semibold">
            Create Schedule
          </Button>
        </form>
      )}

      {scheduleList.length === 0 ? (
        <p className="text-deep-ocean">No classes scheduled yet. Click "New Class" to create one.</p>
      ) : (
        <div className="space-y-3">
          {scheduleList.map((item) => (
            <div
              key={item.schedules.id}
              className="flex items-center justify-between bg-white rounded-lg border border-driftwood p-4"
            >
              <div>
                <p className="font-semibold text-deep-current">{item.classes.title}</p>
                <p className="text-sm text-deep-ocean">
                  {item.schedules.date} · {item.schedules.startTime}–{item.schedules.endTime}
                  {item.schedules.location && ` · ${item.schedules.location}`}
                </p>
              </div>
              <div className="text-right">
                <p className="text-sm font-semibold text-deep-current">
                  {item.schedules.bookedCount}/{item.schedules.capacity}
                </p>
                <p className="text-xs text-deep-ocean">{item.schedules.status}</p>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Create admin classes API**

The schedule page needs to fetch class types. Create `src/app/api/admin/classes/route.ts`:

```ts
import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { classes } from "@/lib/db/schema";
import { eq } from "drizzle-orm";

export async function GET() {
  const result = await db.select().from(classes).where(eq(classes.active, true));
  return NextResponse.json(result);
}
```

- [ ] **Step 5: Create seed script for class types**

The `classes` table needs initial data matching the Sanity services. Create `scripts/seed-classes.ts`:

```ts
import { drizzle } from "drizzle-orm/postgres-js";
import postgres from "postgres";
import { classes } from "../src/lib/db/schema";

const client = postgres(process.env.DATABASE_URL!);
const db = drizzle(client);

async function seed() {
  console.log("Seeding class types...");

  const classTypes = [
    { slug: "prenatal", title: "Prenatal Yoga", category: "class" as const, bookingType: "stripe" as const, priceInPence: 1500 },
    { slug: "postnatal", title: "Postnatal Yoga", category: "class" as const, bookingType: "stripe" as const, priceInPence: 1500 },
    { slug: "baby-yoga", title: "Baby Yoga & Massage", category: "class" as const, bookingType: "stripe" as const, priceInPence: 1500 },
    { slug: "vinyasa", title: "Vinyasa Yoga Seasonal Flow", category: "class" as const, bookingType: "stripe" as const, priceInPence: 1500 },
  ];

  for (const ct of classTypes) {
    await db.insert(classes).values(ct).onConflictDoNothing();
    console.log(`  ✓ ${ct.title} (£${(ct.priceInPence / 100).toFixed(2)})`);
  }

  console.log("\n✓ Class types seeded");
  process.exit(0);
}

seed().catch(console.error);
```

Add to package.json scripts:
```json
"db:seed-classes": "tsx scripts/seed-classes.ts"
```

Run it:
```bash
cd ~/code/moontide
doppler run -- npx tsx scripts/seed-classes.ts
```

**Note:** Class prices are placeholder (£15 each). Gabrielle to confirm actual prices.

- [ ] **Step 6: Run tests and verify**

```bash
cd ~/code/moontide
npm test
```

- [ ] **Step 7: Commit**

```bash
cd ~/code/moontide
git add .
git commit -m "feat: add admin schedule management with class types and CRUD API"
```

---

### Task 9: Admin Bookings, Bundles & Messages Pages

**Files:**
- Create: `~/code/moontide/src/app/api/admin/bookings/route.ts`
- Create: `~/code/moontide/src/app/api/admin/bundles/route.ts`
- Create: `~/code/moontide/src/app/admin/bookings/page.tsx`
- Create: `~/code/moontide/src/app/admin/bundles/page.tsx`
- Create: `~/code/moontide/src/app/admin/messages/page.tsx`

- [ ] **Step 1: Create bookings API**

Create `src/app/api/admin/bookings/route.ts`:

```ts
import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { bookings, schedules, classes } from "@/lib/db/schema";
import { eq, desc } from "drizzle-orm";

export async function GET() {
  const result = await db
    .select()
    .from(bookings)
    .innerJoin(schedules, eq(bookings.scheduleId, schedules.id))
    .innerJoin(classes, eq(schedules.classId, classes.id))
    .orderBy(desc(bookings.createdAt));

  return NextResponse.json(result);
}
```

- [ ] **Step 2: Create bundles API**

Create `src/app/api/admin/bundles/route.ts`:

```ts
import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { bundles } from "@/lib/db/schema";
import { desc } from "drizzle-orm";

export async function GET() {
  const result = await db
    .select()
    .from(bundles)
    .orderBy(desc(bundles.purchasedAt));

  return NextResponse.json(result);
}
```

- [ ] **Step 3: Create admin bookings page**

Create `src/app/admin/bookings/page.tsx`:

```tsx
"use client";

import { useState, useEffect } from "react";

interface BookingRow {
  bookings: {
    id: number;
    customerName: string;
    customerEmail: string;
    status: string;
    createdAt: string;
    stripePaymentId: string | null;
    bundleId: number | null;
  };
  schedules: {
    date: string;
    startTime: string;
  };
  classes: {
    title: string;
  };
}

export default function AdminBookingsPage() {
  const [bookingList, setBookingList] = useState<BookingRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/admin/bookings")
      .then((r) => r.json())
      .then((data) => {
        setBookingList(data);
        setLoading(false);
      });
  }, []);

  if (loading) return <p className="text-deep-ocean">Loading...</p>;

  return (
    <div className="max-w-4xl mx-auto">
      <h1 className="text-2xl font-semibold text-deep-current mb-6">Bookings</h1>
      {bookingList.length === 0 ? (
        <p className="text-deep-ocean">No bookings yet.</p>
      ) : (
        <div className="space-y-3">
          {bookingList.map((item) => (
            <div
              key={item.bookings.id}
              className="flex items-center justify-between bg-white rounded-lg border border-driftwood p-4"
            >
              <div>
                <p className="font-semibold text-deep-current">
                  {item.bookings.customerName}
                </p>
                <p className="text-sm text-deep-ocean">
                  {item.bookings.customerEmail}
                </p>
                <p className="text-xs text-deep-ocean mt-1">
                  {item.classes.title} · {item.schedules.date} {item.schedules.startTime}
                </p>
              </div>
              <div className="text-right">
                <span
                  className={`text-xs font-semibold px-2 py-1 rounded ${
                    item.bookings.status === "confirmed"
                      ? "bg-seagrass/20 text-seagrass"
                      : item.bookings.status === "cancelled"
                        ? "bg-red-100 text-red-600"
                        : "bg-shallow-water/20 text-deep-ocean"
                  }`}
                >
                  {item.bookings.status}
                </span>
                <p className="text-xs text-deep-ocean mt-1">
                  {item.bookings.bundleId ? "Bundle" : "Stripe"}
                </p>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Create admin bundles page**

Create `src/app/admin/bundles/page.tsx`:

```tsx
"use client";

import { useState, useEffect } from "react";

interface BundleRow {
  id: number;
  customerEmail: string;
  creditsTotal: number;
  creditsRemaining: number;
  status: string;
  purchasedAt: string;
  expiresAt: string;
}

export default function AdminBundlesPage() {
  const [bundleList, setBundleList] = useState<BundleRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/admin/bundles")
      .then((r) => r.json())
      .then((data) => {
        setBundleList(data);
        setLoading(false);
      });
  }, []);

  if (loading) return <p className="text-deep-ocean">Loading...</p>;

  return (
    <div className="max-w-4xl mx-auto">
      <h1 className="text-2xl font-semibold text-deep-current mb-6">Bundles</h1>
      {bundleList.length === 0 ? (
        <p className="text-deep-ocean">No bundles purchased yet.</p>
      ) : (
        <div className="space-y-3">
          {bundleList.map((bundle) => (
            <div
              key={bundle.id}
              className="flex items-center justify-between bg-white rounded-lg border border-driftwood p-4"
            >
              <div>
                <p className="font-semibold text-deep-current">{bundle.customerEmail}</p>
                <p className="text-sm text-deep-ocean">
                  Purchased: {new Date(bundle.purchasedAt).toLocaleDateString("en-GB")}
                  {" · "}Expires: {new Date(bundle.expiresAt).toLocaleDateString("en-GB")}
                </p>
              </div>
              <div className="text-right">
                <p className="text-lg font-semibold text-deep-current">
                  {bundle.creditsRemaining}/{bundle.creditsTotal}
                </p>
                <span
                  className={`text-xs font-semibold px-2 py-1 rounded ${
                    bundle.status === "active"
                      ? "bg-seagrass/20 text-seagrass"
                      : bundle.status === "expired"
                        ? "bg-red-100 text-red-600"
                        : "bg-shallow-water/20 text-deep-ocean"
                  }`}
                >
                  {bundle.status}
                </span>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 5: Create admin messages page**

Create `src/app/admin/messages/page.tsx`:

```tsx
"use client";

import { useState, useEffect } from "react";

interface Message {
  id: number;
  name: string;
  email: string;
  subject: string;
  message: string;
  createdAt: string;
  read: boolean;
}

export default function AdminMessagesPage() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Message | null>(null);

  useEffect(() => {
    fetch("/api/admin/messages")
      .then((r) => r.json())
      .then((data) => {
        setMessages(data);
        setLoading(false);
      });
  }, []);

  if (loading) return <p className="text-deep-ocean">Loading...</p>;

  return (
    <div className="max-w-4xl mx-auto">
      <h1 className="text-2xl font-semibold text-deep-current mb-6">Messages</h1>

      {selected ? (
        <div className="bg-white rounded-lg border border-driftwood p-6">
          <button
            onClick={() => setSelected(null)}
            className="text-sm text-lunar-gold mb-4 hover:text-lunar-gold/80"
          >
            &larr; Back to messages
          </button>
          <div className="mb-4">
            <p className="font-semibold text-deep-current text-lg">{selected.subject}</p>
            <p className="text-sm text-deep-ocean">
              From: {selected.name} ({selected.email})
            </p>
            <p className="text-xs text-deep-ocean">
              {new Date(selected.createdAt).toLocaleString("en-GB")}
            </p>
          </div>
          <p className="text-deep-ocean leading-relaxed whitespace-pre-wrap">
            {selected.message}
          </p>
        </div>
      ) : messages.length === 0 ? (
        <p className="text-deep-ocean">No messages yet.</p>
      ) : (
        <div className="space-y-2">
          {messages.map((msg) => (
            <button
              key={msg.id}
              onClick={() => setSelected(msg)}
              className={`w-full text-left flex items-center justify-between rounded-lg border p-4 transition-colors ${
                msg.read
                  ? "bg-white border-driftwood"
                  : "bg-lunar-gold/5 border-lunar-gold/30"
              }`}
            >
              <div>
                <p className={`text-sm ${msg.read ? "text-deep-ocean" : "font-semibold text-deep-current"}`}>
                  {msg.subject}
                </p>
                <p className="text-xs text-deep-ocean">{msg.name} · {msg.email}</p>
              </div>
              <span className="text-xs text-deep-ocean">
                {new Date(msg.createdAt).toLocaleDateString("en-GB")}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 6: Create messages API**

Create `src/app/api/admin/messages/route.ts`:

```ts
import { NextResponse } from "next/server";
import { db } from "@/lib/db";
import { contactSubmissions } from "@/lib/db/schema";
import { desc } from "drizzle-orm";

export async function GET() {
  const result = await db
    .select()
    .from(contactSubmissions)
    .orderBy(desc(contactSubmissions.createdAt));

  return NextResponse.json(result);
}
```

- [ ] **Step 7: Run tests and verify**

```bash
cd ~/code/moontide
npm test
```

- [ ] **Step 8: Commit**

```bash
cd ~/code/moontide
git add .
git commit -m "feat: add admin pages for bookings, bundles, and messages"
```

---

### Task 10: Public Booking Pages 🔍 HUMAN REVIEW

**Files:**
- Modify: `~/code/moontide/src/app/book/page.tsx`
- Modify: `~/code/moontide/src/app/book/bundle/page.tsx`
- Create: `~/code/moontide/src/app/book/confirmation/page.tsx`

- [ ] **Step 1: Build the booking page**

Replace `src/app/book/page.tsx` — this page shows upcoming classes with availability, and lets customers book (either via Stripe or bundle redemption):

```tsx
import { db } from "@/lib/db";
import { schedules, classes } from "@/lib/db/schema";
import { eq, gte, and } from "drizzle-orm";
import { BookingClient } from "./booking-client";

export const dynamic = "force-dynamic";

export const metadata = { title: "Book a Class — Moontide" };

export default async function BookPage() {
  const today = new Date().toISOString().split("T")[0];

  const upcoming = await db
    .select()
    .from(schedules)
    .innerJoin(classes, eq(schedules.classId, classes.id))
    .where(and(gte(schedules.date, today), eq(schedules.status, "open")));

  return (
    <div className="max-w-3xl mx-auto px-6 py-16">
      <h1 className="text-3xl font-light tracking-wide text-deep-current text-center mb-1">
        Book a Class
      </h1>
      <div className="w-8 h-0.5 bg-lunar-gold mx-auto mb-8" />
      <BookingClient schedules={upcoming} />
    </div>
  );
}
```

- [ ] **Step 2: Create booking client component**

Create `src/app/book/booking-client.tsx`:

```tsx
"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

interface ScheduleWithClass {
  schedules: {
    id: number;
    date: string;
    startTime: string;
    endTime: string;
    capacity: number;
    bookedCount: number;
    location: string | null;
  };
  classes: {
    title: string;
    priceInPence: number;
  };
}

export function BookingClient({ schedules }: { schedules: ScheduleWithClass[] }) {
  const [selected, setSelected] = useState<ScheduleWithClass | null>(null);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);
  const [bundleCheck, setBundleCheck] = useState(false);

  async function handleBook() {
    if (!selected || !name || !email) return;
    setLoading(true);

    // First try bundle redemption
    if (bundleCheck) {
      const redeemRes = await fetch("/api/book/redeem", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          scheduleId: selected.schedules.id,
          customerName: name,
          customerEmail: email,
        }),
      });

      if (redeemRes.ok) {
        window.location.href = "/book/confirmation?type=bundle";
        return;
      }
      // Bundle not found — fall through to Stripe
    }

    // Stripe checkout
    const res = await fetch("/api/book/checkout", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        type: "individual",
        scheduleId: selected.schedules.id,
        customerName: name,
        customerEmail: email,
      }),
    });

    const data = await res.json();
    if (data.url) {
      window.location.href = data.url;
    }
    setLoading(false);
  }

  if (schedules.length === 0) {
    return (
      <p className="text-deep-ocean text-center">
        No classes currently scheduled. Check back soon or{" "}
        <a href="/contact" className="text-lunar-gold underline">
          get in touch
        </a>{" "}
        for updates.
      </p>
    );
  }

  return (
    <div>
      {!selected ? (
        <div className="space-y-3">
          {schedules.map((item) => {
            const spotsLeft = item.schedules.capacity - item.schedules.bookedCount;
            return (
              <button
                key={item.schedules.id}
                onClick={() => setSelected(item)}
                className="w-full text-left flex items-center justify-between bg-white rounded-lg border border-driftwood p-4 hover:border-lunar-gold transition-colors"
              >
                <div>
                  <p className="font-semibold text-deep-current">{item.classes.title}</p>
                  <p className="text-sm text-deep-ocean">
                    {new Date(item.schedules.date).toLocaleDateString("en-GB", {
                      weekday: "long",
                      day: "numeric",
                      month: "long",
                    })}
                    {" · "}
                    {item.schedules.startTime}–{item.schedules.endTime}
                    {item.schedules.location && ` · ${item.schedules.location}`}
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-sm font-semibold text-deep-current">
                    £{(item.classes.priceInPence / 100).toFixed(2)}
                  </p>
                  <p className={`text-xs ${spotsLeft <= 2 ? "text-red-600" : "text-deep-ocean"}`}>
                    {spotsLeft} {spotsLeft === 1 ? "spot" : "spots"} left
                  </p>
                </div>
              </button>
            );
          })}
        </div>
      ) : (
        <div className="bg-white rounded-lg border border-driftwood p-6">
          <button
            onClick={() => setSelected(null)}
            className="text-sm text-lunar-gold mb-4 hover:text-lunar-gold/80"
          >
            &larr; Back to classes
          </button>
          <h2 className="text-lg font-semibold text-deep-current mb-1">
            {selected.classes.title}
          </h2>
          <p className="text-sm text-deep-ocean mb-6">
            {new Date(selected.schedules.date).toLocaleDateString("en-GB", {
              weekday: "long",
              day: "numeric",
              month: "long",
            })}
            {" · "}
            {selected.schedules.startTime}–{selected.schedules.endTime}
            {" · "}£{(selected.classes.priceInPence / 100).toFixed(2)}
          </p>

          <div className="space-y-4">
            <div>
              <Label htmlFor="name">Your name</Label>
              <Input
                id="name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                required
                className="mt-1"
              />
            </div>
            <div>
              <Label htmlFor="email">Email address</Label>
              <Input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                className="mt-1"
              />
            </div>
            <label className="flex items-center gap-2 text-sm text-deep-ocean">
              <input
                type="checkbox"
                checked={bundleCheck}
                onChange={(e) => setBundleCheck(e.target.checked)}
                className="rounded border-driftwood"
              />
              I have a class bundle
            </label>
            <Button
              onClick={handleBook}
              disabled={loading || !name || !email}
              className="w-full bg-lunar-gold text-deep-current hover:bg-lunar-gold/90 font-semibold"
            >
              {loading ? "Processing..." : bundleCheck ? "Use Bundle Credit" : "Pay & Book"}
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 3: Build the bundle purchase page**

Replace `src/app/book/bundle/page.tsx`:

```tsx
"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export default function BundlePage() {
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);

  async function handlePurchase() {
    if (!email) return;
    setLoading(true);

    const res = await fetch("/api/book/checkout", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ type: "bundle", customerEmail: email }),
    });

    const data = await res.json();
    if (data.url) {
      window.location.href = data.url;
    }
    setLoading(false);
  }

  return (
    <div className="max-w-lg mx-auto px-6 py-16">
      <h1 className="text-3xl font-light tracking-wide text-deep-current text-center mb-1">
        Six Class Bundle
      </h1>
      <div className="w-8 h-0.5 bg-lunar-gold mx-auto mb-8" />

      <div className="bg-white rounded-lg border border-driftwood p-6 text-center mb-8">
        <p className="text-3xl font-semibold text-deep-current mb-2">£75</p>
        <p className="text-deep-ocean">6 classes · Valid for 90 days</p>
      </div>

      <div className="space-y-4">
        <div>
          <Label htmlFor="email">Email address</Label>
          <Input
            id="email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            placeholder="Your email for bundle tracking"
            className="mt-1"
          />
        </div>
        <Button
          onClick={handlePurchase}
          disabled={loading || !email}
          className="w-full bg-lunar-gold text-deep-current hover:bg-lunar-gold/90 font-semibold"
        >
          {loading ? "Processing..." : "Purchase Bundle"}
        </Button>
      </div>

      <p className="text-sm text-deep-ocean text-center mt-6">
        Your bundle will be linked to your email address. Use the same email when booking classes to redeem credits.
      </p>
    </div>
  );
}
```

- [ ] **Step 4: Create confirmation page**

Create `src/app/book/confirmation/page.tsx`:

```tsx
import Link from "next/link";

export const metadata = { title: "Booking Confirmed — Moontide" };

export default async function ConfirmationPage({
  searchParams,
}: {
  searchParams: Promise<{ type?: string }>;
}) {
  const { type } = await searchParams;
  const isBundle = type === "bundle";

  return (
    <div className="max-w-lg mx-auto px-6 py-16 text-center">
      <div className="w-12 h-12 rounded-full bg-seagrass/20 flex items-center justify-center mx-auto mb-4">
        <span className="text-seagrass text-xl">✓</span>
      </div>
      <h1 className="text-2xl font-semibold text-deep-current mb-2">
        {isBundle ? "Bundle Purchased!" : "Booking Confirmed!"}
      </h1>
      <p className="text-deep-ocean mb-8">
        {isBundle
          ? "Your 6-class bundle is now active. Use the same email address when booking to redeem your credits."
          : "You're all booked in. A payment confirmation has been sent to your email."}
      </p>
      <div className="flex gap-3 justify-center">
        <Link
          href="/book"
          className="bg-lunar-gold text-deep-current px-6 py-3 rounded-md font-semibold text-sm hover:bg-lunar-gold/90 transition-colors"
        >
          {isBundle ? "Book a Class" : "Book Another"}
        </Link>
        <Link
          href="/"
          className="border border-deep-current text-deep-current px-6 py-3 rounded-md text-sm hover:bg-deep-current hover:text-foam-white transition-colors"
        >
          Home
        </Link>
      </div>
    </div>
  );
}
```

- [ ] **Step 5: Verify booking flow end-to-end**

```bash
cd ~/code/moontide
doppler run -- npm run dev
```

1. Create a class schedule via admin: `/admin/schedule`
2. Browse available classes: `/book`
3. Select a class and fill in details
4. Should redirect to Stripe Checkout (will fail without real Stripe keys — expected)
5. Bundle page at `/book/bundle` should show £75 purchase flow

- [ ] **Step 6: Commit**

```bash
cd ~/code/moontide
git add .
git commit -m "feat: add public booking pages with schedule browser, bundle purchase, and confirmation"
```

---

### Task 11: Stripe Account Setup & Integration Test

**Files:**
- No code changes — infrastructure and secrets configuration

- [ ] **Step 1: Create Stripe account**

Go to https://dashboard.stripe.com and create an account for the Moontide business. Start in test mode.

- [ ] **Step 2: Get API keys**

From the Stripe dashboard (test mode):
- **Publishable key** (starts with `pk_test_`)
- **Secret key** (starts with `sk_test_`)

- [ ] **Step 3: Set up webhook**

In Stripe dashboard → Developers → Webhooks → Add endpoint:
- **URL:** `https://moontide-six.vercel.app/api/stripe/webhook` (use production URL once domain is set)
- **Events:** `checkout.session.completed`
- Note the **webhook signing secret** (starts with `whsec_`)

- [ ] **Step 4: Add Stripe secrets to Doppler**

```bash
doppler secrets set --project moontide --config dev \
  STRIPE_SECRET_KEY="sk_test_..." \
  STRIPE_WEBHOOK_SECRET="whsec_..." \
  NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY="pk_test_..."

doppler secrets set --project moontide --config prd \
  STRIPE_SECRET_KEY="sk_test_..." \
  STRIPE_WEBHOOK_SECRET="whsec_..." \
  NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY="pk_test_..."
```

- [ ] **Step 5: Add Stripe env vars to Vercel**

```bash
cd ~/code/moontide
printf 'sk_test_...' | npx vercel env add STRIPE_SECRET_KEY production
printf 'whsec_...' | npx vercel env add STRIPE_WEBHOOK_SECRET production
printf 'pk_test_...' | npx vercel env add NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY production
printf 'pk_test_...' | npx vercel env add NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY preview
printf 'pk_test_...' | npx vercel env add NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY development
```

- [ ] **Step 6: Test end-to-end booking with Stripe test card**

1. Create a schedule via admin
2. Go to `/book`, select the class, fill in details, click "Pay & Book"
3. On Stripe Checkout, use test card `4242 4242 4242 4242`, any future expiry, any CVC
4. Should redirect to `/book/confirmation`
5. Check admin `/admin/bookings` — booking should appear
6. Check Stripe dashboard — payment should appear

- [ ] **Step 7: Test bundle purchase**

1. Go to `/book/bundle`, enter email, click "Purchase Bundle"
2. Pay with test card on Stripe Checkout
3. Should redirect to `/book/confirmation?type=bundle`
4. Check admin `/admin/bundles` — bundle should appear with 6 credits
5. Go to `/book`, book a class with same email, check "I have a class bundle"
6. Should book immediately (no Stripe redirect), credits should decrement to 5

---

### Task 12: Deploy & Update CLAUDE.md

**Files:**
- Modify: `~/code/moontide/CLAUDE.md`

- [ ] **Step 1: Deploy to production**

```bash
cd ~/code/moontide
git push
npx vercel deploy --prod
```

- [ ] **Step 2: Apply production migration**

```bash
cd ~/code/moontide
doppler run --config prd -- npx drizzle-kit migrate
```

- [ ] **Step 3: Seed production class types**

```bash
cd ~/code/moontide
doppler run --config prd -- npx tsx scripts/seed-classes.ts
```

- [ ] **Step 4: Seed production admin user**

```bash
cd ~/code/moontide
ADMIN_PASSWORD=<secure-password> doppler run --config prd -- npx tsx scripts/seed-admin.ts
```

- [ ] **Step 5: Update CLAUDE.md with Phase 2 conventions**

Add to the Key Conventions section:
- Better Auth protects `/admin/*` routes via middleware
- Admin API routes at `/api/admin/*` — not separately protected (rely on middleware)
- Stripe webhook at `/api/stripe/webhook` — uses raw body for signature verification
- Booking flow: `/api/book/checkout` (Stripe) and `/api/book/redeem` (bundle)
- Class prices stored in `classes.priceInPence` — always in pence, never pounds
- Bundle price constant in checkout route (£75 for 6 classes)
- Bundle redemption is email-based lookup, no auth required for customers

- [ ] **Step 6: Commit**

```bash
cd ~/code/moontide
git add .
git commit -m "docs: update CLAUDE.md with Phase 2 conventions"
```
