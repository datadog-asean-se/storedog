# Feature Flags × RUM — Custom Workshop Lab

> **Companion module for:** [Monitor and Analyze Critical User Flows with Synthetic & Real User Monitoring](https://learn.datadoghq.com)
>
> **Branch:** `workshop/featureflags-rum` on [datadog-asean-se/storedog](https://github.com/datadog-asean-se/storedog)
>
> **Time:** ~45 minutes (can run immediately after the main RUM + Synthetics lab)

---

## What You Will Learn

By the end of this lab you will be able to:

- Understand what **OpenFeature** is and why it is the industry standard for feature flag SDKs
- Create a **Datadog Feature Flag** with two variants and a progressive rollout
- Wire the flag into a **Next.js** app using the Datadog OpenFeature browser provider
- See how flag variant data **automatically appears in every RUM session** — no manual instrumentation
- Use the **RUM Explorer** to compare user experience metrics between flag variants
- Understand how **Guardrail Metrics** can automatically roll back a bad release

---

## Background: The Problem This Lab Solves

In the main lab you used RUM Explorer, Session Replay, and Frustration Signals to find and diagnose real user problems. But how do you ship a risky change to real users *safely* — and know within minutes if it caused a regression?

The answer is **Feature Flags tied to your observability data**. Instead of:

```
Deploy → Wait for users to complain → Manually find the bug → Deploy a fix
```

You get:

```
Flag rollout at 10% → RUM detects Frustration Signals spike → Auto-rollback
```

This lab demonstrates that loop end-to-end using Storedog's existing `product-card-frustration` bug — now controlled by a real Datadog Feature Flag instead of a static JSON file.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Completed the main RUM + Synthetics lab | Storedog must already be running in your lab environment |
| Lab `.env` contains `DD_API_KEY` and `DD_APP_KEY` | Found at `/root/storedog/.env` in the lab host |
| Lab `.env` contains `DD_APPLICATION_ID` and `DD_CLIENT_TOKEN` | Same file — the RUM app credentials |
| Datadog org with **Feature Flags** enabled | Standard on all Datadog Learn lab orgs |

---

## Part 1 — Setup (5 minutes)

### Step 1.1 — Run the quick-start script

From the lab host terminal (`/root`), run a single command to swap the base Storedog stack for the Feature Flags–enabled version:

```bash
curl -fsSL https://raw.githubusercontent.com/datadog-asean-se/storedog/workshop/featureflags-rum/storedog-ff-lab.sh | bash
```

Or if you already cloned the repo:

```bash
bash /root/storedog-ff/storedog-ff-lab.sh
```

The script will:
1. Stop the running base Storedog stack
2. Clone the `workshop/featureflags-rum` branch to `/root/storedog-ff`
3. Copy your existing lab credentials (`.env`) into the new directory
4. Map `DD_APPLICATION_ID` → `NEXT_PUBLIC_DD_APPLICATION_ID` (required by Next.js)
5. Run `setup-feature-flags.sh` to create the flag in your Datadog org
6. Start the Feature Flags–enabled stack

> **Expected output:**
> ```
> ╔══════════════════════════════════════════════════════╗
> ║  Storedog — Feature Flags × RUM Workshop Lab Setup  ║
> ╚══════════════════════════════════════════════════════╝
> [1/5] Stopping base storedog stack... Stopped.
> [2/5] Setting up workshop repo at /root/storedog-ff...
> [3/5] Copying lab credentials...
> [4/5] Creating Datadog Feature Flag in your lab org...
>       === Datadog Feature Flags — Workshop Setup ===
>       [1/5] Validating credentials... OK
>       [2/5] Resolving flag environments... Using environment: 'dev'
>       [3/5] Checking if 'product-card-frustration' already exists...
>       [4/5] Creating flag 'product-card-frustration'... Created
>       [5/5] Setting up 50/50 allocation... Allocation created.
>       === Done ===
> [5/5] Starting Feature Flags × RUM storedog stack...
> ✅ All done!
> ```

### Step 1.2 — Verify the stack is running

```bash
docker compose -f /root/storedog-ff/docker-compose.dev.yml ps
```

All services (`frontend`, `backend`, `dd-agent`, `puppeteer`, etc.) should show **Up**.

### Step 1.3 — Troubleshooting the setup script

If the script fails, add `--debug` for verbose API output:

```bash
cd /root/storedog-ff
bash scripts/setup-feature-flags.sh --debug
```

Debug mode prints the raw JSON response from every Datadog API call, making it easy to spot the exact failure.

---

## Part 2 — Understanding the Code Changes (10 minutes)

This section explains what the workshop branch added to Storedog. You don't need to run anything — just read and understand.

### 2.1 — New dependencies (`package.json`)

```json
"@datadog/openfeature-browser": "^1.2.3",
"@openfeature/react-sdk": "^1.5.0",
"@openfeature/web-sdk": "^1.5.0"
```

**OpenFeature** is a [CNCF](https://cncf.io) open standard — a vendor-neutral API for feature flags. Think of it like OpenTelemetry, but for flags. Your app code calls `useBooleanFlagValue('my-flag', false)` regardless of which flag backend (Datadog, LaunchDarkly, etc.) is behind it.

**`@datadog/openfeature-browser`** is Datadog's OpenFeature *provider* — the plugin that connects the OpenFeature SDK to Datadog's flag management backend.

### 2.2 — Provider initialisation (`pages/_app.tsx`)

```typescript
import { DatadogProvider } from '@datadog/openfeature-browser'
import { OpenFeature } from '@openfeature/web-sdk'
import { OpenFeatureProvider } from '@openfeature/react-sdk'

// After datadogRum.init(...)
if (typeof window !== 'undefined') {
  const ffProvider = new DatadogProvider({
    clientToken: process.env.NEXT_PUBLIC_DD_CLIENT_TOKEN,
    applicationId: process.env.NEXT_PUBLIC_DD_APPLICATION_ID,
    site: 'datadoghq.com',
    env: 'dev',              // ← targets the 'dev' Datadog FF environment
    service: 'store-frontend',
    enableExposureLogging: true,
    enableFlagEvaluationTracking: true,   // ← wires flag data into RUM automatically
  })
  OpenFeature.setProvider(ffProvider)
}
```

Key points:
- Runs **client-side only** (`typeof window !== 'undefined'`) — flags are never evaluated server-side in this setup
- **`enableFlagEvaluationTracking: true`** is the magic: every flag evaluation is automatically attached to the user's RUM session — no extra code needed
- **`env: 'dev'`** targets the non-production Datadog Feature Flag environment, so you can experiment without affecting production

The app is wrapped with `<OpenFeatureProvider>` so all child components can use OpenFeature React hooks.

### 2.3 — Flag evaluation in the product list (`components/product/ProductList.tsx`)

**Before (server-side, no RUM correlation):**
```typescript
// pages/products/index.tsx — evaluated once at server render
const flag = (await codeStash('product-card-frustration', { file: config })) || false
return { props: { cardVersion: flag ? 'v2' : 'v1' } }
```

**After (client-side, RUM-correlated):**
```typescript
// components/product/ProductList.tsx — evaluated in the browser, live
import { useBooleanFlagValue } from '@openfeature/react-sdk'

const frustrationFlagEnabled = useBooleanFlagValue('product-card-frustration', false)
const resolvedCardVersion = frustrationFlagEnabled ? 'v2' : (cardVersion ?? 'v1')
```

When `frustrationFlagEnabled` is `true`, the user sees `ProductCard-v2` — product thumbnails that are not linked to the product page. Clicking them generates **rage clicks** and **dead clicks**, which Datadog RUM captures as Frustration Signals.

Because the evaluation happens in the browser via the Datadog OpenFeature provider, Datadog records:
- Which flag was evaluated (`product-card-frustration`)
- Which variant the user received (`control` or `frustration`)
- This data is attached to every RUM View, Action, and Error in that session

---

## Part 3 — Explore the Flag in Datadog (5 minutes)

### Step 3.1 — Find the flag

1. In Datadog, navigate to **Digital Experience → Feature Flags**
2. Find `product-card-frustration`
3. Notice it has two variants: `control` (normal cards) and `frustration` (broken cards)
4. It is currently **enabled** in the `dev` environment with a 50/50 allocation

### Step 3.2 — Examine the flag page

Click into the flag. Observe:

- **Environments tab** — the flag is in the `dev` environment (where Storedog sends data)
- **Variants** — `control` returns `false`, `frustration` returns `true`
- **Targeting Rules** — 50/50 split across all users (no targeting filter)
- **Real-time Metrics** — after a few minutes of Puppeteer traffic, you will see exposure counts per variant and performance metrics

> **Instructor note:** This is the same view that shows error rate, latency, and RUM signals broken down by variant — the "flag page as a mini-dashboard" story.

---

## Part 4 — Observe Flag Data in RUM (10 minutes)

### Step 4.1 — Open the RUM Explorer

1. Navigate to **Digital Experience → RUM → Sessions**
2. Wait 2–3 minutes for Puppeteer traffic to generate sessions

### Step 4.2 — Filter by flag variant

In the search bar, type:

```
@feature_flags.product-card-frustration:frustration
```

This filters to sessions where the user received the broken product cards variant. Compare to:

```
@feature_flags.product-card-frustration:control
```

**What to look for:**

| Metric | `control` variant | `frustration` variant |
|---|---|---|
| Frustration Signals | Low | High (rage clicks on broken thumbnails) |
| JS error rate | Normal | May be elevated |
| LCP (Largest Contentful Paint) | Normal | Similar (it's a layout change, not a perf change) |

### Step 4.3 — Session Replay with flag context

1. Click on any session from the `frustration` variant
2. Open **Session Replay**
3. Watch a user click on the product thumbnails — they are not linked, generating dead clicks
4. In the session attributes panel on the right, find the **Feature Flags** section
   - `product-card-frustration: frustration` — the variant that was active during this session

This is the key insight: you don't need to look in a separate tool to correlate the flag to the problem. The flag variant is **part of the session**, visible in the same replay.

### Step 4.4 — Frustration Signals in RUM Explorer

1. Navigate to **RUM → Frustration Signals**
2. Filter by `@feature_flags.product-card-frustration:frustration`
3. Observe the spike of **Dead Clicks** and **Rage Clicks** — these are the users hitting the broken product thumbnails

---

## Part 5 — Control the Rollout (10 minutes)

### Step 5.1 — Roll back the flag

In the Datadog Feature Flags UI:

1. Open `product-card-frustration`
2. Click **Edit Targeting Rules** in the `dev` environment
3. Change the `frustration` variant weight to **0%** (or disable the flag entirely)
4. Save

Wait 1–2 minutes. Reload the Storedog products page (`/products`). Product thumbnails should now link correctly — the `control` variant is serving to 100% of users.

Check the RUM Explorer: Frustration Signals should drop to zero for new sessions.

### Step 5.2 — Gradual rollout (instructor demo)

> This step is best done as a live demonstration. Students watch; the instructor drives.

The instructor sets up a **progressive rollout**:

1. Set `frustration` to 10%
2. In the **Metrics** tab on the flag page, attach a guardrail: `[RUM] Error count` → action: **ABORT**
3. Click **Start Rollout**

Increase to 25%, 50%... as Puppeteer generates traffic, the error/frustration signal spikes.

**When the guardrail fires:**
- Datadog automatically sets the flag back to 0% exposure
- A notification fires (Slack / email)
- No engineer needed to babysit the release

**The key message:** The same RUM data you used in the main lab to *diagnose* a problem is now being used to *prevent* the problem from reaching more users.

---

## Part 6 — Review the Code Changes (optional deep-dive, 5 minutes)

If you want to understand the diff between the base Storedog and the workshop branch, examine these three files:

```bash
# From the lab host
cd /root/storedog-ff

# See what changed
git diff origin/main -- \
  services/frontend/pages/_app.tsx \
  services/frontend/pages/products/index.tsx \
  services/frontend/components/product/ProductList.tsx \
  services/frontend/package.json
```

**The minimal change surface:**
- **4 files modified** — `package.json`, `_app.tsx`, `products/index.tsx`, `ProductList.tsx`
- **~30 lines of new application code**
- The other 100+ lines are the two new helper scripts (`setup-feature-flags.sh`, `storedog-ff-lab.sh`)

This is the practical lesson: adding OpenFeature + Datadog to an existing Next.js app is a small, contained change. The hard part is the flag *strategy* — what to flag, what guardrails to attach, and what rollback looks like.

---

## Part 7 — Clean Up

When done, stop the Feature Flags lab stack and restore the original Storedog if needed:

```bash
# Stop the FF stack
docker compose -f /root/storedog-ff/docker-compose.dev.yml down

# Restart the original base stack (if needed for the next lab section)
docker compose -f /root/storedog/docker-compose.dev.yml up -d
```

The flag in Datadog will remain in your lab org. You can archive it from the Feature Flags UI if you want a clean state.

---

## Reference — What Was Changed in This Branch

### File changes summary

| File | Change |
|---|---|
| `services/frontend/package.json` | Added `@datadog/openfeature-browser`, `@openfeature/web-sdk`, `@openfeature/react-sdk` |
| `services/frontend/pages/_app.tsx` | Added `DatadogProvider` init with `enableFlagEvaluationTracking: true`; wrapped app with `<OpenFeatureProvider>` |
| `services/frontend/pages/products/index.tsx` | Removed server-side `codeStash` call for `product-card-frustration` |
| `services/frontend/components/product/ProductList.tsx` | Added `useBooleanFlagValue('product-card-frustration', false)` — client-side flag drives card variant |
| `scripts/setup-feature-flags.sh` | New: creates the flag in the student's Datadog org via REST API. Run with `--debug` for verbose output. |
| `storedog-ff-lab.sh` | New: one-shot student setup script |

### Architecture flow

```
Browser
  │
  ├─ datadogRum.init()          ← RUM SDK (already in base Storedog)
  │
  ├─ OpenFeature.setProvider()  ← DatadogProvider (new in this branch)
  │     │ clientToken / applicationId / env:'dev'
  │     │ enableFlagEvaluationTracking: true
  │     ↓
  │   Datadog Feature Flags backend (fetches flag config)
  │
  ├─ useBooleanFlagValue('product-card-frustration', false)
  │     │ returns: true  → ProductCard-v2 (broken thumbnails)
  │     │          false → ProductCard    (normal thumbnails)
  │     ↓
  │   flag evaluation auto-attached to RUM session
  │
  └─ RUM session contains:
        @feature_flags.product-card-frustration = "control" | "frustration"
```

### Environment variable mapping

The lab's `.env` uses unprefixed names (`DD_APPLICATION_ID`, `DD_CLIENT_TOKEN`). Next.js requires `NEXT_PUBLIC_*` for client-side access. The `storedog-ff-lab.sh` quick-start script bridges this automatically by appending the prefixed aliases to `.env`.

| Lab `.env` var | Mapped to |
|---|---|
| `DD_APPLICATION_ID` | `NEXT_PUBLIC_DD_APPLICATION_ID` |
| `DD_CLIENT_TOKEN` | `NEXT_PUBLIC_DD_CLIENT_TOKEN` |
| `DD_SITE` | `NEXT_PUBLIC_DD_SITE` |

---

## Key Concepts Summary

| Concept | What it means |
|---|---|
| **OpenFeature** | CNCF open standard for feature flag SDKs — vendor-neutral, like OpenTelemetry for flags |
| **DatadogProvider** | Datadog's OpenFeature browser provider — connects OpenFeature to Datadog's flag backend |
| **`enableFlagEvaluationTracking`** | Auto-attaches flag variant to every RUM session — zero extra code needed |
| **Guardrail Metric** | A RUM/APM metric that auto-pauses or aborts a rollout when it degrades |
| **Progressive Rollout** | Staged traffic exposure (10% → 25% → 50% → 100%) with automatic advancement when guardrails are healthy |
| **Variant** | The specific value a user receives when a flag is evaluated (`control` or `frustration` in this lab) |
| **`@feature_flags.*`** | The RUM attribute namespace where flag evaluation data appears — filterable in the RUM Explorer |

---

## Further Reading

- [Datadog Feature Flags documentation](https://docs.datadoghq.com/feature_management/)
- [Datadog RUM Feature Flag Tracking](https://docs.datadoghq.com/real_user_monitoring/feature_flag_tracking/)
- [OpenFeature specification](https://openfeature.dev/docs/reference/intro/)
- [Guardrail Metrics blog post](https://www.datadoghq.com/blog/guardrail-metrics/)
- [Stop babysitting releases blog post](https://www.datadoghq.com/blog/feature-flags/)
- [`@datadog/openfeature-browser` on npm](https://www.npmjs.com/package/@datadog/openfeature-browser)
