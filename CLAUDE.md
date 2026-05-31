# CLAUDE.md — Athleap

This file provides context to Claude Code when working in this repository. Read it fully before doing any work.

---

## What Athleap Is

Athleap is an AI-powered dynamic training coach, initially built as an iOS app. It reads daily health metrics from wearables (HRV, RHR, sleep, SpO2, steps) and dynamically adjusts a personalised training plan every day based on the user's actual recovery state — not a static plan.

The core differentiator vs Runna, Garmin Coach, TrainingPeaks: **the plan changes daily based on real data, and the AI explains every change**.

Target users: recreational athletes (runners, cyclists, triathletes, swimmers) who train seriously but aren't full-time athletes. A key persona is shift workers / night workers whose schedules and recovery patterns are irregular.

---

## Commercial Model

- **Free tier**: Data tracking, 7-day metrics view, run clubs in area — visible forever so users see the value
- **Trial**: 2-week full access, no card required
- **Paid**: £8.99/month or £59.99/year
- **B2C only** for now (no B2B)
- AI cost estimate: ~£0.05–0.15/user/month at Claude API rates
- Revenue targets: 500 users = £4,500/mo; 1,000 = £9,000/mo; 2,000 = £18,000/mo

---

## Sports Supported (v1)

- Running
- Cycling
- Triathlon
- Swimming
- Strength training (integrated from v1 — sport-specific or standalone)

---

## Core Features

### Dynamic AI Coaching
- Week 1: generic conservative plan based on onboarding answers (goals, fitness level, available days, equipment, injuries)
- Day 2+: starts adapting as real vitals come in
- Week 3+: personal baseline established, confident specific adjustments
- Week 6+: knows patterns — how user responds to load, recovery after hard efforts, normal HRV range

### Tiered AI Suggestions (user always has final say)
- **Green (auto-adjust)**: Minor tweaks — adjust quietly, notify user with reason
- **Amber (suggest)**: Moderate signal — AI suggests, user confirms or overrides
- **Red (strong warning)**: Red flags — hard to override, AI explains risk clearly

### Hard-coded Rules (enforced in code, not AI)
- Never >10% weekly run volume increase
- No back-to-back high-impact days
- HRV <30ms = easy day only (non-negotiable)
- HRV <36ms = reduce intensity
- Injury protocol is non-negotiable

### HRV Gating
- Personal baseline built over time (not population averages)
- <36ms: reduce intensity
- <30ms: easy day only
- Morning sync: pre-calculate at 5–6am background sync; pull-to-refresh as fallback
- Two-stage display: sleep data first, HRV refines when available (~20 min after waking)

### Planned vs Actual Loop
- AI reads completed session data, compares against what was planned
- Reconstructs Apple Watch intervals from HealthKit pace stream (segments >6 min under 06:10/km = interval attempts)
- WorkoutKit (iOS 17+) gives per-step metrics when session started from the app
- Adapts future sessions based on what was actually achieved

### Training Load Metrics
- CTL (Chronic Training Load = fitness)
- ATL (Acute Training Load = fatigue)
- TSB (Training Stress Balance = form = fitness - fatigue)
- 80/20 polarised training: 80% Zone 2 easy, 20% threshold+
- Concurrent training management: separate strength and cardio by 6+ hours on same day

### Strength Training
- Integrated from v1 — not bolted on later
- Sport-specific strength OR standalone program
- Equipment-aware (barbell, dumbbells, resistance bands, bodyweight)
- User chooses: "curate strength based on my sport" OR "general strength program"
- Hevy-style logging: 3 months history free, unlimited history paid
- Custom exercise catalogue — not limited to what Coros/Garmin support natively

### Watch Integrations
| Watch | How it works |
|-------|-------------|
| Apple Watch | HealthKit (read all data), WorkoutKit iOS 17+ (push structured workouts, get per-step data back) |
| Garmin | Garmin Connect API (read data, push workouts to calendar) |
| Coros | Coros API (read data, push workouts to calendar) |

- **Apple Health as universal bridge**: aggregates data from all fitness apps; one connection covers sleep, HRV, workouts from any source
- Bidirectional sync: read from Apple Health/Garmin/Coros; write completed workouts back
- Deduplication: match by timestamp + sport type within 5 minutes; flag ambiguous duplicates to user; prefer richer data source

### Missing Watch Data
- Transparent message to user: "no overnight data — watch may not have been worn"
- Uses previous available data to make recommendation
- App continues to function — no hard dependency on daily data

### AI Knowledge Base (4 layers)
1. Sports science documentation
2. Published frameworks: Jack Daniels VDOT, Joe Friel periodisation, Andy Coggan power zones
3. Individual athlete data (accumulated over time)
4. Learned patterns (personal response to load, recovery signatures)

### AI Hallucination Prevention
- Constrained prompting within knowledge base
- Hard-coded rules enforced in code (not left to AI)
- Confidence-bounded outputs
- Sports scientist review before launch

### User-Initiated Workouts
- User can add an ad-hoc workout based on what they feel like doing
- AI logs it, accounts for it in load calculations, adapts the rest of the week accordingly

---

## Screens (Mockup built at `mockup/index.html`)

Dark theme (`#1a1a1a` background), green accent `#00E5A0`, iPhone-style phone frames.

1. **Home / Today** — Recovery score, HRV/RHR/sleep pills, AI plan adjustment banner (keep/restore), this week's sessions
2. **Recovery & Metrics** — HRV bar chart, sleep, RHR, training load (Fitness/Fatigue/Form bars), weekly strain, time tabs (7D/1M/3M/1Y)
3. **Today's Session** — Interval structure with colour-coded dots, "Start on Apple Watch" CTA, AI rationale card
4. **AI Coach Chat** — Conversational UI, AI explains changes, user asks about pace targets, AI gives specific HR/pace ranges
5. **Activity Log** — Filter tabs (All/Running/Strength/Cycling), workout entries with exercise breakdown, PR badges, planned vs actual

Bottom navigation: Home · Metrics · Plan · Coach · Profile

---

## Architecture Plan (not yet built)

- **One backend, two frontends**: FastAPI backend → iOS app (Swift) + Web app (React/Next.js)
- **Web companion**: deeper metrics, full calendar view, for users who want desktop access
- **iOS data display**: 7D → 1M → 3M → 1Y; all-time data available on web only

### Intervals.icu Integration (considered)
- Universal workout delivery layer
- Official REST API
- CTL/ATL/TSB calculations
- Syncs to Garmin/Polar/Apple Health
- Workout push → Apple Watch via Watchletic

---

## Known Coros API Bugs (from personal system testing)
- `create_strength_workout()` hardcodes sets=1 → use custom httpx call
- `_check_response()` needs 2 args
- `schedule_workout()` needs `happen_day=` not `date=`
- v2 REST returns 500 for cardio → use `coros_api.create_workout()`

---

## Current Status

- Product vision: defined
- README: written and pushed to GitHub
- Mockup: 5 screens built at `mockup/index.html`
- Coaching system: being validated on a live athlete (the founder) before iOS build begins
- iOS app: not yet started
- Backend: not yet started

## Repo
`https://github.com/ameyamarathe/athleap-app`

---

## What to Work On Next

When resuming, likely next steps are:
1. Define the technical architecture in more detail (FastAPI backend structure, Swift iOS project setup)
2. Set up the iOS Xcode project skeleton
3. Define the database schema (users, training plans, daily vitals, sessions, adjustments)
4. Build the HealthKit data ingestion layer first (most critical dependency)
