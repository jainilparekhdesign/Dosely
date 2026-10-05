# Dosely — Medication Tracker (v1)

Native iOS app (SwiftUI + SwiftData, iOS 26+) built from the Medication Tracker PRD: scan a prescription, confirm, and get actionable reminders and an adherence record.

## Run it
1. Open `Dosely.xcodeproj` in Xcode 27.
2. Pick the **Dosely** scheme and an iPhone simulator (or your iPhone — set your Team under *Signing & Capabilities* first).
3. ⌘R. Tests: ⌘U (76 unit tests).

**Demo data (Debug builds only):** in *Product → Scheme → Edit Scheme → Run → Arguments*, add `-seedDemo` for two profiles, seven medicines and three weeks of history on a fresh install. `-scanSample /path/to/image.png` opens the scan flow on an image.

## What's in v1
| PRD area | Implemented |
|---|---|
| Prescription scan | VisionKit document camera or photo → on-device Vision OCR → Apple Intelligence (on-device, when available) structures rows → deterministic shorthand decoder. US (QD, BID, TID, QID, q8h, HS, PRN) and Indian (OD, BD, TDS, SOS, 1-0-1, ½-0-½, 5/7, 2/52) shorthand; ~180 Indian brands mapped to generics; OCR typo correction; optional RxNorm (RxNav) name check, which is off by default and sends names only |
| Review screen | Original image (zoomable) beside parsed fields, low-confidence fields highlighted, each flagged medicine must be checked before **Save** is enabled, original OCR line shown per medicine |
| Medication profile | 8 types, tablet shapes, colours, two-tone capsules, pill or box photo, strength, instructions, doctor, stock |
| Schedules | X times a day, every X hours, specific weekdays, every X days, as needed (with a daily max); a different amount per time; meal-relative times (before, with or after breakfast, lunch or dinner, or at bedtime); start date and end date or number of days, after which the course ends automatically |
| Reminders | Local notifications in a rolling window (≤56 of the 64 iOS allows), refilled on launch, foreground, edits, timezone change and background refresh. Medicines due at the same time are grouped into one notification. **Taken / Snooze 10 / Snooze 30 / Skip** work from the notification. A follow-up nudge comes if there's no response (configurable; quiet hours mute it). Critical medicines use time-sensitive alerts. The pill icon is attached to each notification |
| Tracking | Today timeline (Upcoming / Due / Taken / Skipped / Missed), one-tap Take, Take all, log a late dose with the actual time, undo, week strip for past days, as-needed logging |
| History | Month calendar with a daily adherence ring, per-medicine adherence, day detail with editing |
| v1.1 pulled in | Refill tracking and alerts, PDF adherence report (7/30/90 days, shareable), pill photo, caregiver profiles with their own meal times |
| Privacy | Everything stays on-device. The store uses iOS file protection. Optional Face ID lock. Delete photos or all data. Medical disclaimer must be agreed during onboarding. RxNorm credit in Settings |

## Layout
```
Dosely/
  App/        entry point, root/tab view, debug-only demo hooks
  Models/     SwiftData models, Schedule, DraftMedication, formatting
  Engine/     ScheduleEngine (pure schedule maths), DosePlanner (status + adherence)
  Scan/       TextRecognizer, ShorthandDecoder, PrescriptionParser, DrugDatabase, AIExtractor, ScanPipeline
  Services/   DataStore, DoseActions, NotificationService, ReportGenerator
  Views/      Today, Medications, Scan, History, Settings, Onboarding, Components
DoselyTests/  decoder, parser, schedule/DST, dose-logging tests
```

## Known gaps / next steps
- Tapering doses aren't supported yet. The workaround is several schedules with end dates.
- No cloud sync yet. The models use CloudKit-compatible defaults, so encrypted iCloud sync can be added without a migration.
- Critical alerts (which bypass mute) need an Apple entitlement. v1 uses time-sensitive notifications instead.
- The Indian brand list is a small built-in set. License a commercial source (e.g. CIMS/MIMS) before paid launch, as the PRD says.
- Scanning has only one language (English). Indian-language scan is still an open question in the PRD.
