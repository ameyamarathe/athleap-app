-- ═══════════════════════════════════════════════════════════════════════════
-- ATHLEAP — PostgreSQL Schema
-- Version: 1.0.0
-- Description: Full operational database schema for Athleap iOS training app
--
-- Schemas:
--   raw    → data landing zone (from HealthKit, Garmin, Coros APIs)
--   app    → operational application tables
--   audit  → AI decision trail and change logs
--
-- Run order: extensions → schemas → app tables → raw tables → audit tables
--            → indexes → triggers
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- EXTENSIONS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";   -- UUID generation
CREATE EXTENSION IF NOT EXISTS "pg_trgm";     -- fuzzy text search on exercise names


-- ═══════════════════════════════════════════════════════════════════════════
-- SCHEMAS
-- ═══════════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS raw;    -- data as it lands from APIs
CREATE SCHEMA IF NOT EXISTS app;    -- operational application tables
CREATE SCHEMA IF NOT EXISTS audit;  -- AI decisions and change logs


-- ═══════════════════════════════════════════════════════════════════════════
-- APP SCHEMA — USERS & AUTH
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- USERS
-- Core identity table. One row per user.
-- ─────────────────────────────────────────────
CREATE TABLE app.users (
    user_id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    email               TEXT        NOT NULL UNIQUE,
    display_name        TEXT        NOT NULL,
    date_of_birth       DATE,
    gender              TEXT        CHECK (gender IN ('male', 'female', 'non_binary', 'prefer_not_to_say')),
    timezone            TEXT        NOT NULL DEFAULT 'UTC',
    subscription_tier   TEXT        NOT NULL DEFAULT 'free'
                                    CHECK (subscription_tier IN ('free', 'trial', 'pro')),
    trial_started_at    TIMESTAMPTZ,
    trial_ends_at       TIMESTAMPTZ,
    subscription_start  TIMESTAMPTZ,
    subscription_end    TIMESTAMPTZ,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email             ON app.users (email);
CREATE INDEX idx_users_subscription_tier ON app.users (subscription_tier);


-- ─────────────────────────────────────────────
-- USER FITNESS PROFILES
-- Onboarding answers. One row per user.
-- Updated as user edits their profile.
-- ─────────────────────────────────────────────
CREATE TABLE app.user_fitness_profiles (
    profile_id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id                 UUID        NOT NULL REFERENCES app.users (user_id) ON DELETE CASCADE,
    primary_sport           TEXT        NOT NULL
                                        CHECK (primary_sport IN ('running', 'cycling', 'triathlon', 'swimming', 'strength')),
    secondary_sports        TEXT[],                     -- e.g. ['cycling', 'strength']
    fitness_level           TEXT        NOT NULL
                                        CHECK (fitness_level IN ('beginner', 'intermediate', 'advanced')),
    years_training          SMALLINT,
    weekly_hours_available  NUMERIC(4,1),
    max_days_per_week       SMALLINT    CHECK (max_days_per_week BETWEEN 1 AND 7),

    -- Running performance markers
    recent_5k_time_seconds  INTEGER,
    recent_10k_time_seconds INTEGER,
    recent_hm_time_seconds  INTEGER,
    recent_marathon_seconds INTEGER,

    -- Cycling
    ftp_watts               INTEGER,

    -- Strength
    strength_level          TEXT        CHECK (strength_level IN ('none', 'beginner', 'intermediate', 'advanced')),
    strength_goal           TEXT        CHECK (strength_goal IN ('sport_specific', 'general', 'none')),
    available_equipment     TEXT[],                     -- ['barbell', 'dumbbells', 'bands', 'bodyweight', 'machine']

    -- Health & schedule
    current_injuries        TEXT,
    injury_notes            TEXT,
    is_shift_worker         BOOLEAN     NOT NULL DEFAULT FALSE,
    shift_pattern_notes     TEXT,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_user_fitness_profiles_user ON app.user_fitness_profiles (user_id);


-- ─────────────────────────────────────────────
-- USER SCHEDULE PREFERENCES
-- Which days and times the user prefers to train.
-- One row per day of week per user.
-- ─────────────────────────────────────────────
CREATE TABLE app.user_schedule_preferences (
    pref_id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID        NOT NULL REFERENCES app.users (user_id) ON DELETE CASCADE,
    day_of_week     SMALLINT    NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),  -- 0=Mon, 6=Sun
    preferred_time  TEXT        CHECK (preferred_time IN ('morning', 'afternoon', 'evening', 'flexible')),
    is_available    BOOLEAN     NOT NULL DEFAULT TRUE,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_schedule_prefs_user ON app.user_schedule_preferences (user_id);
CREATE UNIQUE INDEX idx_schedule_prefs_user_day ON app.user_schedule_preferences (user_id, day_of_week);


-- ─────────────────────────────────────────────
-- USER WATCH CONNECTIONS
-- One row per connected device/service per user.
-- ─────────────────────────────────────────────
CREATE TABLE app.user_watch_connections (
    connection_id       UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID        NOT NULL REFERENCES app.users (user_id) ON DELETE CASCADE,
    source              TEXT        NOT NULL
                                    CHECK (source IN ('apple_health', 'garmin', 'coros')),
    is_connected        BOOLEAN     NOT NULL DEFAULT TRUE,
    access_token        TEXT,                           -- encrypted at rest
    refresh_token       TEXT,                           -- encrypted at rest
    token_expires_at    TIMESTAMPTZ,
    last_synced_at      TIMESTAMPTZ,
    sync_status         TEXT        DEFAULT 'ok'
                                    CHECK (sync_status IN ('ok', 'error', 'pending', 'disconnected')),
    error_message       TEXT,
    connected_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_watch_connections_user_source ON app.user_watch_connections (user_id, source);
CREATE INDEX        idx_watch_connections_user        ON app.user_watch_connections (user_id);


-- ═══════════════════════════════════════════════════════════════════════════
-- RAW SCHEMA — DATA LANDING ZONE
-- dbt reads from here. Never modify after landing.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- RAW DAILY VITALS
-- One row per user per date per source per metric.
-- ─────────────────────────────────────────────
CREATE TABLE raw.daily_vitals (
    raw_vital_id    UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID        NOT NULL REFERENCES app.users (user_id) ON DELETE CASCADE,
    source          TEXT        NOT NULL CHECK (source IN ('apple_health', 'garmin', 'coros')),
    metric_date     DATE        NOT NULL,
    metric_type     TEXT        NOT NULL
                                CHECK (metric_type IN (
                                    'hrv_rmssd', 'resting_hr', 'spo2', 'steps',
                                    'respiratory_rate', 'skin_temp_deviation',
                                    'stress_score', 'body_battery'
                                )),
    value           NUMERIC(10,4) NOT NULL,
    unit            TEXT        NOT NULL,               -- 'ms', 'bpm', '%', 'steps'
    collected_at    TIMESTAMPTZ,                        -- when device collected it
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX        idx_raw_vitals_user_date ON raw.daily_vitals (user_id, metric_date);
CREATE INDEX        idx_raw_vitals_source    ON raw.daily_vitals (source);
CREATE INDEX        idx_raw_vitals_type      ON raw.daily_vitals (metric_type);
CREATE UNIQUE INDEX idx_raw_vitals_dedup     ON raw.daily_vitals (user_id, source, metric_date, metric_type);


-- ─────────────────────────────────────────────
-- RAW SLEEP SESSIONS
-- One row per sleep session per source.
-- ─────────────────────────────────────────────
CREATE TABLE raw.sleep_sessions (
    raw_sleep_id        UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID        NOT NULL REFERENCES app.users (user_id) ON DELETE CASCADE,
    source              TEXT        NOT NULL CHECK (source IN ('apple_health', 'garmin', 'coros')),
    sleep_date          DATE        NOT NULL,           -- date of the night
    bedtime             TIMESTAMPTZ,
    wake_time           TIMESTAMPTZ,
    total_sleep_seconds INTEGER,
    deep_sleep_seconds  INTEGER,
    rem_sleep_seconds   INTEGER,
    light_sleep_seconds INTEGER,
    awake_seconds       INTEGER,
    sleep_score         SMALLINT,                       -- source's own 0-100 score if available
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX        idx_raw_sleep_user_date ON raw.sleep_sessions (user_id, sleep_date);
CREATE UNIQUE INDEX idx_raw_sleep_dedup     ON raw.sleep_sessions (user_id, source, sleep_date);


-- ─────────────────────────────────────────────
-- RAW ACTIVITIES
-- One row per completed workout from watch/app.
-- Unprocessed — dbt cleans and matches to planned sessions.
-- ─────────────────────────────────────────────
CREATE TABLE raw.activities (
    raw_activity_id     UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID        NOT NULL REFERENCES app.users (user_id) ON DELETE CASCADE,
    source              TEXT        NOT NULL CHECK (source IN ('apple_health', 'garmin', 'coros', 'manual')),
    external_id         TEXT,                           -- source's own activity ID (for dedup)
    activity_type       TEXT        NOT NULL,           -- 'running', 'cycling', 'swimming', 'strength'
    started_at          TIMESTAMPTZ NOT NULL,
    ended_at            TIMESTAMPTZ,
    duration_seconds    INTEGER,
    distance_metres     NUMERIC(10,2),
    avg_heart_rate      SMALLINT,
    max_heart_rate      SMALLINT,
    avg_pace_sec_per_km NUMERIC(8,2),
    avg_power_watts     SMALLINT,
    normalized_power    SMALLINT,
    tss                 NUMERIC(6,2),
    calories            SMALLINT,
    elevation_gain_m    NUMERIC(8,2),
    avg_cadence         SMALLINT,
    raw_payload         JSONB,                          -- full raw API response
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX        idx_raw_activities_user        ON raw.activities (user_id);
CREATE INDEX        idx_raw_activities_started_at  ON raw.activities (user_id, started_at);
CREATE INDEX        idx_raw_activities_type        ON raw.activities (activity_type);
CREATE UNIQUE INDEX idx_raw_activities_dedup       ON raw.activities (user_id, source, external_id)
    WHERE external_id IS NOT NULL;


-- ═══════════════════════════════════════════════════════════════════════════
-- APP SCHEMA — TRAINING PLANS & SESSIONS
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- TRAINING PLANS
-- One plan = one week. New plan generated weekly by AI.
-- ─────────────────────────────────────────────
CREATE TABLE app.training_plans (
    plan_id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID        NOT NULL REFERENCES app.users (user_id) ON DELETE CASCADE,
    week_start_date     DATE        NOT NULL,           -- Monday of the week
    week_end_date       DATE        NOT NULL,           -- Sunday of the week
    plan_status         TEXT        NOT NULL DEFAULT 'active'
                                    CHECK (plan_status IN ('active', 'completed', 'superseded')),
    generated_by        TEXT        NOT NULL DEFAULT 'ai'
                                    CHECK (generated_by IN ('ai', 'manual')),
    ai_model_version    TEXT,                           -- which Claude version generated this
    generation_notes    TEXT,                           -- AI summary of why this plan was created
    total_planned_tss   NUMERIC(8,2),
    total_planned_hours NUMERIC(5,2),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX        idx_plans_user       ON app.training_plans (user_id);
CREATE INDEX        idx_plans_week_start ON app.training_plans (user_id, week_start_date);
CREATE UNIQUE INDEX idx_plans_active_week ON app.training_plans (user_id, week_start_date)
    WHERE plan_status = 'active';


-- ─────────────────────────────────────────────
-- PLANNED SESSIONS
-- One row per session within a training plan.
-- ─────────────────────────────────────────────
CREATE TABLE app.planned_sessions (
    session_id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    plan_id                 UUID        NOT NULL REFERENCES app.training_plans (plan_id) ON DELETE CASCADE,
    user_id                 UUID        NOT NULL REFERENCES app.users (user_id) ON DELETE CASCADE,
    scheduled_date          DATE        NOT NULL,
    session_type            TEXT        NOT NULL
                                        CHECK (session_type IN (
                                            'easy', 'threshold', 'interval', 'long',
                                            'recovery', 'strength', 'cross_training', 'rest'
                                        )),
    sport                   TEXT        NOT NULL
                                        CHECK (sport IN ('running', 'cycling', 'swimming', 'strength', 'triathlon', 'rest')),
    title                   TEXT        NOT NULL,
    description             TEXT,
    planned_duration_min    INTEGER,
    planned_distance_km     NUMERIC(6,2),
    planned_tss             NUMERIC(6,2),
    target_hr_zone          SMALLINT    CHECK (target_hr_zone BETWEEN 1 AND 5),
    target_power_low        SMALLINT,
    target_power_high       SMALLINT,
    target_pace_sec_per_km  NUMERIC(8,2),
    ai_rationale            TEXT,                       -- why AI chose this session
    session_order           SMALLINT,                   -- ordering within the day
    is_modified             BOOLEAN     NOT NULL DEFAULT FALSE,
    original_session_id     UUID        REFERENCES app.planned_sessions (session_id),
    session_status          TEXT        NOT NULL DEFAULT 'upcoming'
                                        CHECK (session_status IN (
                                            'upcoming', 'completed', 'skipped', 'modified', 'in_progress'
                                        )),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sessions_plan      ON app.planned_sessions (plan_id);
CREATE INDEX idx_sessions_user_date ON app.planned_sessions (user_id, scheduled_date);
CREATE INDEX idx_sessions_status    ON app.planned_sessions (session_status);


-- ─────────────────────────────────────────────
-- PLANNED INTERVALS
-- Interval structure within a cardio session.
-- ─────────────────────────────────────────────
CREATE TABLE app.planned_intervals (
    interval_id             UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id              UUID        NOT NULL REFERENCES app.planned_sessions (session_id) ON DELETE CASCADE,
    step_order              SMALLINT    NOT NULL,
    step_type               TEXT        NOT NULL
                                        CHECK (step_type IN ('warmup', 'interval', 'recovery', 'cooldown', 'steady', 'rest')),
    duration_seconds        INTEGER,
    distance_metres         NUMERIC(8,2),
    target_pace_sec_per_km  NUMERIC(8,2),
    target_hr_zone          SMALLINT    CHECK (target_hr_zone BETWEEN 1 AND 5),
    target_power_low        SMALLINT,
    target_power_high       SMALLINT,
    notes                   TEXT
);

CREATE INDEX idx_intervals_session ON app.planned_intervals (session_id);


-- ═══════════════════════════════════════════════════════════════════════════
-- APP SCHEMA — COMPLETED WORKOUTS & STRENGTH LOGGING
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- COMPLETED WORKOUTS
-- One row per finished workout.
-- Linked to a planned session where matched.
-- ─────────────────────────────────────────────
CREATE TABLE app.completed_workouts (
    workout_id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id                 UUID        NOT NULL REFERENCES app.users (user_id) ON DELETE CASCADE,
    planned_session_id      UUID        REFERENCES app.planned_sessions (session_id),
    raw_activity_id         UUID        REFERENCES raw.activities (raw_activity_id),
    source                  TEXT        NOT NULL CHECK (source IN ('apple_health', 'garmin', 'coros', 'manual')),
    sport                   TEXT        NOT NULL,
    title                   TEXT,
    started_at              TIMESTAMPTZ NOT NULL,
    ended_at                TIMESTAMPTZ,
    duration_seconds        INTEGER,
    distance_metres         NUMERIC(10,2),
    avg_heart_rate          SMALLINT,
    max_heart_rate          SMALLINT,
    avg_pace_sec_per_km     NUMERIC(8,2),
    avg_power_watts         SMALLINT,
    normalized_power        SMALLINT,
    tss                     NUMERIC(6,2),
    calories                SMALLINT,
    elevation_gain_m        NUMERIC(8,2),
    perceived_effort        SMALLINT    CHECK (perceived_effort BETWEEN 1 AND 10),
    user_notes              TEXT,
    is_ad_hoc               BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_completed_user       ON app.completed_workouts (user_id);
CREATE INDEX idx_completed_started_at ON app.completed_workouts (user_id, started_at);
CREATE INDEX idx_completed_planned    ON app.completed_workouts (planned_session_id);


-- ─────────────────────────────────────────────
-- EXERCISE CATALOGUE
-- Master list of all exercises.
-- Seeded with common exercises, users can add custom.
-- ─────────────────────────────────────────────
CREATE TABLE app.exercises (
    exercise_id         UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                TEXT        NOT NULL,
    muscle_groups       TEXT[],                         -- ['chest', 'triceps', 'anterior_deltoid']
    equipment           TEXT[],                         -- ['barbell', 'dumbbells', 'bodyweight']
    exercise_type       TEXT        NOT NULL
                                    CHECK (exercise_type IN ('strength', 'plyometric', 'mobility', 'cardio_drill')),
    is_compound         BOOLEAN     DEFAULT FALSE,
    is_custom           BOOLEAN     NOT NULL DEFAULT FALSE,
    created_by_user_id  UUID        REFERENCES app.users (user_id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_exercises_name   ON app.exercises USING gin (name gin_trgm_ops);
CREATE INDEX idx_exercises_muscle ON app.exercises USING gin (muscle_groups);


-- ─────────────────────────────────────────────
-- WORKOUT STRENGTH SETS
-- One row per set in a strength workout.
-- Powers Hevy-style logging.
-- ─────────────────────────────────────────────
CREATE TABLE app.workout_strength_sets (
    set_id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    workout_id          UUID        NOT NULL REFERENCES app.completed_workouts (workout_id) ON DELETE CASCADE,
    exercise_id         UUID        NOT NULL REFERENCES app.exercises (exercise_id),
    set_number          SMALLINT    NOT NULL,
    reps_planned        SMALLINT,
    reps_completed      SMALLINT,
    weight_kg           NUMERIC(6,2),
    duration_seconds    INTEGER,                        -- for time-based sets (planks etc)
    distance_metres     NUMERIC(8,2),                   -- for distance-based (sled push etc)
    is_warmup_set       BOOLEAN     NOT NULL DEFAULT FALSE,
    rpe                 SMALLINT    CHECK (rpe BETWEEN 1 AND 10),
    notes               TEXT,
    logged_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_strength_sets_workout          ON app.workout_strength_sets (workout_id);
CREATE INDEX idx_strength_sets_exercise         ON app.workout_strength_sets (exercise_id);
CREATE INDEX idx_strength_sets_user_exercise    ON app.workout_strength_sets (workout_id, exercise_id, weight_kg DESC);


-- ═══════════════════════════════════════════════════════════════════════════
-- APP SCHEMA — AI COACH
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- COACH CONVERSATION THREADS
-- One row per conversation thread per user.
-- ─────────────────────────────────────────────
CREATE TABLE app.coach_threads (
    thread_id       UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID        NOT NULL REFERENCES app.users (user_id) ON DELETE CASCADE,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_message_at TIMESTAMPTZ
);

CREATE INDEX idx_threads_user ON app.coach_threads (user_id);


-- ─────────────────────────────────────────────
-- COACH MESSAGES
-- One row per message in a conversation.
-- ─────────────────────────────────────────────
CREATE TABLE app.coach_messages (
    message_id      UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    thread_id       UUID        NOT NULL REFERENCES app.coach_threads (thread_id) ON DELETE CASCADE,
    user_id         UUID        NOT NULL REFERENCES app.users (user_id) ON DELETE CASCADE,
    role            TEXT        NOT NULL CHECK (role IN ('user', 'assistant')),
    content         TEXT        NOT NULL,
    tokens_used     INTEGER,                            -- track AI API cost per message
    model_version   TEXT,
    sent_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_messages_thread ON app.coach_messages (thread_id);
CREATE INDEX idx_messages_user   ON app.coach_messages (user_id, sent_at DESC);


-- ═══════════════════════════════════════════════════════════════════════════
-- APP SCHEMA — COMPUTED METRICS
-- Written by morning pipeline. App reads this — never joins raw directly.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- DAILY METRICS
-- One row per user per day.
-- Computed by Python + dbt pipeline every morning.
-- This is what the home screen reads.
-- ─────────────────────────────────────────────
CREATE TABLE app.daily_metrics (
    metric_id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID        NOT NULL REFERENCES app.users (user_id) ON DELETE CASCADE,
    metric_date         DATE        NOT NULL,

    -- Vitals (cleaned, best source wins after dedup)
    hrv_rmssd           NUMERIC(6,2),
    resting_hr          SMALLINT,
    spo2_pct            NUMERIC(5,2),
    steps               INTEGER,
    respiratory_rate    NUMERIC(5,2),

    -- Sleep
    sleep_total_min     INTEGER,
    sleep_deep_min      INTEGER,
    sleep_rem_min       INTEGER,
    sleep_score         SMALLINT,

    -- HRV baseline (rolling 30-day per user, updated daily)
    hrv_baseline_30d    NUMERIC(6,2),
    hrv_deviation       NUMERIC(6,2),
    hrv_status          TEXT        CHECK (hrv_status IN ('low', 'normal', 'elevated')),

    -- Training load (Banister impulse-response model)
    ctl                 NUMERIC(8,4),                   -- chronic training load (fitness)
    atl                 NUMERIC(8,4),                   -- acute training load (fatigue)
    tsb                 NUMERIC(8,4),                   -- training stress balance (form)

    -- Recovery score (composite 0–100)
    recovery_score      SMALLINT    CHECK (recovery_score BETWEEN 0 AND 100),
    recovery_status     TEXT        CHECK (recovery_status IN ('low', 'moderate', 'good', 'optimal')),

    -- Data quality
    hrv_source          TEXT,
    sleep_source        TEXT,
    watch_worn          BOOLEAN     DEFAULT TRUE,
    data_confidence     TEXT        CHECK (data_confidence IN ('high', 'medium', 'low', 'insufficient')),

    computed_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_daily_metrics_user_date ON app.daily_metrics (user_id, metric_date);
CREATE INDEX        idx_daily_metrics_date      ON app.daily_metrics (metric_date);
CREATE INDEX        idx_daily_metrics_recovery  ON app.daily_metrics (user_id, recovery_score);


-- ═══════════════════════════════════════════════════════════════════════════
-- AUDIT SCHEMA — AI DECISION TRAIL
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- AI PLAN ADJUSTMENTS
-- Every AI plan change is logged here with full context.
-- Never deleted — permanent audit trail.
-- ─────────────────────────────────────────────
CREATE TABLE audit.ai_plan_adjustments (
    adjustment_id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id                 UUID        NOT NULL REFERENCES app.users (user_id) ON DELETE CASCADE,
    session_id              UUID        REFERENCES app.planned_sessions (session_id),
    plan_id                 UUID        REFERENCES app.training_plans (plan_id),
    adjustment_date         DATE        NOT NULL,
    trigger_type            TEXT        NOT NULL
                                        CHECK (trigger_type IN (
                                            'low_hrv', 'poor_sleep', 'high_fatigue', 'illness',
                                            'overtraining', 'user_request', 'missed_session', 'exceeded_plan'
                                        )),
    severity                TEXT        NOT NULL
                                        CHECK (severity IN ('green', 'amber', 'red')),
    original_value          JSONB,                      -- session/plan values before change
    adjusted_value          JSONB,                      -- session/plan values after change
    ai_rationale            TEXT        NOT NULL,       -- human-readable explanation shown to user

    -- Vitals context at time of adjustment
    hrv_at_adjustment       NUMERIC(6,2),
    rhr_at_adjustment       SMALLINT,
    sleep_hours             NUMERIC(4,2),
    recovery_score          SMALLINT,

    -- User response
    user_accepted           BOOLEAN,                    -- null = not yet responded
    user_responded_at       TIMESTAMPTZ,
    user_override_notes     TEXT,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_adjustments_user    ON audit.ai_plan_adjustments (user_id);
CREATE INDEX idx_adjustments_date    ON audit.ai_plan_adjustments (adjustment_date);
CREATE INDEX idx_adjustments_trigger ON audit.ai_plan_adjustments (trigger_type);
CREATE INDEX idx_adjustments_severity ON audit.ai_plan_adjustments (severity);


-- ═══════════════════════════════════════════════════════════════════════════
-- TRIGGERS — AUTO-UPDATE updated_at
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION app.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON app.users
    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_profiles_updated_at
    BEFORE UPDATE ON app.user_fitness_profiles
    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_watch_connections_updated_at
    BEFORE UPDATE ON app.user_watch_connections
    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_plans_updated_at
    BEFORE UPDATE ON app.training_plans
    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_sessions_updated_at
    BEFORE UPDATE ON app.planned_sessions
    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER trg_daily_metrics_updated_at
    BEFORE UPDATE ON app.daily_metrics
    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();
