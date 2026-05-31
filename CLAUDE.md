# CLAUDE.md — Athleap

This file provides context to Claude Code when working in this repository. Read it fully before doing any work.

---

## What Athleap Is

Athleap is an AI-powered dynamic training coach, initially built as an iOS app. It reads daily health metrics from wearables (HRV, RHR, sleep, SpO2, steps) and dynamically adjusts a personalised training plan every day based on the user's actual recovery state — not a static plan.

The core differentiator vs Runna, Garmin Coach, TrainingPeaks: **the plan changes daily based on real data, and the AI explains every change**.

Target users: recreational athletes (runners, cyclists, triathletes, swimmers) who train seriously but aren't full-time athletes. A key persona is shift workers / night workers whose schedules and recovery patterns are irregular.

This project is also being used as a **learning vehicle for end-to-end data engineering and product analytics** — covering data pipelines, warehousing (Kimball), dbt transformations, and dashboarding.

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
| Garmin | Garmin Connect API (official developer program — apply at developer.garmin.com) |
| Coros | Coros API (official partnership — contact developer@coros.com) |

- **Apple Health as universal bridge**: aggregates data from all fitness apps; one connection covers sleep, HRV, workouts from any source
- **Strategy**: build on Apple Health first (covers Garmin + Coros data via their native apps), apply for official API access once app has traction
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

Dark theme (`#0C0C0E` background), green accent `#00D68F`, Dynamic Island iPhone frames.
Preview at `http://localhost:3131` (run `npx serve mockup -p 3131`).

1. **Home / Today** — Recovery ring score, HRV/RHR/sleep vitals, AI plan adjustment banner (keep/restore), this week's sessions
2. **Recovery & Metrics** — SVG HRV line chart, sleep + RHR cards, training load bars (CTL/ATL/TSB), weekly strain bars, time tabs (7D/1M/3M/1Y)
3. **Today's Session** — Session hero card, interval structure with colour-coded bars, "Start on Apple Watch" CTA, AI rationale card
4. **AI Coach Chat** — Conversational UI, AI explains changes, user asks about pace targets, AI gives specific HR/pace ranges
5. **Activity Log** — Filter tabs (All/Running/Strength/Cycling), workout entries with exercise breakdown, PR badges, planned vs actual

Bottom navigation: Home · Metrics · Plan · Coach · Profile

---

## Full Architecture

### Application Stack
- **One backend, two frontends**: FastAPI (Python) backend → iOS app (Swift/SwiftUI) + Web app (React/Next.js)
- **Web companion**: deeper metrics, full calendar view, all-time data
- **iOS data display**: 7D → 1M → 3M → 1Y; all-time on web only

### Data Stack (free/open source, on-premise)

| Layer | Tool | Purpose |
|-------|------|---------|
| Operational DB | PostgreSQL | App database — users, sessions, vitals, plans |
| Transformation | dbt Core (CLI) | ETL layer — staging → intermediate → marts |
| Analytical DB | DuckDB (later) | Kimball star schema for heavy analytics |
| Scheduling | Cron jobs (now) → Airflow (later) | Pipeline orchestration |
| Dashboards | Metabase (self-hosted) | Internal analytics and metrics |
| App backend | FastAPI | Serves data to iOS and web |

### Data Pipeline Architecture

```
Data Sources
├── Apple HealthKit (HRV, sleep, RHR, SpO2, steps)
├── Garmin Connect API
├── Coros API
└── App events (user actions, plan changes, workout logs)
        ↓
   [EXTRACT]
   Python scripts — pull raw data, land in PostgreSQL raw schema
        ↓
   [TRANSFORM — dbt Core]
   staging models     → clean, rename, cast types, deduplicate
   intermediate models → HRV baseline, CTL/ATL/TSB, sleep scoring
   mart models        → Kimball fact + dimension tables
        ↓
   [LOAD]
   PostgreSQL marts schema (now) → DuckDB (when data grows)
        ↓
   [SERVE]
   FastAPI → iOS app + web
   Metabase → internal dashboards
```

### dbt Layer Structure

```
raw schema (PostgreSQL)
└── landed by Python ingestion scripts

staging (dbt)
├── stg_healthkit_vitals.sql
├── stg_garmin_activities.sql
└── stg_coros_activities.sql

intermediate (dbt)
├── int_hrv_baseline.sql         (rolling 30-day avg per user)
├── int_training_load.sql        (CTL/ATL/TSB calculations)
└── int_sleep_score.sql          (sleep quality scoring)

marts — Kimball star schema (dbt)
├── fact_daily_vitals.sql
├── fact_workouts.sql
├── fact_training_load.sql
├── fact_plan_adherence.sql      (planned vs actual)
├── dim_user.sql
├── dim_date.sql
├── dim_sport.sql
├── dim_workout_type.sql
└── dim_watch.sql
```

### Mapping to Familiar Concepts (Microsoft Fabric background)

| Fabric / Power BI | Athleap Equivalent |
|-------------------|-------------------|
| Power BI Dataflows (Power Query) | dbt models (.sql files) |
| Fabric Warehouse schemas | dbt layers (staging / intermediate / marts) |
| Scheduled refresh | Cron job running `dbt build` |
| PBI datamodel relationships | dbt schema.yml |
| Power BI reports | Metabase dashboards |

---

## Known Coros API Bugs (from personal system testing)
- `create_strength_workout()` hardcodes sets=1 → use custom httpx call
- `_check_response()` needs 2 args
- `schedule_workout()` needs `happen_day=` not `date=`
- v2 REST returns 500 for cardio → use `coros_api.create_workout()`

---

## Current Status

| Area | Status |
|------|--------|
| Product vision | Defined |
| UI Mockup | 5 screens built (`mockup/index.html`) |
| README | Written and pushed to GitHub |
| Data architecture | Designed — PostgreSQL + dbt + DuckDB + Metabase |
| Database schema | Written — `database/schema.sql` |
| ERD diagram | Built — `database/schema-diagram.html` |
| PostgreSQL instance | Not yet created — needs local install + `CREATE DATABASE athleap` |
| dbt project | Not yet set up |
| iOS app | Not yet started |
| FastAPI backend | Not yet started |
| Coaching system | Being validated on live athlete (founder) |

## Repo
`https://github.com/ameyamarathe/athleap-app`

---

## What to Work On Next

**Immediate next steps (in order):**
1. ~~Design PostgreSQL raw schema~~ ✅ Done — `database/schema.sql`
2. Install PostgreSQL locally (Windows) → `CREATE DATABASE athleap` → run schema.sql
3. Design Kimball star schema for marts layer
4. Set up dbt Core project structure
5. Write dbt staging + intermediate + mart models
6. Set up FastAPI backend skeleton
7. Build HealthKit data ingestion layer (most critical app dependency)
8. Set up iOS Xcode project (Swift/SwiftUI)

---

## Database Setup Instructions

### Local PostgreSQL setup (Windows)
1. Download and install from: https://www.postgresql.org/download/windows/
   - Remember the password set for `postgres` user
   - Default port: 5432
   - Install pgAdmin (included in installer)
2. Create the database:
   ```sql
   CREATE DATABASE athleap;
   ```
3. Run the schema:
   ```bash
   psql -U postgres -d athleap -f "T:\athleap-app\database\schema.sql"
   ```
   Or open `schema.sql` in pgAdmin Query Tool and run it.

### Files
- `database/schema.sql` — full DDL (3 schemas, 16 tables, indexes, triggers)
- `database/schema-diagram.html` — ERD diagram, open in browser at `http://localhost:3132`
