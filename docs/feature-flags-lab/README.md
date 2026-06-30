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
- Create a **Datadog Feature Flag** with two variants and enable it in a flag environment
- Wire the flag into a **Next.js** app using the Datadog OpenFeature browser provider
- See how flag variant data **automatically appears in every RUM session** — no manual instrumentation
- Use the **RUM Explorer** and **Session Replay** to observe the real user impact of an enabled flag
- **Disable** a flag to instantly roll back a bad experience without a new deployment
- Understand how **Guardrail Metrics** can automate this rollback

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

## Get the Lab

Run these two commands from the lab host terminal. That's all you need — the rest is handled automatically.

```bash
# Clone the workshop branch (fast — single branch, shallow)
git clone --branch workshop/featureflags-rum --single-branch --depth 1 \
  https://github.com/datadog-asean-se/storedog.git /root/storedog-ff

# Run the one-shot setup script
bash /root/storedog-ff/storedog-ff-lab.sh
```

> **Already have `/root/storedog-ff`?** Pull the latest changes instead:
> ```bash
> git -C /root/storedog-ff pull origin workshop/featureflags-rum
> bash /root/storedog-ff/storedog-ff-lab.sh
> ```

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
> [1/5] Base storedog compose not found at /root/lab — skipping stop.
> [2/5] Setting up workshop repo at /root/storedog-ff...
> [3/5] Copying lab credentials...       Copied from /root/lab/.env
> [4/5] Creating Datadog Feature Flag in your lab org...
>       === Datadog Feature Flags — Workshop Setup ===
>       [1/5] Validating credentials... OK (HTTP 200)
>       [2/5] Resolving flag environments... Using environment: 'Development'
>       [3/5] Checking if 'product-card-frustration' already exists...
>       [4/5] Creating flag 'product-card-frustration'... Created (id=...)
>       [5/5] Setting up allocation... Enabled (HTTP 200).
>       === Done ===
> [5/5] Starting Feature Flags × RUM storedog stack...
> ╔═══════════════════════════════════════════════════════════════╗
> ║  All done! Your Feature Flags × RUM lab is running.          ║
> ╚═══════════════════════════════════════════════════════════════╝
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
"@openfeature/react-sdk": "^1.4.1",
"@openfeature/web-sdk": "^1.9.0"
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
4. It is currently **ENABLED** in the `Development` environment

### Step 3.2 — Examine the flag page

Click into the flag. Observe:

- **Environments tab** — the flag is **ENABLED** in the `Development` environment (where Storedog sends data with `env:'dev'`)
- **Variants** — `control` returns `false`, `frustration` returns `true`
- **Targeting Rule: "Workshop 50/50" — 50% Control / 50% Frustration** — the setup script creates this rule automatically so half of Puppeteer sessions get each variant
- **"If no rules are met → Frustration (broken cards)"** — the fallback default if no targeting rule matches
- **Real-time Metrics** — after a few minutes of Puppeteer traffic, you will see exposure counts per variant and RUM performance metrics appear on this page

> **Instructor note:** This page is the "flag as a dashboard" story — real-time RUM signals split by variant, all in one place without switching tools.

---

## Part 4 — Observe Flag Data in RUM (10 minutes)

### Step 4.1 — Open the RUM Explorer

1. Navigate to **Digital Experience → RUM → Sessions**
2. Wait 2–3 minutes for Puppeteer traffic to generate sessions

### Step 4.2 — Filter sessions by flag variant

In the search bar, filter to the frustration cohort:

```
@feature_flags.product-card-frustration:frustration
```

Then compare to the control cohort:

```
@feature_flags.product-card-frustration:control
```

**What to look for:**

| Metric | `control` variant | `frustration` variant |
|---|---|---|
| Frustration Signals | Low | High (rage clicks on broken thumbnails) |
| Dead clicks | Rare | Frequent — users clicking unlinked thumbnails |
| Session duration | Normal | Shorter — users give up and leave |

> **Key insight:** You didn't write any tracking code. The flag variant appeared in RUM automatically because `enableFlagEvaluationTracking: true` was set in the DatadogProvider. Every evaluation is wired into every session.

### Step 4.3 — Session Replay with flag context

1. Click on any session from the list
2. Open **Session Replay**
3. Watch a user click on the product thumbnails — they are not linked, generating dead clicks
4. In the session attributes panel on the right, find the **Feature Flags** section:
   - `product-card-frustration: frustration` — you can see exactly which flag variant was active during this session

This is the money shot: flag variant, user behaviour, and performance metrics — all in the same view, no tool-switching required.

### Step 4.4 — Frustration Signals

1. Navigate to **RUM → Frustration Signals**
2. You should see a cluster of **Dead Clicks** and **Rage Clicks**
3. Filter by `@feature_flags.product-card-frustration:frustration` to confirm they all come from flag-exposed sessions

These are the users hitting the broken product thumbnails. In a real incident, this signal — correlated to the flag — would tell you exactly what to disable.

---

## Part 5 — Roll Back with One Click (10 minutes)

### Step 5.1 — Disable the flag

You've seen the broken experience in RUM. Now fix it — without any code change or deployment.

In the Datadog Feature Flags UI:

1. Open `product-card-frustration`
2. Click the **Development** environment tab
3. Click **Disable** (the toggle next to "ENABLED")
4. Confirm

**What just happened:**
- The DatadogProvider in Storedog's browser fetches the latest flag config every few minutes
- Within 1–2 minutes, it receives the disabled state
- `useBooleanFlagValue('product-card-frustration', false)` now returns the SDK default: `false`
- `false` → `control` variant → normal product cards with working thumbnails
- No deployment. No restart. No code change.

Wait 2 minutes, reload `/products`. Product thumbnails now link to product pages correctly.

Check the RUM Explorer: new sessions will no longer show `@feature_flags.product-card-frustration:frustration`. Frustration Signals drop to zero.

### Step 5.2 — Re-enable the flag

1. In the Feature Flags UI, click **Enable** on the Development environment
2. Wait 1–2 minutes
3. Reload `/products` — broken thumbnails are back
4. Check RUM — Frustration Signals return

This on/off toggle is the core of the demo. In production, you would use a **targeting rule with a percentage** (e.g., expose `frustration` to 10% of users first, then 25%...) instead of a 100% default. But the principle is the same: the flag is the rollback switch, and RUM is what tells you whether to pull it.

### Step 5.3 — Guardrail Metrics (instructor demo, optional)

> This step is best done as a live demonstration. Students watch; the instructor drives.

For a more advanced scenario, the instructor can configure an automated guardrail:

1. In the flag page, click **Edit Targeting Rules** in the Development environment
2. Change the default variant to `control` (safe state when no rules match)
3. Add a targeting rule: **100% of users → `frustration`** variant
4. In the **Metrics** section, click **Add Guardrail**:
   - Metric: `[RUM] Error count` or `[RUM] Long task count`
   - Action: **ABORT**
5. Save and **Enable** the flag

Now with the targeting rule active, Puppeteer traffic generates RUM data. When the guardrail metric crosses its threshold:
- Datadog **automatically disables** the targeting rule (rolls back to `control`)
- No engineer needed to watch a dashboard

**The key message:** The same RUM data you used in the main lab to *diagnose* a problem is now being used to *automatically prevent* the problem from reaching more users — without anyone having to watch a dashboard overnight.

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
