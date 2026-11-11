# Anchor

**A Scripture-first daily gate for macOS.** Anchor starts at login and covers every display with a calm, full-screen gate. You get to your other apps after a short morning routine: breathing, Bible reading, reflection, memory-verse review, journaling and one or two habit exercises. Then the gate steps aside for the rest of the day.

It never locks you out of your own Mac. An emergency unlock, a Shift-key safe launch and a failsafe timer are always available, and every use is logged.

- macOS 14 Sonoma or later · Swift 5.9+ · SwiftUI · SwiftData
- Everything stays local. Personal writing is encrypted at rest. No analytics.
- Bundled public-domain translations: **KJV** (1769) and **World English Bible**. Optional **API.Bible** support for licensed translations, using your own key.

---

## The daily flow

| # | Step | What happens |
|---|------|--------------|
| 1 | **Welcome** | The date, your streak, a short centering verse, and 60 seconds of box breathing (4-4-4-4). You can skip after 15 seconds. |
| 2 | **Scripture** | The next day of your reading plan. **Continue** unlocks after the minimum reading time (default 5 min), which only counts while Anchor is frontmost. You can change the translation and text size, and star verses to memorize. |
| 3 | **Reflection** | One prompt each day, rotating: *Summarize the passage in one sentence* / *What does this reveal about God?* / *What is one thing to obey or apply today?* AI questions are optional (see below). |
| 4 | **Memory verse** | Shown only on days when SM-2 says a starred verse is due. Three modes: first-letter recall, cloze (fill the gaps), and full recitation. Anchor grades what you typed and suggests a score, and you choose the final grade. |
| 5 | **Journal** | SOAP, Gratitude (3 specific things), Prayer list (requests, then answers), or Free write (rich text). Each entry takes tags and a mood (1–5) and links to the day's passage. |
| 6 | **Rewire** | 1–2 short exercises a day, rotating through the ones you've enabled: *Gratitude, specifically*, a *When–then plan* (implementation intention), a CBT-style *Thought reframe*, and *Walk through the day* (process visualization). |
| 7 | **Unlock** | A summary card (streak, minutes in the Word, verses memorized). Then the gate goes away for the rest of the day. |

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
- Only if your first check of the day is before the **grace cutoff** (default 11:00). A gate that appeared at 10:55 stays up after 11:00; it doesn't vanish.
- Never once today's session is complete or unlocked.

The decision logic is pure Swift (`AnchorCore/GatePolicy.swift`) and unit-tested.

### Ways out (by design)

1. **Emergency unlock.** This is the link at the top right of the gate. Press and hold the button for **30 continuous seconds**, then type your unlock phrase (default: *I choose to unlock my Mac*; change it in Settings → Gate). You can add an optional reason. The gate is released for the rest of the day.
2. **Safe launch.** Hold **Shift** while Anchor launches (at login, or when you open it). No gate appears today.
3. **Failsafe.** If the gate has been up for 90 minutes (configurable, 30–240), it releases itself. This protects against a bug or a stuck step.
4. **Log out / restart / shut down** always work. Anchor never blocks session termination.

Uses 1–3 are recorded in the **Unlock log** on the dashboard, and emergency-unlock days appear as outlined squares on the streak heatmap. An unlocked day doesn't count toward your streak, but you can still finish the session later from the menu bar, and then it does.

> If something goes badly wrong, you can also remove Anchor from **System Settings → General → Login Items** in a safe-launch session, or from another account. You can also delete `~/Library/Containers/app.anchor.Anchor`.

---

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
│   │   └── Summary.swift       flow steps, summary numbers
│   └── Tests/AnchorCoreTests/  SM-2, streak, gate-state, plan, recall, content tests
├── Anchor/                     the macOS app
│   ├── App/                    @main, AppDelegate, AppModel, menu bar
│   ├── Gate/                   GateController, GateWindow, DailyFlow, steps, emergency unlock, Claude client
│   ├── Scripture/              BibleStore, PlanStore, reader, API.Bible client
│   ├── Memory/                 review session (first-letter / cloze / recitation)
│   ├── Journal/                editor, NSTextView rich text, prayer list
│   ├── Rewire/                 the four exercises
│   ├── Dashboard/              overview + heatmap, plan, memory, journal search/export, prayers, log
│   ├── Settings/               Settings window
│   ├── Shared/                 SwiftData models, AnchorStore, encryption, Keychain, theme
│   └── Resources/
│       ├── Bibles/KJV.json, WEB.json   (31,102 verses each, compact JSON)
│       └── Plans/*.json                (4 seed plans)
├── AnchorTests/                app-level tests (in-memory store, encryption, bundled data)
└── tools/                      scripts that rebuilt the seed data
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
- **Screen Time integration** (`FamilyControls` / `ManagedSettings`): block chosen apps during focus hours after the gate is cleared. This needs Apple's Family Controls entitlement.
- **iCloud sync** through CloudKit. The models would need their `@Attribute(.unique)` constraints replaced, since CloudKit does not support them.
- **Family mode:** multiple profiles, each with its own plan and journal.
