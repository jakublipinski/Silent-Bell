# Silent Bell

**A mindfulness bell that never makes a sound.** A standalone Apple Watch app that
taps your wrist at random moments — a quiet prompt to notice where your attention
is. No sound, no notification on the watch face, nothing anyone else can see.

[silentbell.app](https://silentbell.app) · [Privacy](https://silentbell.app/privacy.html) · [Support](https://silentbell.app/support.html)

The interesting part of this project is not the taps — it is staying alive between
them. watchOS gives an app almost no background runtime, and none of the obvious
routes (local notifications, background refresh, a phone companion, background
location) can deliver a silent haptic on a schedule. This README documents what
actually works, and the several things that do not, in enough detail to save
somebody else the search.

Everything below was verified on a real device rather than inferred from
documentation.

## What it is

A standalone watchOS app: a mindfulness bell that never makes a sound. It taps the
wrist at **random moments, X times per hour**, as a recurring prompt to bring
attention back to the present.

The randomness is the point: a predictable rhythm gets absorbed into the
background within a day; an unpredictable one keeps working. The timing is
deliberately not regularised.

Built and verified on an Apple Watch Series 7. The bundle identifier is
`app.silentbell.watch`.

## Governing constraints (all honoured)

1. **No notifications _as the reminder_** — the wrist taps are never notifications
   (local or push); a notification would leave a persistent Notification Center
   entry, which is the thing this project exists to avoid. **Deliberate exception:**
   a single self-clearing "resume" local notification is used as an occasional
   *meta-event* when a session ends — never as a reminder tap (see "Session
   lifecycle & resume"). This knowingly reverses the original "no
   `UNUserNotification` of any kind" rule, accepting the Focus caveat noted there.
2. **No sound** — haptic only (the resume notification is haptic-only too, `sound = nil`).
3. **No screen wake required** — taps land with the wrist down and display off.
4. **Focus-mode independent** — the reminder taps are haptics from an active
   session, so Focus never silences them. (The resume *notification* is the one
   Focus-gated element — see the caveat under "Session lifecycle & resume".) Focus is
   irrelevant by construction.
5. **No network** — no servers, relays, analytics, or telemetry. Nothing in this
   project makes a network request; the app has no networking code at all.
6. **Unpredictable timing** — stratified random, no fixed intervals, no alignment
   to round-number clock times.

## Architecture

Standalone watchOS app, SwiftUI, single target, no iOS companion. Small by
design — no coordinator layer. Source files in `SilentBell/`:

| File | Role |
|---|---|
| `SilentBellApp.swift` | `@main` App entry, hosts `ContentView`. |
| `Scheduler.swift` | Pure, testable stratified-random tap generator. Generic over the RNG so tests can seed it; the app uses `SystemRandomNumberGenerator`. |
| `ReminderSession.swift` | Owns the `WKExtendedRuntimeSession`, drives the scheduler one tap at a time, plays haptics, keeps the dev log. Exposes a single `Phase` (`stopped`/`starting`/`active`/`paused`) as the one source of truth for UI state. |
| `Haptics.swift` | The four distinct haptic signals (reminder / started / stopped / paused). The reminder tap is user-selectable at runtime via `@AppStorage`. |
| `ContentView.swift` | The three state screens (Stopped / Active / Paused), settings rows, tap-type picker, developer screen. |
| `Design.swift` | Visual language: palette, the `RippleMark`, `PillButton`, `SettingRow`, `OptionPicker`. |

Build configuration lives in `project.yml` (XcodeGen). The `.xcodeproj` is a
generated artifact — never hand-edited; regenerate with `xcodegen generate`.

## Scheduling model

**Stratified random, not uniform random.** Each active hour is divided into X
equal buckets (X = taps per hour) and one random moment is drawn inside each
bucket. Uniform sampling across the whole hour clusters badly (two taps seconds
apart, then long silence, reads as a malfunction); stratification keeps each tap
unpredictable while keeping the spacing usable.

As implemented in `Scheduler.swift`:

- **Minimum gap** enforced. If a bucket's draw lands closer than the gap to the
  previous fire, it's pushed forward to the minimum.
- **Re-randomised every hour.** Generation is forward-only and lazy: the current
  hour is cached and regenerated only when time crosses into the next hour, so
  each hour is drawn fresh — the schedule never cycles.
- **Buckets are anchored to the arm moment** (`epoch`), not to the clock hour.
  Because a session lasts exactly one hour, anchoring this way guarantees all X taps
  land inside it. Clock-hour anchoring used to strand taps past expiry — e.g. started
  at 10:56 with 1 tap/hour, the next draw fell at 12:58 while the session died at
  11:56, giving ~28 minutes of silence and then a quiet end.
- **No active window.** Removed by decision: the app only ever runs in a session the
  user has just started by hand, and that session dies within the hour, so a
  time-of-day window could never prevent anything the user didn't just ask for. It
  only added confusing states ("no taps fit the window", rolling forward to the next
  day). *You* are the active window.
- **One tap at a time.** The next fire is a single `DispatchQueue.main.asyncAfter`.
  The full schedule is never materialised as a bank of pending timers. Idle CPU
  between taps is effectively zero.
- **Debug 60-second hour.** A toggle compresses the "hour" to 60s for fast testing;
  the minimum gap is scaled by the same factor so debug distributions stay
  meaningful.

## Background runtime — the hard part, and how it's solved

Playing a haptic is trivial; staying alive between haptics is the whole problem.

The app uses **`WKExtendedRuntimeSession` with the `physical-therapy` session
type**. This is the type whose runtime continues in the **background** even when
the user presses the Digital Crown or switches apps — structurally identical to
what this app does. (Self-care and mindfulness survive screen-dimming but die on
Crown-press; only physical-therapy and smart-alarm run backgrounded, and
smart-alarm is a scheduled one-shot.)

The full delegate is implemented in `ReminderSession.swift`:
`extendedRuntimeSessionDidStart`, `extendedRuntimeSessionWillExpire`,
`extendedRuntimeSession(_:didInvalidateWith:error:)`. Invalidation reasons are
surfaced in the UI and dev log.

Platform facts that shaped the design (all verified against current Apple docs
and confirmed on-device):

- A session can only be **started while the app is foreground/active** — there is
  no way to schedule one ahead of time. The user starts it by opening the app and
  tapping.
- **One session at a time.**
- **Time limit is 1 hour** for physical-therapy. On expiry the app pauses;
  resuming across the day is the normal mode of operation, not an edge case. See
  "Session lifecycle & resume" for exactly how the app cues and eases each resume.
- The session type is declared in **Info.plist under `WKBackgroundModes` as the
  string `physical-therapy`** (set via `project.yml`), not passed at init.
- **No special entitlement is required.** Physical-therapy needs only the
  background mode. The `com.apple.developer.extended-runtime-session` entitlement
  belongs to the separate "health monitoring" session type — it is **not** used
  here, and must not be added (a Personal Team can't carry it, and it isn't
  needed).

### CPU discipline

watchOS silently terminates apps with sustained high CPU — no delegate fires, the
app just stops. Accordingly: no polling loops, no sub-second timers, no
animations, no `TimelineView` refreshing at high frequency, no live countdown.
Scheduling is one `asyncAfter` per tap, then idle.

### The Smart Stack / Live Activity indicator (not ours, not suppressible)

While a session runs, watchOS shows a **small status dot at the top of the screen**
and an auto-generated **Reminder entry in the Smart Stack** (Crown-scroll). This is
**not** something this app creates — there is no `NSSupportsLiveActivities` key, no
ActivityKit code and no widget target; the system advertises it on its own because
an extended runtime session is active (the same transparency it applies to
workouts). Consequently **there is no app-side API to hide it** — an app being able
to conceal its own background activity is precisely what the feature exists to
prevent. (No Apple documentation was found covering suppression for the
extended-runtime-session case; the nearest developer-forum guidance says visibility
is the wearer's setting, not the app's.)

The wearer's off switch, which **works and is purely cosmetic**: Settings →
(per-app) turn off Live Activities for Reminder — or globally under Settings →
Smart Stack (`Allow Live Activities`, `Auto-Launch Live Activities`). Turning it off
does **not** affect the session, background execution or the haptics; taps continue
exactly as before. This is currently turned **off** by preference ("less UI the
better").

Side effect worth remembering: that indicator was the only *glanceable* "running"
signal (the complication having been dropped), so with it off the watch face tells
you nothing either way — state is communicated purely by haptics and the resume
notification.

### Session lifecycle & resume

A session ends in one of two ways (both confirmed on-device):

- **Graceful 1-hour expiry** — `extendedRuntimeSessionWillExpire` fires ~seconds
  before the cap, while the session is still valid. The app plays the descending
  **"expired" haptic** there — a **Focus-proof** cue, because it's an app haptic
  from a live session, not a notification.
- **Early `suppressedBySystem` / error death** — the system cuts the session short
  with no `willExpire` warning; by `didInvalidate` the session is dead and (if
  backgrounded) no haptic can play. This is what made early deaths feel "silent".
  Diagnostics ruled out Low Power Mode (observed `lowPower=false`, battery ~40%);
  the exact trigger of the reason-4 case is still open, but the app no longer dies
  silently regardless (below).

**Resume mechanism** (in `ReminderSession`), added to make every resume noticeable
and cheap without polling:

- On **any** non-user session end, a single self-clearing **"resume" local
  notification** ("Silent Bell paused — Tap to resume.") is posted. Tapping it
  relaunches the app; ContentView auto-arms once the scene is `.active` (starting a
  session is only legal while active). Resuming (or tapping the notification)
  clears the delivered notification, so at most **one** ever sits in Notification
  Center. Same identifier (`"rearm"`) each time, so schedules replace, never stack.
- **Killed-app safety net:** the same notification is also **pre-scheduled at arm
  time for the expiry moment**, so it still fires if the app is terminated before
  it can run any `didInvalidate` cleanup.
- A deliberate **user stop** (reason `.none`) cancels the pending/delivered
  notification — no nudge.
- **Notification haptic is suppressed where our own haptic already fired.** The
  notification never plays a sound (`sound = nil`); its *alerting haptic* is
  controlled with `interruptionLevel`:
  - `.passive` — filed into Notification Center with **no alerting haptic and no
    screen wake**. Used on **graceful expiry**, where `willExpire` already played the
    Focus-proof "expired" haptic, so the notification is only a tappable button.
  - `.active` (default) — used when we **could not** play a haptic: the early
    `suppressedBySystem`/error death (session already dead while backgrounded) and
    the pre-scheduled killed-app safety net. There the notification is the *only*
    possible cue, so making it passive would restore the silent-death bug.

  The discriminator is a `didPlayExpiryHaptic` flag set in `willExpire` and reset on
  each arm — deliberately **not** the invalidation reason, since a full-hour graceful
  expiry has been observed reporting reason `-1 (error)` rather than `expired`.
- **Focus caveat:** the resume *notification* is Focus-gated. Under a daytime Focus
  the nudge's alert can be suppressed, so the app could lapse unnoticed. The
  graceful-expiry haptic is not gated; only the early-death path depends solely on
  the (gated) notification. If this proves a problem, the escape hatch is
  `HKWorkoutSession` (no 1-hour cap, no resume chore, Focus-proof) at the cost of a junk
  Activity entry and battery — evaluated and kept in reserve, not adopted.

## Haptics

`WKInterfaceDevice.current().play(_:)` with `WKHapticType` (the nine built-ins
are the whole palette; Core Haptics custom patterns aren't available on watchOS).
Four signals, defined in `Haptics.swift`, kept distinct so they're never
confusable:

- **Reminder tap** — a single built-in, **user-selectable at runtime** via the
  "Tap Type" picker (tapping a row plays it live and selects it). Default
  **`.start`**, shown as *Gentle* (`.click` was tried and felt too subtle;
  `.notification` felt like a real system alert). Stored in `@AppStorage` under
  `Haptics.reminderKey` and read live at fire time, so changing it needs no rebuild.
- **Started** — ascending two-part confirmation (`.start` → `.directionUp`).
- **Stopped** — descending two-part confirmation (`.directionDown` → `.stop`).
  Deliberately *shorter* than the paused alert, so a stop the user chose never
  feels like a session that ended on its own.
- **Paused** — descending three-part alert (`.directionDown` → `.stop` →
  `.failure`). Played at `willExpire` as the Focus-proof resume cue.

The picker names haptics for how they feel, not for the API constant:
Gentle→`start`, Tick→`click`, Knock→`notification`, Double→`success`,
Rise→`directionUp`, Fall→`directionDown`, Firm→`stop`, Heavy→`failure`,
Echo→`retry`.

## Configuration & defaults

All settings are in-app (shown only when a session is not running), persisted with `@AppStorage`:

| Setting | Default | Range |
|---|---|---|
| Taps per hour | **4** | 1–10 |
| Min. gap | **5 minutes** | 1–15 min |
| Tap Type | **Gentle** (`.start`) | any of the 9 built-ins |
| Debug 60-second hour | off | toggle (developer screen) |

Two properties worth knowing:

- Because buckets are anchored to the start moment, **any** taps/hour value delivers
  exactly that many taps inside the session — 1/hour no longer produces the long
  silence it used to.
- **The minimum gap also applies to the first tap** (the start moment counts as a
  virtual previous fire), so a tap can never land instantly and blur into the
  ascending "started" confirmation.
- The gap is **capped at 90% of one bucket** (`ScheduleConfig.effectiveMinGap`). A
  gap at or above the bucket size would clamp every draw to the floor, turning the
  schedule into a deterministic ladder and — once `tapsPerHour × gap > 1 hour` —
  pushing taps past the session's expiry. The cap preserves the randomness.

The developer screen (behind the "Log" row) holds the 60-second debug toggle, the
dev log, the build tag, and two **"Test resume"** buttons — *alerting* (the
early-death path) and *silent* (the graceful-expiry path as actually felt) — to
verify the notify → tap → auto-start flow without waiting for a real session end.

## Visual design

Designed in Claude Design; implemented in `Design.swift` + `ContentView.swift`.

- **Accent: Sand `#CFA86F`** — a low-saturation amber that reads as lamplight, not
  alert-orange, and holds up on OLED black at low brightness. Alternatives kept in
  the file as one-line swaps: Moonlight `#97A8C2`, Bone `#BFB8A8`.
- **The mark** (`RippleMark`) — a dot and its ripples: a sound wave rendered as
  something felt. **It never animates**; state is carried by fill and how far the
  ripple reaches.
- **Glance logic — three redundant, entirely static signals**, since no animation is
  permitted and there is no complication:
  1. *Where the colour sits.* Active carries the accent at the top (mark + word);
     Paused is monochrome up top and the only accent is the Resume button at the
     bottom. Rule: **top-lit = running**.
  2. *Fill.* Active is a filled accent dot with two full ripples; Paused is a grey
     dot whose ripples have settled to one faint ring; Stopped is all-grey with full
     ripples.
  3. *Density.* Active shows two lines of times; Paused is nearly empty — the
     silhouettes differ even when blurred by motion.
- **App icon** — the mark reduced to two elements (dot + one ring), as the design
  renders it in the notification badge, so it survives ~48px in the app grid. On
  `#1C1C1E` rather than true black, because a black icon vanishes into the black
  honeycomb. Rendered by a CoreGraphics script to a single 1024px
  `Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

## Feature scope

**In:** taps/hour, minimum gap, selectable reminder haptic, start/stop/resume, dev-only log
of scheduled and fired timestamps, 60-second debug mode, resume notification.

**Out (by decision):**

- **Complication / any UI indication.** Deliberately dropped — the app runs fully
  in the background with no watch-face presence. The "paused" haptic and the resume
  notification are the no-look cues. (A live-state complication would also have
  needed an App Group, which a free Personal Team can't use — so this decision
  also sidesteps that limitation.)
- **Active time-of-day window.** Removed (see "Scheduling model") — the user's
  deliberate start *is* the window, and sessions can't outlive the hour.
- iOS companion, settings sync, statistics/history/streaks.
- Anything the wearer has to look at during normal operation.

## Build & deployment — command line only

*Signing identifiers, the paired Watch's UDID and the provisioning-refresh setup
live in `OPERATIONS.md`, which is git-ignored.*

Full `Xcode.app` must be on disk (the watchOS SDK, `xcodebuild`, and `devicectl`
all ship inside it; Command Line Tools alone are insufficient). The IDE never
needs opening for day-to-day work.

One-time setup already done:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -downloadPlatform watchOS
brew install xcodegen
```

Every iteration goes through **`./run.sh`** (generate → build → install):

```bash
./run.sh
```

It builds for a **generic watchOS destination** (so the build never waits on the
Watch), then installs via `devicectl` with a retry loop (the Watch must be awake
and near the Mac for the install to land). Output is logged to `run.log`.

Manual equivalents, if ever needed:

```bash
xcodegen generate
xcodebuild -project SilentBell.xcodeproj -scheme SilentBell \
           -destination 'generic/platform=watchOS' \
           -allowProvisioningUpdates -derivedDataPath ./build build
xcrun devicectl device install app --device <WATCH_UDID> \
           ./build/Build/Products/Debug-watchos/SilentBell.app
```

## Testing — results

Two things verified independently (a randomised schedule must not be debugged
inside a process that might be silently dying).

**Schedule** (via dev log + 60-second debug mode) — **passed**: X fires per
period, no two closer than the minimum gap, non-clustered distribution, a
different sequence each period. (Tested while the active window still existed; the
window has since been removed and buckets anchored to the arm moment, which only
tightens the guarantee that every tap lands inside the session.)

**Background survival** (60-second period) — **passed**, including the case that
matters most:

1. App open, screen on — taps land. ✅
2. Wrist down, screen off — taps land. ✅
3. **Digital Crown pressed, app backgrounded — taps land.** ✅ (the test
   mindfulness sessions fail; physical-therapy passes)
4. Another app foreground — taps land. ✅

A multi-hour battery/resume-frequency run is the natural next real-world check;
resuming is required once per hour by the session limit.

## Fallback (not needed)

If physical-therapy sessions had proven unavailable, the fallback was
`HKWorkoutSession` (long background runtime + haptics, no special approval, at the
cost of a junk Activity entry and worse battery). The free-team physical-therapy
path worked, so this was never needed and is recorded only for context.

## Rejected approaches (design record)

Each was evaluated and ruled out; not to be revisited.

| Approach | Why it fails |
|---|---|
| watchOS Accessibility → Chimes | Silenced by every Focus mode (intended by Apple); fixed to the quarter hour. |
| Push services (ntfy, Pushover, Bark…) *as the reminder* | A push is always a notification. APNs has no delete; `apns-collapse-id` only replaces. |
| Deleting a delivered push from the app | Removal only affects the iPhone; the mirrored Watch copy stays (sync is Watch → iPhone only). |
| Shortcuts automation + Vibrate Device | Time-of-Day triggers are Daily/Weekly/Monthly only — no sub-daily, let alone random; runs on the iPhone, so the phone vibrates, not the wrist. |
| Third-party timer apps | No per-app haptic customisation on watchOS, and none randomise. |

## Licence

Source code is licensed under the **Apache License 2.0** — see [`LICENSE`](LICENSE).

The **"Silent Bell" name, the app icon, and the ripple mark are not covered by that
licence** and remain reserved (Apache-2.0 §6 grants no trademark rights). You are
welcome to read, build, fork and reuse the code; please ship it under your own name
and artwork.

## Building it yourself

Requires full Xcode (not just Command Line Tools) and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cp secrets.env.example secrets.env     # add your own team ID and Watch UDID
./run.sh                               # generate → build → install
```

`Reminder.xcodeproj` is generated and never committed; edit `project.yml` instead.
