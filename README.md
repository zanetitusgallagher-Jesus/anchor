# Anchor

**A Scripture-first daily gate for macOS.** Anchor starts at login and covers every display with a calm, full-screen gate. You get to your other apps after a short morning routine: Bible reading, reflection, memory-verse review, journaling and one or two habit exercises. Then the gate steps aside for the rest of the day.

It never locks you out of your own Mac. An emergency unlock, a Shift-key safe launch and a failsafe timer are always available, and every use is logged.

- macOS 14 Sonoma or later · Swift 5.9+ · SwiftUI · SwiftData
- Everything stays local. Personal writing is encrypted at rest. No analytics.
- Bundled public-domain translations: **KJV** (1769) and **World English Bible**. Optional **API.Bible** support for licensed translations, using your own key.
- **Focus hours:** after the gate is cleared, pause chosen apps (for example social or news apps) during the hours you set.

---

## The daily flow

| # | Step | What happens |
|---|------|--------------|
| 1 | **Welcome** | The date, your streak and a short centering verse. A **"How much time do you have today?"** slider (2–15 minutes) shapes the session (see below). Optional box breathing (4-4-4-4) is off by default; turn it on in Settings → Daily flow. |
| 2 | **Scripture** | The next day of your reading plan. **Continue** unlocks after the reading time set by the slider, which only counts while Anchor is frontmost. You can change the translation and text size, and star verses to memorize. |
| 3 | **Reflection** | One prompt each day, rotating: *Summarize the passage in one sentence* / *What does this reveal about God?* / *What is one thing to obey or apply today?* AI questions are optional (see below). |
| 4 | **Memory verse** | Shown only on days when SM-2 says a starred verse is due. Three modes: first-letter recall, cloze (fill the gaps), and full recitation. Anchor grades what you typed and suggests a score, and you choose the final grade. |
| 5 | **Journal** | SOAP, Gratitude (3 specific things), Prayer list (requests, then answers), or Free write (rich text). Each entry takes tags and a mood (1–5) and links to the day's passage. |
| 6 | **Rewire** | 1–2 short exercises a day, rotating through the ones you've enabled: *Gratitude, specifically*, a *When–then plan* (implementation intention), a CBT-style *Thought reframe*, and *Walk through the day* (process visualization). |
| 7 | **Unlock** | A summary card (streak, minutes in the Word, verses memorized). Then the gate goes away for the rest of the day. |

**Short on time?** The slider always goes down to **2 minutes**. If you choose less time than today's main-plan reading needs (about 10 minutes on a Bible in a Year day), today switches to **Verse a Day** automatically:
- your day and streak still count, and the 30-Day Challenge counts it too;
- the main plan's reading isn't skipped, it waits for your next session (Bible in a Year pace shows you a day behind);
- the dashboard marks these days in a lighter shade and lists them under *Recent sessions* as "Verse a Day · short on time".

The Welcome screen always says what keeps you on your main plan ("10+ minutes keeps you on Bible in a Year. That's the goal."), and has a one-tap button to choose that.

**Session length.** The slider remembers your last choice. When there's no short plan to fall back on (for example, when Verse a Day is already your main plan), its **minimum depends on today's reading**: Anchor counts the words and allows about 250 words a minute, a little above average silent reading speed.
- **Short readings** (Verse a Day, a psalm) start at **2 minutes**.
- **Bible in a Year** days (about 2,000 words) start at about **10 minutes**: roughly 9 to read and 1 to reflect.
- The top of the slider is at least 10 minutes above the minimum.

Reading gets the time today's passage needs, or about 40% of the session if that's more. The spare minutes add steps:

| Spare minutes after reading | Adds |
|---|---|
| any | Reflection |
| 3+ | Memory verse (if one is due) |
| 5+ | Journal |
| 7+ | one Rewire exercise |
| 9+ | a second Rewire exercise (if Settings allows two a day) |

In Settings you can mark each of steps 2–6 *Required*, *Optional* (shows **Skip for today**) or *Off*. With the defaults, the whole session takes about 10–15 minutes.

If you restart partway through, Anchor resumes after the steps you've already finished. Reading plans track **completed days**, not calendar dates, so a missed day never skips a reading.

### Reading plans (seed data)

| Plan | Length | Notes |
|------|--------|-------|
| Bible in a Year | 365 days | Genesis to Revelation, about 85 verses a day |
| New Testament in 90 Days | 90 days | about 88 verses a day |
| Psalms & Proverbs | 31 days | one Proverbs chapter per day of the month, plus about 5 Psalms |
| The Gospels | 45 days | Matthew to John |
| Custom | your choice | pick books and a number of days on the dashboard |
| **Verse a Day** | 229 days | one well-known verse or short passage a day; about a minute of reading |
| **Whole Bible, Shuffled** | 365 days | every verse exactly once, as a fresh mix of passages (≤25 verses each) from across the Bible each day; each shuffle is unique |

The days are balanced by **verse count**, not chapter count, so each day's reading is about the same length.

---

## The gate, and how it lets you out

**How it locks.** While the session isn't done, Anchor shows a borderless `NSWindow` at `.screenSaver` level on every display. The windows use `collectionBehavior` `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, so they appear on every Space and over full-screen apps. Anchor also sets

```
NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching,
                             .disableForceQuit, .disableHideApplication]
```

so the Dock, menu bar, ⌘-Tab, ⌘-H and ⌥⌘⎋ are unavailable.

**How it stays.** Anchor re-asserts the gate (re-activates itself and brings the windows forward) in these cases:
- another app activates
- Anchor resigns active
- the Mac or its displays wake
- the user session becomes active again
- displays are added or removed
- once a second as a backstop

A day-change notification and a 60-second re-check catch the start of a new day.

**When it appears.**
- Only on the weekdays you choose.
- At **any time of day** by default: every login, wake and screen unlock shows the gate until today's session is done. Optionally set a cutoff hour in Settings → Gate so the gate only appears if your first use of the day is before it.
- Never once today's session is complete or unlocked.

The decision logic is pure Swift (`AnchorCore/GatePolicy.swift`) and unit-tested.

### Ways out (by design)

1. **Emergency unlock.** This is the link at the top right of the gate. Press and hold the button for **30 continuous seconds**, then type your unlock phrase (default: *I choose to unlock my Mac*; change it in Settings → Gate). You can add an optional reason. The gate is released for the rest of the day.
2. **Safe launch.** Hold **Shift** while Anchor launches (at login, or when you open it). No gate appears today.
3. **Failsafe.** If the gate has been up for 90 minutes (configurable, 30–240), it releases itself. This protects against a bug or a stuck step.
4. **Log out / restart / shut down** always work. Anchor never blocks session termination.

Uses 1–3 are recorded in the **Unlock log** (focus-hours allowances are logged there too, but they don't affect the gate) on the dashboard, and emergency-unlock days appear as outlined squares on the streak heatmap. An unlocked day doesn't count toward your streak, but you can still finish the session later from the menu bar, and then it does.

> If something goes badly wrong, you can also remove Anchor from **System Settings → General → Login Items** in a safe-launch session, or from another account. You can also delete `~/Library/Containers/app.anchor.Anchor`.

---

## Focus hours (app pausing)

Settings → **Focus** lets you choose apps to pause, the hours (for example 9:00–17:00, or overnight such as 22:00–02:00), and the days.

When you open a paused app during focus hours, Anchor:
1. hides the app, and
2. shows a calm full-screen "*App* is paused · Focus hours until 5:00 PM" screen with Colossians 3:23.

From there you can:
- choose **Back to what matters**, which keeps the app hidden and returns you to Finder, or
- **hold for 5 seconds** to allow the app for a few minutes (configurable, 1–30). Each allowance is recorded in the Unlock log.

Anchor checks when any app becomes active, plus every 2 seconds as a backstop, so an app that is already open when focus hours begin is paused too. Focus hours never apply while the morning gate is up.

**Never paused:** Finder, System Settings, Terminal, Activity Monitor and Anchor itself, even if you add them to the list. This keeps your Mac usable.

**Why not Apple's Screen Time API?** `FamilyControls`, `ManagedSettings` and `DeviceActivity` are available only on iOS, iPadOS and Mac Catalyst. They aren't available to native macOS apps, and Anchor's gate needs AppKit windows that a Catalyst app can't create. So Anchor pauses apps itself, using only public AppKit APIs (`NSWorkspace` activation notifications and `NSRunningApplication.hide()`). This needs no special entitlement or Apple approval, and the app stays sandboxed.

The trade-offs:
- It can't block websites.
- It can't stop an app's background work; it keeps the app out of sight.
- It's a commitment device, not a parental control that can't be bypassed.

The schedule logic is in `AnchorCore/Focus.swift`, with unit tests.

---

## Listening

The Scripture step has a **Listen** bar (⌘L) with play/pause/stop and speed (0.8×–1.5×). Every passage is read by a **human narrator**: the World English Bible recordings from [eBible.org](https://ebible.org/eng-web/audio/) (public domain), downloaded over HTTPS.

**Each day's passages are cut out of the chapter recordings,** so you hear exactly today's verses, even in the shuffled plan:
1. Each chapter's recording is downloaded once and cached on your Mac. The next passage downloads while the current one plays.
2. The recordings have no verse timestamps. Anchor estimates where each verse starts from the length of its text (a narrator's pace is steady within a chapter), then moves each cut to the nearest pause in the actual audio. Cuts lean earlier at the start and later at the end, so a passage is never clipped.
3. The verse being read is highlighted as you listen.

If narration can't load (for example, you're offline and the chapter isn't cached yet), Anchor says why and offers **Try again**, or reading it with the Mac's voice if you choose.

**How it stays reliable:**
- eBible.org names its files inconsistently from book to book (`01_01_Genesis_Chapter_One.mp3`, `0999 John-Chapter Three.mp3`, `0499 Psalms-Twenty One.mp3`, `0629 Proverbs-Chapter 001.mp3`, and duplicates). Anchor never guesses a URL. It reads each book's folder listing over HTTPS and works out the chapter from each file name.
- **CI checks the live source on every build** (`AnchorTests/LiveAudioTests.swift`):
  - all 66 books → all 1,189 chapters resolve;
  - sample files are real MP3 audio and AVFoundation can open them;
  - John 3:16–21 is cut from the John 3 recording with both cuts landing in real pauses;
  - every passage of a shuffled-plan day can be cut.

## Challenges

Start these from Dashboard → **Challenges**. Their progress shows on the Welcome screen, on the Unlock card and on the dashboard.

- **30-Day Challenge.** Complete your morning session on 30 days, starting today. Badges at 7, 14, 21 and 30 days. When the 30 days are up, you'll see how many you completed, and you can start again.
- **Bible in a Year.** Starting it begins a new **Whole Bible, Shuffled** plan and makes it your reading plan. Every day is a different mix of passages from across Scripture, and after 365 reading days you've read every verse once. Anchor shows whether you're on pace (for example "2 days ahead"). Badges at 30 days, 100 days, halfway and the whole Bible. Missed days never skip a reading; you just fall a little behind pace.

## Dashboard and menu bar

The menu bar icon (📖) shows your streak and a **Start today's session** button, which you can use even after the grace window or an unlock. It also opens the Dashboard and Settings.

The **Dashboard** has these pages:
- **Overview:** streak stats and a 26-week calendar heatmap.
- **Reading plan:** progress, the next reading, plan switching, and the custom plan builder.
- **Memory verses:** the deck with due dates, intervals and ease, plus a "Review now" session.
- **Journal:** search by text, tag, book and date range; edit or delete entries; export to **Markdown** or **PDF**.
- **Answered prayers:** open requests plus a timeline of answers, showing how long each was prayed for.
- **Unlock log**

---

## Privacy and data

- **Local only.** Data is stored with SwiftData inside the app's sandbox container. There are no accounts, analytics or telemetry.
- **Encrypted at rest.** Journal entries (including their tags, mood and passage), prayer requests, reflections and Rewire answers are sealed with **AES-256-GCM** (CryptoKit). The 256-bit key is generated on first use and stored only in the **Keychain** (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Dates, the template type, memory verses (public Scripture) and streak data are stored in plain form so they can be queried.
- **Exports are not encrypted.** The save panel says so.
- **Network** is used only by the two optional integrations, and only with keys you provide (stored in the Keychain):
  - **API.Bible.** Sends the chapter you're reading to `api.scripture.api.bible`.
  - **AI reflection questions** (off by default). When you press *Ask*, Anchor sends today's passage reference and text to `api.anthropic.com`. When you press *Get feedback*, it also sends the questions and your answers. Nothing else is sent: not your journal, prayers or other reflections. Settings → AI lists exactly what is sent.

---

## Install without Xcode

Every push to `main` is built on GitHub's Mac servers and published as **Anchor.zip** on the [latest release](https://github.com/zanetitusgallagher-Jesus/anchor/releases/tag/latest). It's a universal app, so it runs on both Apple silicon and Intel Macs, and it needs **macOS 14 Sonoma or later**.

Install it with one command in **Terminal**:

```bash
curl -L -o /tmp/Anchor.zip https://github.com/zanetitusgallagher-Jesus/anchor/releases/download/latest/Anchor.zip && ditto -x -k /tmp/Anchor.zip /Applications && open /Applications/Anchor.app
```

Run the same command again whenever you want to update.

If you download the zip in a browser instead, macOS will say the app "can't be opened" because it isn't signed by an identified developer. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the Anchor message. You only need to do this once.

> These builds are ad-hoc signed, not signed with an Apple Developer ID or notarized. That's fine on your own Mac. To share Anchor with other people, build it with a Developer ID as described below.

## Build and run

### Requirements
- Xcode 15 or later on macOS 14 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), which generates the `.xcodeproj` from `project.yml` so the project file never has merge conflicts:

```bash
brew install xcodegen
```

### Steps

```bash
make project     # xcodegen generate
```

```bash
open Anchor.xcodeproj
```

1. Select the **Anchor** target → *Signing & Capabilities* and choose your **Team**. Automatic signing is fine. The bundle ID is `app.anchor.Anchor`; change it if needed.
2. Run (⌘R). Anchor appears in the menu bar. If today's session isn't done and it's before the cutoff, the gate appears immediately.
   *Tip while developing:* hold **Shift** when you launch to skip the gate, or set *Settings → Gate → Only before* to an early hour.

From the command line:

```bash
make build
```

```bash
make test
```

To run only the pure-Swift logic tests (this also works on Linux):

```bash
make test-core
```

### Permissions
- **No Accessibility permission is needed.** The gate uses only public window-level and presentation-option APIs.
- **Login item:** on first launch Anchor registers itself with `SMAppService.mainApp`. macOS shows a "Login item added" notification. You can manage this in Settings → Gate → Startup or in System Settings → General → Login Items. If the status is *requires approval*, the Settings tab links straight to Login Items.
- **Sandbox entitlements:** `app-sandbox`, `network.client` (for the optional APIs), and `files.user-selected.read-write` (for export).

### Distributing
For your own Mac, an Xcode *Run* build or *Product → Archive → Distribute App → Copy App* is enough. For other people, archive with a Developer ID certificate, then notarize:

```bash
xcrun notarytool submit Anchor.zip --keychain-profile <profile> --wait
```

```bash
xcrun stapler staple Anchor.app
```

The hardened runtime is already enabled.

---

## Project structure

```
anchor/
├── project.yml                 XcodeGen spec (app + tests + local package)
├── AnchorCore/                 Swift package: pure domain logic, no UI (macOS + Linux)
│   ├── Sources/AnchorCore/
│   │   ├── DayKey.swift        calendar-day identity
│   │   ├── SM2.swift           SM-2 spaced repetition
│   │   ├── Streak.swift        current/longest streak with scheduled weekdays
│   │   ├── GatePolicy.swift    show/hide decision, failsafe, emergency-unlock rules
│   │   ├── Settings.swift      AnchorSettings (tolerant Codable)
│   │   ├── Bible.swift         Bible model, references, 66-book catalog
│   │   ├── ReadingPlan.swift   verse-balanced plan generator, progress
│   │   ├── Recall.swift        first-letter, cloze, recall grading → SM-2 quality
│   │   ├── DailyContent.swift  reflection rotation, Rewire scheduler, box breathing
│   │   ├── Journal.swift       templates, tags, search, Markdown export
│   │   ├── Focus.swift         focus-hours schedule, overnight windows, pause rules
│   │   ├── Challenge.swift     30-day and Bible-in-a-year challenge progress, pace, milestones
│   │   └── Summary.swift       flow steps, summary numbers
│   └── Tests/AnchorCoreTests/  SM-2, streak, gate-state, plan, recall, content tests
├── Anchor/                     the macOS app
│   ├── App/                    @main, AppDelegate, AppModel, menu bar
│   ├── Gate/                   GateController, GateWindow, DailyFlow, steps, emergency unlock, Claude client
│   ├── Scripture/              BibleStore, PlanStore, reader, API.Bible client
│   ├── Memory/                 review session (first-letter / cloze / recitation)
│   ├── Journal/                editor, NSTextView rich text, prayer list
│   ├── Rewire/                 the four exercises
│   ├── Focus/                  focus hours: app pausing controller, shield screen, settings
│   ├── Dashboard/              overview + heatmap, plan, memory, journal search/export, prayers, log
│   ├── Settings/               Settings window
│   ├── Shared/                 SwiftData models, AnchorStore, encryption, Keychain, theme
│   └── Resources/
│       ├── Bibles/KJV.json, WEB.json   (31,102 verses each, compact JSON)
│       └── Plans/*.json                (4 seed plans)
├── AnchorTests/                app-level tests (in-memory store, encryption, bundled data)
└── tools/                      scripts that rebuilt the seed data and draw the app icon (make_icon.py)
```

### Seed data provenance
- **KJV:** [scrollmapper/bible_databases](https://github.com/scrollmapper/bible_databases) (`formats/json/KJV.json`). Public domain (outside the UK Crown patent).
- **WEB:** [TehShrike/world-english-bible](https://github.com/TehShrike/world-english-bible) (per-book JSON). The World English Bible is in the public domain.
- `tools/build_bibles.py` normalizes both into `{id, name, books:[{id (USFM), name, chapters:[[verse…]]}]}`.
- `tools/build_plans.py` generates the plans with the same algorithm as `ReadingPlanGenerator.split`.

---

## Notes on the research-based copy

The Rewire exercises describe only what the evidence supports, and they cite their sources:
- **Gratitude.** Writing down specific good things is linked to small gains in well-being (e.g. Emmons & McCullough, 2003).
- **Implementation intentions** ("When X, I will Y"). These improve follow-through across many studies (Gollwitzer, 1999).
- **Cognitive reframing.** This is a core CBT technique. The exercise suggests talking to someone you trust or a counselor if thoughts are persistent.
- **Process visualization.** Rehearsing the *steps* helps more than imagining only the outcome (Taylor et al., 1998).

---

## Known limitations

- macOS lets some system UI appear above `.screenSaver` level windows: the Force Quit window (if invoked before the gate), Notification Center, and some security prompts. Anchor re-asserts itself afterwards. That's intentional: system security dialogs should never be blocked.
- macOS 14's cooperative app activation can delay re-activation for a moment when another app grabs focus. The gate windows stay on top during that time.
- Anyone with an administrator account can of course remove Anchor. It's a commitment device, not parental control.

## Roadmap

These phases are not built yet:
- **iCloud sync** through CloudKit. The models would need their `@Attribute(.unique)` constraints replaced, since CloudKit does not support them.
- **Family mode:** multiple profiles, each with its own plan and journal.
