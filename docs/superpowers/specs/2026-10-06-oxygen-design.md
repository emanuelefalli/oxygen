# Oxygen: Helio Strap companion app for iOS (design spec)

- Date: 2026-10-06
- Owner: Emanuele Falli
- Status: approved 2026-10-07; revision 2 on 2026-10-07 (see section 16)
- Scope of this spec: the overall architecture of Oxygen, plus the detailed design of sub-project 1 (Foundation). Sub-projects 2 to 5 are outlined here and get their own specs.

## 1. Brief

### 1.1 Goal

Build Oxygen, a personal iOS app that replaces the Zepp app for daily use with the Amazfit Helio Strap. Oxygen syncs the strap over BLE, computes its own scores on the phone, records workouts, and offers a cleaner UI and simpler UX than Zepp. It starts from a fork of OpenCircuit.

### 1.2 Requirements stated by the owner

- Native iOS app that runs locally, with no cloud dependency.
- Data is pulled from the strap over BLE.
- Strain, recovery, sleep and stress are computed in software, inside the app.
- Workouts are recorded, including starting and stopping a workout from the phone.
- WHOOP-style presentation: strain 0–21, recovery 0–100% with colour bands, sleep performance as a percentage.
- A UI built only for the Helio Strap.
- OpenCircuit is the starting point.
- Distribution with a free Apple ID.
- Development machine: personal MacBook running macOS 26 Tahoe. No development happens on the work laptop.

### 1.3 Assumptions the owner accepted

- Personal use only. No App Store release.
- Oxygen's local store is the source of truth.
- Apple Health export is out of v1, because HealthKit needs a paid Apple Developer account. OpenCircuit's roadmap confirms this.
- Zepp stays installed only to keep the strap paired (which keeps the auth key valid) and to install firmware updates. Zepp's iOS Bluetooth permission stays off the rest of the time.

### 1.4 Success criteria

1. The owner stops opening Zepp for daily use.
2. The Today screen answers three questions without scrolling: how recovered am I, how much strain have I done, how did I sleep.
3. A workout can be started in two taps.
4. Every score can be traced to its inputs and its formula.

## 2. Constraints

| Constraint | Consequence |
|---|---|
| Free Apple ID (Personal Team) | Provisioning profiles expire after 7 days, so a weekly re-install from Xcode is needed. Each App ID also expires after 7 days, with at most 10 per 7 days. HealthKit cannot be signed. |
| No paid account | Only one app target and no app extensions in v1 (no widgets, no Live Activities). |
| The strap buffers about 7 days of history | A missed weekly re-sign, or a long gap between syncs, loses data. The re-sign guard (section 9.2) prevents this. |
| iOS background BLE limits | Sync runs in the foreground, plus CoreBluetooth background wake-ups when the strap connects. There is no background polling. |
| OpenCircuit licence: PolyForm Noncommercial 1.0.0 | The private copy is allowed for personal use. Oxygen must not be sold or used commercially. |
| One BLE owner at a time | Zepp and Oxygen must not hold the strap at the same time. Zepp's Bluetooth stays off. |

## 3. Background findings

- The Helio Strap uses the Zepp OS protocol: an ECDH handshake on curve sect163r2, AES-128 encrypted payloads, and chunked framing with CRC-32.
- A per-device auth key is created when the strap is first paired with Zepp, and is stored on Zepp's servers. Third-party apps use that extracted key. Unpairing the strap in Zepp invalidates it.
- OpenCircuit is an iOS app (Swift, SwiftUI, CoreBluetooth, SwiftData, HealthKit) with a clean-room `ZeppKit` module that handles auth, framing, history fetch and controls.
- OpenCircuit already syncs HR, resting HR, HRV, SpO₂, skin temperature, sleep respiratory rate, steps, stress, PAI and the strap's own sleep stages.
- OpenCircuit has no in-app strain or recovery score, does not import workouts recorded on the strap, and cannot start workouts. Workout control is open as issue #227.
- OpenCircuit's code is split in two:
  - `ios/OpenCircuitKit/` is a SwiftPM package. It provides the libraries `ZeppKit` (auth, framing, history fetch and record parsing; pure Swift plus CommonCrypto) and `ZeppKitTesting` (`FakeZeppDevice`, a simulated strap).
  - Everything that touches CoreBluetooth, SwiftData or the Keychain lives in the upstream app target under `ios/OpenCircuit/`: `HelioConnection`, `HelioSession`, `HelioKeyStore`, `HelioStoreSink` and `LocalStore`. Another app cannot link that code.
- Upstream acks every history round with `03 09` (keep on strap) and tracks a watermark per fetch type. The other ack, `03 01`, makes the strap discard the data.
- `HelioVerify`, part of `OpenCircuitKit`, is a macOS command-line tool. It authenticates with a real strap and fetches history, with no app signing.
- The upstream Xcode project is generated with XcodeGen from `ios/project.yml`.
- Workout control runs on the encrypted endpoint `0x0019`. OpenCircuit's protocol doc states that the phone's workout commands cannot be decrypted from a capture.
- Gadgetbridge (Android) syncs Zepp OS workouts, and Healthee pulls workout summaries from the strap over BLE.
- No project has decoded Zepp's own BioCharge and Exertion scores. Oxygen's scores are therefore its own, built on published formulas.
- HelioCore (iOS, Swift, MIT licence, early stage) gets the same auth key by logging in to the Zepp cloud with the owner's Zepp account. It decodes values streamed live while connected: HR, HRV, SpO₂, skin temperature and stress. Its README does not mention history sync, sleep or workouts. It still requires the strap to be linked to a Zepp account.
- The HRV statistic the strap reports (RMSSD or another) is not confirmed.

## 4. Approach

Chosen approach: **fork OpenCircuit, keep `OpenCircuitKit` as close to upstream as possible, and build Oxygen as a new app target with its own analytics package.**

- Oxygen links only the `ZeppKit` and `OpenCircuitKit` libraries.
- Oxygen owns its Bluetooth layer, its strap session, its key storage and its data store. These are adapted from the upstream app target's `ios/OpenCircuit/Helio/` files.

Rejected alternatives:

- **Rework OpenCircuit in place.** Upstream moves fast, so merges would become unmanageable within weeks.
- **Clean-room rebuild.** This gives the most control but is the most work, and every upstream protocol fix would have to be ported by hand.

Auth key decision (2026-10-07): the key is extracted once on the MacBook and pasted into Oxygen.

- An in-app Zepp cloud login, as HelioCore does it, is rejected for v1. The owner's Zepp password would pass through Oxygen, and Oxygen would depend on an unofficial cloud API that can change without notice.
- HelioCore's login flow stays recorded as the reference if the key ever has to be re-fetched (section 14).

## 5. Architecture

### 5.1 Repository layout

The repository lives at `github.com/emanuelefalli/oxygen` as a **private** copy of OpenCircuit, not a GitHub fork. A fork of a public repository is always public, and this repository will hold fixtures made from the owner's health data. The tree below is the layout once sub-project 5 is done. Each folder is created by the sub-project that first needs it.

```
oxygen/
├─ ios/OpenCircuitKit/          upstream; the only planned change is the workout protocol (sub-project 5)
│   └─ Sources/ZeppKit/         auth, framing, history fetch, record parsing
├─ ios/OpenCircuit/             upstream app target; unchanged, never installed
├─ ios/project.yml              upstream XcodeGen spec; unchanged
├─ ios/OxygenAnalytics/         new SwiftPM package, pure Swift, no UI, no BLE, no persistence
├─ ios/Oxygen/
│   ├─ project.yml              Oxygen's own XcodeGen spec
│   ├─ Sources/
│   │   ├─ App/                 app entry, build constants
│   │   ├─ Sync/                SyncCoordinator, SyncRunner, StrapConnection, StrapSession
│   │   ├─ Keys/                StrapAuthKey, StrapKeyStore
│   │   ├─ Store/               RawStore (raw rounds, watermarks); derived data from sub-project 2
│   │   ├─ Decode/              StrapRecordDecoder, record de-duplication
│   │   ├─ Log/                 TransitionLog
│   │   ├─ ResignGuard/         provisioning profile expiry
│   │   ├─ Export/              raw data export
│   │   ├─ Workouts/            WorkoutController (sub-project 5)
│   │   └─ Screens/
│   └─ Tests/                   OxygenTests
└─ docs/superpowers/            specs, plans, notes
```

### 5.2 Dependency rules

- `Oxygen` depends on `OxygenAnalytics` and the `ZeppKit` and `OpenCircuitKit` products of the `OpenCircuitKit` package.
- `OxygenAnalytics` depends on nothing outside the Swift standard library and Foundation. Its inputs are plain value types, and the time zone and the current time are explicit parameters. The same input always gives the same output.
- `OpenCircuitKit` has no knowledge of Oxygen.
- Oxygen never links or compiles code from the upstream app target `ios/OpenCircuit/`. Files adapted from it carry a header comment naming the source path and the upstream commit.
- Oxygen owns one SwiftData container. It holds raw history rounds and watermarks (sub-project 1), and derived records from sub-project 2 onward.
- Raw history rounds are append-only.

### 5.3 Git strategy

- Remotes: `origin` is the private repository, `upstream` is `perezjuanj/OpenCircuit`.
- `main` = upstream plus `ios/Oxygen/`, `ios/OxygenAnalytics/` and `docs/superpowers/`.
- Merge `upstream/main` into `main` once a month, then:
  - run the whole Kit test suite and the Oxygen tests;
  - diff `ios/OpenCircuit/Helio/` since the commit recorded in Oxygen's header comments, and port relevant fixes by hand;
  - smoke-test on the phone.
- Kit changes for workout control live on the branch `zeppkit-workout-control` and are offered upstream when possible.

### 5.4 State handling

All connection and workout logic is written as explicit state machines with a closed set of states and events. No callback chains. Every transition is written to the transition log (section 10.2).

## 6. Data flow

```
strap ──BLE──► StrapConnection ──► StrapSession (drives ZeppKit) ──► RawStore (raw history rounds, append-only)
                                                                       │  StrapRecordDecoder (ZeppKit parser) + de-duplication
                                                                       ▼
          value types: MinuteSample, SleepSession, HrvSample, StressSample, WorkoutRecord
                              │
                     OxygenAnalytics (pure functions)
                              ▼
          Oxygen store (derived): CycleScores, WorkoutScores (each tagged with algorithmVersion) ──► Screens
```

- Raw data is never modified by Oxygen.
- History rounds are stored exactly as ZeppKit delivers them: decrypted, reassembled and CRC-checked bytes.
- Decoding happens on read, so an improved ZeppKit parser also applies to data stored earlier.
- A round is stored once per (fetch type, round start, payload SHA-256).
- Decoded records are unique by (fetch type, record timestamp). If two rounds contain the same record, the one received later wins.
- Every derived record stores the `algorithmVersion` that produced it. When the version changes, all derived records are recomputed from raw data.
- **Main sleep:** the longest strap sleep session that ends between 00:00 and 14:00 local time. Other sleep sessions are naps and do not start a cycle.
- **Cycle:** a cycle starts at the end of a main sleep and runs until the end of the next main sleep. If a calendar day has no main sleep, that day's cycle starts at 04:00 local time.
- Recovery belongs to the cycle that starts at the wake-up following the sleep it was computed from.

## 7. Analytics engine (sub-project 2, outline)

The constants below are starting values. The sub-project 2 spec fixes the final values after calibrating them against the owner's exported data.

### 7.1 Profile inputs

- `birthYear`
- `sex` (male or female; selects the TRIMP coefficients)
- `maxHeartRateOverride` (optional)
- `sleepNeedBaselineHours` (default 8.0)

### 7.2 Heart rate reserve

- `HRmax` = `maxHeartRateOverride`, or else `208 − 0.7 × age` (Tanaka).
- `HRrest` = the resting HR the strap reports for the cycle. If that is missing, use the lowest 5-minute rolling mean of HR during the preceding sleep.
- `HRr` = `(HR − HRrest) / (HRmax − HRrest)`, clamped to [0, 1].

### 7.3 Strain (0–21)

- Banister TRIMP over the cycle: `TRIMP = Σ Δt_minutes × HRr × a × e^(b × HRr)`.
  - Male coefficients: `a = 0.64`, `b = 1.92`.
  - Female coefficients: `a = 0.86`, `b = 1.67`.
- `Strain = 21 × (1 − e^(−TRIMP / k))`, starting with `k = 100`.
- Minutes without an HR sample add nothing. If HR coverage of the cycle is below 50%, strain is shown as partial, together with the coverage percentage.

### 7.4 Sleep performance (%)

- `sleepNeed = sleepNeedBaselineHours + max(0, previousCycleStrain − 10) × 3 min + 0.33 × (sum of shortfall over the last 3 nights)`, capped at `sleepNeedBaselineHours + 2 h`.
- `sleepPerformance = min(100, asleepDuration / sleepNeed × 100)`.
- Uses the strap's own sleep stages.
- A night the strap did not stage gives "not available".

### 7.5 Recovery (0–100%)

- **Valid night:** a main sleep with strap sleep stages, at least 3 h asleep, and at least one HRV value.
- Baselines: a 30-night rolling mean and standard deviation of ln(overnight HRV) and of resting HR. Only valid nights count, and the current night is excluded.
- Components:
  - `hrvComponent = clamp(50 + 25 × z_lnHRV, 0, 100)`
  - `restingHeartRateComponent = clamp(50 − 25 × z_RHR, 0, 100)`
  - `sleepComponent = sleepPerformance`
- `Recovery = round(0.5 × hrvComponent + 0.2 × restingHeartRateComponent + 0.3 × sleepComponent)`.
- Bands: green 67–100, yellow 34–66, red 0–33.
- The screen shows "calibrating" until 7 valid nights exist.
- Because recovery compares HRV only with the owner's own baseline, the unknown HRV statistic does not affect it.

### 7.6 Stress

- Uses the strap's own 0–100 stress values. Oxygen adds no new algorithm.
- Shown as a daily average, plus time spent in each band: relaxed 0–39, normal 40–59, medium 60–79, high 80–100.

### 7.7 Workout heart-rate zones

Five zones by % of HRmax: 50–60, 60–70, 70–80, 80–90 and 90–100.

### 7.8 Missing data

Any score whose inputs are missing shows "not available" plus the reason, for example "no sleep recorded" or "HR coverage 32%". Oxygen never shows a zero or a guessed value in place of a missing one.

## 8. Workouts (sub-projects 4 and 5, outline)

### 8.1 Import (sub-project 4)

- Add workout summary and workout detail fetch types to `ZeppKit`. They are written clean-room from a protocol spec, using Gadgetbridge's Zepp OS workout support as the factual reference, the same way OpenCircuit produced `docs/ZEPP_PROTOCOL.md`.
- Each imported workout is stored as a raw `WorkoutRecord`: sport, start, end, average HR, max HR, calories, plus HR detail if the strap provides it.
- `OxygenAnalytics` computes `WorkoutScores` from it: workout strain (the TRIMP model over the workout window) and time in each zone.

### 8.2 Start/stop (sub-project 5)

It starts with a time-boxed spike that answers three questions in order:

1. **Is it already decoded?** Do Gadgetbridge's Zepp OS workout service or OpenCircuit issue #227 already document start, pause, resume and end messages?
2. **How can the messages be captured?** An HCI log of Zepp starting a workout only shows AES ciphertext. Decrypting it needs the session key derived from Zepp's ephemeral ECDH key. The spike picks a working capture method.
3. **How does the strap behave?** Does the link have to stay up during a workout, and what happens on disconnect, pause and resume?

`WorkoutController` is a state machine:

```
idle → starting(sport) → active ⇄ paused → ending → importing → done
any state → failed(reason)
```

The live screen shows current HR, zone, elapsed time and accrued strain. HelioCore's live-stream decoding is the cross-check reference for the live values, alongside OpenCircuit's live HR.

### 8.3 Fallback if the spike fails: phone-side workouts

- Oxygen records the start and end times on the phone and computes workout strain from minute HR and live HR.
- What is lost: strap-side workout-mode sampling and the strap's VO₂max estimate.
- The data model and UI are the same as for strap-side workouts, so strap-side control can replace the fallback later without UI changes.

### 8.4 Out of v1

Phone GPS routes for outdoor workouts.

## 9. UI/UX (sub-project 3, outline)

### 9.1 Screens

- **Today:**
  - Cards for Recovery % (coloured by band), Strain (0–21, rising during the day) and Sleep performance %.
  - Stress timeline.
  - Resting HR and HRV against baseline.
  - Sync status line driven by the `SyncCoordinator` state. Pull down to sync.
- **Sleep:**
  - Hypnogram from the strap's stages.
  - Duration against need.
  - Overnight HR, HRV, SpO₂, skin temperature and respiratory rate.
  - A 7-night strip.
- **Workouts:**
  - A Start workout button, then a sport picker with recent sports first, then the live screen.
  - History list with workout strain and time in each zone.
- **Trends:** 7/30/90-day charts for recovery, strain, sleep performance, HRV and resting HR, with a shaded baseline band. Built with Swift Charts.
- **Settings** (gear icon on Today):
  - Profile inputs.
  - Auth key.
  - Strap battery and firmware.
  - Raw data export.
  - Re-sign status.

### 9.2 Re-sign guard

- Oxygen reads `ExpirationDate` from its own `embedded.mobileprovision`.
- Settings shows "Re-install within N days".
- A banner appears on Today when 2 days or fewer remain.
- A local notification is scheduled 24 hours before expiry, and rescheduled on every launch.
- If the file is missing (for example in the simulator), the status shows "unknown".

### 9.3 UX rules

- Tapping any score shows its inputs and how they combine.
- Missing data shows "not available" plus the reason.
- Dark mode is supported from the first build.
- Only SwiftUI and Swift Charts; no third-party UI libraries.
- Visual design (colours, typography, mockups) is decided in the sub-project 3 spec.

## 10. Error handling

### 10.1 SyncCoordinator failure reasons

| Reason | Trigger | Response |
|---|---|---|
| `bluetoothOff` | Central state is powered off | Banner with a link to Settings. `bluetoothPoweredOn` returns the coordinator to `idle`. |
| `bluetoothUnauthorized` | Bluetooth permission denied | Banner with a link to Settings. |
| `strapNotFound` | No strap seen within 15 s of scanning | Try again on the next launch or foreground. |
| `strapBusy` | Another app holds the connection, usually Zepp with Bluetooth still on | Show "Turn off Bluetooth for Zepp". Try again on the next launch or foreground. |
| `keyRejected` | The strap answers auth with `10 05 25` | Stop. Ask for a new key. Do not retry automatically. |
| `keyMissing` | No auth key is stored (first launch) | Show key entry. Do not scan. |
| `linkLost(state)` | Disconnect during any active state | Retry once after 10 s, restarting at `scanning`. If the retry fails too, `failed`. |
| `fetchTimeout(type)` | No data for that fetch type within 30 s | Retry once after 10 s, restarting at `scanning`. If the retry fails too, `failed`. |
| `persistFailed` | Writing to the store failed | The watermark does not move, so the round is fetched again on the next sync. Report the error. |

A retry restarts the whole sync. Each fetch starts at its type's watermark, so committed data is not fetched again. The one record that overlaps at the watermark is removed by de-duplication.

Oxygen only ever acks with `03 09` (keep on strap). It never sends `03 01`, so the strap never discards data because of Oxygen.

Ways out of `failed(reason)`:

- `syncRequested` → `scanning`, for every reason except `keyRejected` and `keyMissing`.
- `failed(keyRejected)` and `failed(keyMissing)` → `idle` only on `authKeyEntered`.
- `failed(bluetoothUnauthorized)` → `idle` on `bluetoothPoweredOn`.
- `failed(bluetoothOff)` → `idle` on `bluetoothPoweredOn`.

### 10.2 Transition log

- A fixed-size, exportable log with one line per state transition: timestamp, from-state, event and to-state.
- It is the main tool for debugging sync on the device.

## 11. Testing

- **OxygenAnalytics:** golden-file tests.
  - Synthetic fixtures with known results, for example constant HR over a fixed duration giving a TRIMP computed by hand.
  - The owner's exported days frozen as fixtures, with their expected scores.
- **SyncCoordinator and WorkoutController:** table-driven tests that cover every (state, event) pair and its expected next state. They run against a fake transport.
- **StrapSession:** tested end to end against upstream's `FakeZeppDevice`, a simulated strap, so no hardware is needed.
- **Upstream merges:** run the whole Kit test suite after every merge.
- **On the device:** a manual checklist for each sub-project.
  - Pair, then sync.
  - Kill the app in the middle of a sync.
  - Switch on airplane mode in the middle of a sync.
  - Turn Zepp's Bluetooth on and confirm `strapBusy`.
  - Re-install over the existing app and confirm the data is kept.

## 12. Sub-project 1: Foundation (detailed design)

### 12.1 Goal

A signed Oxygen build on the owner's iPhone that syncs the 13 history fetch types ZeppKit parses, shows what it has collected, and exports raw data for analytics development.

| Fetch type | Code | Fetch type | Code |
|---|---|---|---|
| activity | `0x01` | temperature | `0x2e` |
| manualHeartRate | `0x02` | sleepRespiratoryRate | `0x38` |
| pai | `0x0d` | restingHeartRate | `0x3a` |
| stressManual | `0x12` | maximumHeartRate | `0x3d` |
| stressAutomatic | `0x13` | sleepSession | `0x48` |
| bloodOxygenNormal | `0x25` | heartRateVariability | `0x49` |
| bloodOxygenSleep | `0x26` | | |

The `0x2c` statistics files are not fetched.

### 12.2 Out of scope

- Scores.
- Final UI.
- Workouts.
- HealthKit writes.
- Writing strap settings (HEALTH recording switches, alarms).
- Background wake-up sync, meaning a standing connection or CoreBluetooth state restoration. This moves to sub-project 3.
- Sub-project 1 syncs when the app becomes active and when Sync is tapped. The `bluetooth-central` background mode keeps a running sync alive when the phone locks.

### 12.3 Setup steps (on the personal MacBook)

1. **Tools.**
   - Install Xcode 26 from the Mac App Store. In Xcode → Settings → Accounts, add the owner's Apple ID. This creates a Personal Team.
   - Install XcodeGen with `brew install xcodegen`.
2. **Repository.**
   - Create the private repository `emanuelefalli/oxygen` as a mirror copy of `perezjuanj/OpenCircuit` (not a GitHub fork) and clone it.
   - Add the `upstream` remote.
   - Commit this spec to `docs/superpowers/specs/2026-10-06-oxygen-design.md`.
3. **Auth key.**
   - Extract the key by following OpenCircuit's `docs/HELIO_KEY_EXTRACTION.md`.
   - Keep the strap paired in Zepp.
   - Set iPhone Settings → Zepp → Bluetooth to off.
4. **iPhone.**
   - Connect the phone by cable and trust the Mac.
   - Turn on Developer Mode (Settings → Privacy & Security → Developer Mode), then restart.
5. **Smoke test on the Mac.**
   - Run upstream's `HelioVerify` against the strap with the key file, read-only, over the last 24 hours, saving the fetched rounds to a file outside the repository.
   - This proves that the key and the strap work before any app is signed, and it uses no App IDs.
   - The upstream app is not built: its HealthKit entitlement and widget extension cannot be signed with a Personal Team.
6. **Capability check.**
   - Oxygen's own target declares the `bluetooth-central` background mode.
   - The check passes when Oxygen signs and installs with the Personal Team, and a sync started in the foreground completes with the phone locked.
   - Record the result in section 14.
7. **App target.**
   - Generate the Oxygen project from `ios/Oxygen/project.yml`, with the bundle ID `com.emanuelefalli.oxygen`.
   - `ios/OxygenAnalytics` is created in sub-project 2, when it gets its first code.
   - On first launch, trust the developer certificate under Settings → General → VPN & Device Management.
8. **Wireless re-sign.**
   - In Xcode → Devices and Simulators, enable "Connect via network".
   - Each week afterwards, run Oxygen from Xcode over Wi-Fi to renew the profile for another 7 days.
   - App data is kept as long as the bundle ID stays the same and the app is never deleted.

### 12.4 Components

**`SyncCoordinator` (`ios/Oxygen/Sync/`)**

- States:

  ```
  idle → scanning → connecting → authenticating → preparing → fetching(type) → persisting(type) → fetching(next type) … → idle
  linkLost / connectionFailed / fetchTimedOut → waitingForRetry(reason) → scanning   (once per sync)
  any state → failed(reason)
  ```

  `preparing` covers the read-only steps after auth plus the clock: services list, set time, device info and battery.
- Events: `syncRequested`, `authKeyEntered`, `authKeyMissing`, `bluetoothPoweredOn`, `bluetoothPoweredOff`, `bluetoothUnauthorized`, `strapDiscovered`, `strapBusyDetected`, `scanTimedOut`, `connected`, `connectionFailed`, `authSucceeded`, `authRejected`, `sessionPrepared`, `fetchProgressed(type)`, `fetchCompleted(type)`, `fetchTimedOut(type)`, `linkLost`, `persistSucceeded(type)`, `persistFailed(type)`, `retryTimerFired`.
- The coordinator is a pure function from (state, event) to (next state, effects). A separate `SyncRunner` executes the effects.
- The exits from `failed(reason)` are listed in section 10.1.
- Fetch types run one at a time, in ascending code order (section 12.1).
- **`persisting(type)`:** one SwiftData save commits the type's new rounds and its new watermark. The watermark only moves when that save succeeds.
- **Watermark:** the newest record timestamp decoded from the type's committed rounds. The next fetch starts at the watermark (inclusive). With no watermark yet, it starts at now minus 7 days.
- **Timeouts:** scan 15 s; fetch 30 s without progress; retry delay 10 s. Only one retry per sync.
- **Where the strap code comes from:**
  - `StrapConnection` is adapted from upstream `HelioConnection`, `StrapSession` from `HelioSession`, and `StrapKeyStore` from `HelioKeyStore`.
  - Each is rewritten in Oxygen's style, and records the upstream source path and commit in a header comment.
  - `StrapSession` is a pure input-to-output state machine around ZeppKit, like ZeppKit's own `ZeppAuthenticator` and `ZeppHistoryFetch`.

**`RawStore` (`ios/Oxygen/Sources/Store/`)**

- SwiftData models:
  - `StrapHistoryRound`: fetch type code, round start, payload, payload SHA-256 and received time.
  - `StrapFetchWatermark`: one per fetch type.
- For each fetch type it returns the decoded record count, the oldest record time and the newest record time.
- It lists decoded, de-duplicated records and raw rounds for export.

**Foundation screen (`ios/Oxygen/Screens/`)** shows, on a single screen:

- The SyncCoordinator state line.
- A Sync button.
- A table with one row per record type: count, oldest and newest.
- The time of the last successful sync.
- Auth key entry, stored in the Keychain by `StrapKeyStore`. A rejected key is remembered across launches until a new key is entered.
- The re-sign status.
- An Export button.

**Re-sign guard (`ios/Oxygen/ResignGuard/`)**

- Find the XML plist inside `embedded.mobileprovision` between `<?xml` and `</plist>`.
- Decode it with `PropertyListSerialization` and read `ExpirationDate`.
- Drive the banner and the local notification as described in section 9.2.

**Exporter (`ios/Oxygen/Export/`)**

- Writes a folder named `oxygen-export-<yyyyMMdd-HHmmss>/` containing:
  - One CSV per fetch type. Columns are the decoded record's fields, and timestamps are ISO-8601 UTC.
  - `rounds.csv` with every raw round and its payload in hex, so the data can be decoded again later.
  - `manifest.json` with the app version, upstream Kit commit hash, export time, `TimeZone.current.identifier` and the record count per type.
  - `transition-log.txt`.
- The folder is zipped with `NSFileCoordinator` using the `.forUploading` option, so no third-party library is needed, and shared through the share sheet.

### 12.5 Acceptance criteria

1. Oxygen installs on the owner's iPhone with the free Personal Team and launches.
2. After a night of wear, a sync reaches `idle`, and these types show a non-zero count: activity, sleepSession, heartRateVariability, restingHeartRate, temperature and stressAutomatic. The other types may legitimately be zero.
3. Every failure reason in section 10.1 that can be reproduced on the bench is reproduced once. At minimum: `bluetoothOff`, `strapBusy` (Zepp Bluetooth on) and `linkLost` (strap out of range). Each one shows the documented response.
4. Seven consecutive days are synced. The only gaps in activity records are intervals when the strap was not worn or was charging.
5. An export opens on the Mac with one CSV per record type and a manifest whose counts match the Foundation screen.
6. Re-installing from Xcode over the existing app keeps all data.
7. The re-sign guard shows the correct number of days remaining, cross-checked against the profile's expiry shown in Xcode.
8. The capability check result (step 6) is recorded in section 14.

## 13. Sub-project roadmap

| # | Sub-project | Depends on | Risk |
|---|---|---|---|
| 1 | Foundation: private copy, build, install, sync, raw export | none | Low |
| 2 | Analytics engine: `OxygenAnalytics` with golden-file tests on exported data | 1 | Medium (calibration) |
| 3 | UI/UX: Today, Sleep, Workouts, Trends, Settings | 2 | Low |
| 4 | Workout import from the strap | 1 | Medium |
| 5 | Workout start/stop: spike, then strap-side control or the phone-side fallback | 4 | High |

Each sub-project gets its own spec, implementation plan and build cycle.

## 14. Risks and open items

| Item | Mitigation or resolution point |
|---|---|
| Workout start protocol unknown | Spike in sub-project 5. The phone-side fallback (section 8.3) guarantees the two-tap workout either way. |
| HealthKit with a free account | Confirmed not signable (OpenCircuit roadmap). No Apple Health export in v1. |
| Background mode `bluetooth-central` with a free account | Checked in sub-project 1 step 6. If it fails, sync runs in the foreground only. Daily app opens are enough given the strap's buffer. |
| Capability check result | Recorded here during sub-project 1 step 6. |
| Missed weekly re-sign | Re-sign guard (section 9.2). |
| Upstream ZeppKit API changes | Oxygen touches ZeppKit only through `StrapSession` and `StrapRecordDecoder`. Monthly merges run the ZeppKit and Oxygen tests. |
| Upstream fixes to `ios/OpenCircuit/Helio/` | Not merged automatically. Diff the folder monthly since the recorded commit and port fixes by hand. |
| Personal health data in git | Private repository. Exports and captures are gitignored. |
| Auth key invalidated (unpaired in Zepp, factory reset) | `keyRejected` state. Re-extract the key with the same procedure. If that procedure stops working, HelioCore's Zepp cloud login is the reference for fetching it. |
| A firmware update through Zepp changes the protocol | Turn Zepp's Bluetooth on only for updates. Run the sub-project 1 smoke checklist after every firmware update. |
| Unknown HRV statistic | Recovery uses HRV only relative to the owner's own baseline. |
| Licence | PolyForm Noncommercial: personal use only. |

## 15. Sources

- OpenCircuit repository and README: https://github.com/perezjuanj/OpenCircuit
- OpenCircuit Helio Strap driver (issue #215): https://github.com/perezjuanj/OpenCircuit/issues/215
- OpenCircuit Zepp OS protocol and ZeppKit (PR #219): https://github.com/perezjuanj/OpenCircuit/pull/219
- OpenCircuit workout control (issue #227): https://github.com/perezjuanj/OpenCircuit/issues/227
- OpenCircuit strap measurement settings (issue #228): https://github.com/perezjuanj/OpenCircuit/issues/228
- Gadgetbridge Zepp OS support: https://gadgetbridge.org/basics/topics/zeppos/
- Gadgetbridge missing Zepp OS metrics (issue #5910): https://codeberg.org/Freeyourgadget/Gadgetbridge/issues/5910
- Gadgetbridge Helio Strap data gaps (issue #5986): https://codeberg.org/Freeyourgadget/Gadgetbridge/issues/5986
- Gadgetbridge auth key from the vendor server: https://gadgetbridge.org/basics/pairing/huami-xiaomi-server/
- Ridge (Helio Strap, Android): https://github.com/TheCommishDeuce/ridge-helio-strap
- Healthee (Helio Strap, Flutter): https://github.com/romitraj13/healthee
- HelioCore (Helio Strap, iOS, MIT): https://github.com/a9eelsh/HelioCore
- Apple developer membership comparison: https://developer.apple.com/support/compare-memberships/
- OpenCircuit roadmap: https://github.com/perezjuanj/OpenCircuit/blob/HEAD/docs/ROADMAP.md
- OpenCircuit Zepp OS protocol spec: https://github.com/perezjuanj/OpenCircuit/blob/HEAD/docs/ZEPP_PROTOCOL.md
- OpenCircuit Helio key extraction: https://github.com/perezjuanj/OpenCircuit/blob/HEAD/docs/HELIO_KEY_EXTRACTION.md
- OpenCircuitKit package manifest: https://github.com/perezjuanj/OpenCircuit/blob/HEAD/ios/OpenCircuitKit/Package.swift
- OpenCircuit XcodeGen spec: https://github.com/perezjuanj/OpenCircuit/blob/HEAD/ios/project.yml
- OpenCircuit Helio Strap in the app (PR #224): https://github.com/perezjuanj/OpenCircuit/pull/224

## 16. Changelog

- **2026-10-07, revision 2.** Written while planning sub-project 1, after reading OpenCircuit's package manifest, XcodeGen spec, PR #224 and protocol doc.
  - OpenCircuit's store and its CoreBluetooth and Keychain code live in the upstream app target, which Oxygen cannot link. Oxygen therefore owns `StrapConnection`, `StrapSession`, `StrapKeyStore` and `RawStore`. `KitStoreReader` is removed.
  - Acks are `03 09` only. The watermark moves only after the store save commits. Raw rounds are de-duplicated by (type, start, payload hash), and decoded records by (type, timestamp).
  - The smoke test uses `HelioVerify` on the Mac instead of building the upstream app.
  - HealthKit is confirmed paid-only, so the Apple Health toggle is removed. The capability check covers `bluetooth-central` only.
  - Oxygen has its own XcodeGen spec at `ios/Oxygen/project.yml`.
  - `StrapSession` is tested against `FakeZeppDevice`.
  - Added the `preparing` and `waitingForRetry` states, the `keyMissing` failure reason and the related events.
  - Background wake-up sync moves to sub-project 3.
  - The repository is a private copy, not a public fork.
