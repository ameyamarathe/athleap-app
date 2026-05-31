# Athleap

Athleap is an AI-powered dynamic training coach for iOS, built for runners, cyclists, triathletes, and swimmers.

Unlike static training plan apps, Athleap reads your body's daily metrics — HRV, resting heart rate, sleep, SpO2, and training load — from your wearable and adapts your training plan in real time. If your recovery is low, it adjusts. If you nailed last week's sessions, it progresses you. The plan fits your actual life, not an idealised version of it.

## The Problem

Existing training apps (Runna, Garmin Coach, TrainingPeaks) generate a plan and largely stick to it regardless of how your body is responding. A shift worker coming off nights, an athlete with a bad sleep week, or someone carrying fatigue from a hard training block all get the same session the app planned on day one. That's not coaching — it's a static spreadsheet.

## What Athleap Does Differently

- **Reads daily recovery data** from Apple Watch, Garmin, and Coros
- **Generates a weekly training plan** based on your goals, fitness level, schedule, and available data
- **Adjusts daily** as new vitals come in — not just flagging a bad day but actually modifying the right sessions in the right way
- **Explains every change** — the AI tells you why it adjusted your plan, and you can always override it
- **Closes the feedback loop** — compares what you actually did against what was planned and uses that to shape future sessions
- **Pushes structured workouts to your watch** — sessions appear in your Garmin or Coros calendar ready to start, or launch directly from the app for Apple Watch users

## Core Features

- Dynamic plan adjustment based on HRV, sleep, and training load
- Tiered AI recommendations — auto-adjusts minor things, suggests and asks for bigger changes, strongly warns on red flags — but the user always has the final say
- Strain and recovery visualisation (acute load, chronic load, form)
- Planned vs actual workout comparison — the AI reads what you did and adapts accordingly
- Conversational AI coaching — ask why your plan changed and get a clear explanation
- Supports non-standard schedules (shift workers, irregular hours)
- Watch integrations: Apple Watch (HealthKit + WorkoutKit), Garmin (Connect API), Coros

## Sports Supported

- Running
- Cycling
- Triathlon
- Swimming

## How the AI Works

On day one, Athleap asks you about your goals, current fitness, available training days, schedule, and any injuries. It generates a conservative generic plan immediately. From day two onwards it begins adapting that plan as real data comes in. By week three it has enough of your personal baseline to make confident, specific adjustments. By week six it knows your patterns — how you respond to load, what your recovery looks like after hard efforts, what your normal HRV range is — and coaches you accordingly.

The AI never changes your plan silently without telling you. Every adjustment comes with a reason.

## Status

Currently in development. The coaching system is being validated on a live athlete before the iOS app is built.
