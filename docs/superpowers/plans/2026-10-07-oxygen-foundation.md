# Oxygen Sub-project 1 (Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A free-signed Oxygen build on the owner's iPhone. It syncs the Helio Strap's 13 history fetch types into its own store, shows what it collected, and exports raw data.

**Architecture:**
- A pure `SyncCoordinator` reducer decides every transition.
- `SyncRunner` executes the reducer's effects against three components:
  - `StrapConnection`: CoreBluetooth.
  - `StrapSession`: a pure input-to-output state machine around ZeppKit.
  - `RawStore`: SwiftData, holding append-only raw rounds plus one watermark per fetch type.
- ZeppKit makes every protocol decision. Oxygen never links code from the upstream app target.

**Tech Stack:** Swift (language mode 5), SwiftUI, SwiftData, Observation, CoreBluetooth, Security (Keychain), CryptoKit, UserNotifications, XcodeGen and Swift Testing. From upstream: the `ZeppKit` and `OpenCircuitKit` products of `ios/OpenCircuitKit`, plus `FakeZeppDevice`.

**Spec:** `docs/superpowers/specs/2026-10-06-oxygen-design.md` (revision 2), sections 5, 6, 9.2, 10, 11 and 12.

**Where this runs:**
- Everything runs on the owner's MacBook (macOS 26, Xcode 26), with the iPhone and the strap at hand.
- Tasks 1, 2, 14 and 15 need the owner, because they touch hardware, accounts or the Keychain of a real device.
- Tasks 3–13 can be run by an agent with Xcode on that Mac.

## Global Constraints

- **Toolchain:** Xcode 26.x and XcodeGen. iOS deployment target `17.0`. `SWIFT_VERSION: "5.0"`.
- **Signing:** bundle ID `com.emanuelefalli.oxygen`, signed with the free Personal Team.
  - One app target, and no app extensions.
  - No HealthKit entitlement.
  - Info.plist `UIBackgroundModes: [bluetooth-central]`.
- **Upstream files are never modified:** `ios/OpenCircuitKit/**`, `ios/OpenCircuit/**`, `ios/project.yml`, `desktop/**`, and upstream's own files under `docs/`.
  - Nothing from `ios/OpenCircuit/` is linked or compiled into Oxygen.
  - The one exception: the test target compiles `ios/OpenCircuitKit/Sources/ZeppKitTesting/FakeZeppDevice.swift`, which is upstream's own pattern.
- **Dependencies:** no third-party dependencies.
- **Adaptation headers:** a file adapted from upstream app-target code starts with exactly one comment line: `// Adapted from <upstream path> at upstream <40-character commit>.`
- **Timing:**
  - Scan timeout 15 s.
  - Auth timeout 10 s; it ends in `strapBusy`.
  - Each preparation step 5 s; the step is skipped.
  - Fetch timeout 30 s without progress.
  - Retry delay 10 s, one retry per sync.
- **Acks:** keep-on-device (`03 09`) only, never `03 01`. Never pass `--allow-delete` or `--allow-write` to HelioVerify.
- **Fetch order:** the 13 types in ascending code order (spec section 12.1). `0x2c` is never fetched.
- **Watermark (upstream rule):**
  - After a committed round, the watermark is the round's `nextSince` (last record + 1 minute). It never passes now (floored to the minute) and never moves backward.
  - A fetch starts at the watermark floored to the minute, but never more than `HelioFetchPlan.maxLookback` (30 days) back.
  - With no watermark, or one more than `HelioFetchPlan.futureTolerance` (5 min) ahead of now, a fetch starts at now − `HelioFetchPlan.firstSyncLookback` (7 days).
  - Reuse those upstream constants and `HelioFetchPlan.floorToMinute`. Do not copy their values.
- **Time:**
  - Timestamps are stored as `Date`.
  - CSV files use ISO-8601 UTC without fractional seconds (`2026-10-07T06:42:00Z`).
  - The transition log uses milliseconds (`2026-10-07T06:42:13.512Z`).
  - Export folder names use UTC.
- **Keychain:**
  - Service `com.emanuelefalli.oxygen.strap-auth-key`.
  - Accounts `auth-key` and `auth-key-rejected`.
  - Accessibility `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
  - The key is never logged, exported or displayed after it is saved.
- **No health data or auth key in git:**
  - The key lives at `~/.oxygen/helio-auth-key.txt`.
  - Captures go in `~/oxygen-captures/`.
  - Exports leave the phone only through the share sheet.
- **Code style (owner's rules):**
  - Descriptive names. No abbreviations except industry-standard ones (BLE, CSV, UTC, HR, PAI, SHA).
  - Hardware-facing types are prefixed `Strap`.
  - One primary type per file, named after it. Small supporting enums may share the file.
  - Early returns.
  - No comments except adaptation headers and protocol facts a reader cannot infer.
  - No dead or commented-out code.
  - No force unwraps outside tests.
- **Tests:** Swift Testing (`import Testing`, `@testable import Oxygen`).
  - Run all tests: `xcodebuild test -project ios/Oxygen/Oxygen.xcodeproj -scheme Oxygen -destination 'platform=iOS Simulator,name=iPhone 17'`.
  - Run one suite by appending `-only-testing:OxygenTests/<SuiteName>`.
  - If that simulator is missing, use the first iPhone listed by `xcrun simctl list devices available`.

## Review Focus

These are failure modes the spec implies but no single feature test exercises. Each has a pinned test in the task named:

1. **The app is killed or the phone restarts mid-sync.** The next sync must resume from the watermarks with no duplicate records and no gap. Pinned by Task 7 `watermarkNeverMovesBackward` and Task 10 `secondSyncAddsNoDuplicateRecords`.
2. **A second sync trigger arrives while one is running** (the app becomes active while Sync was tapped). It must be ignored. Pinned by the Task 4 rows `fetchingSyncRequestedIsIgnored` and `scanningSyncRequestedIsIgnored`.
3. **Bluetooth is switched off mid-fetch.** The state becomes `failed(bluetoothOff)` and the in-flight type's watermark does not move. Pinned by the Task 4 generic rule `bluetoothPoweredOffInEveryActiveStepFails` and Task 10 `bluetoothOffMidFetchKeepsWatermark`.
4. **The strap has no data for a type** (manual HR, manual stress). The fetch completes with zero rounds and the sync continues. Pinned by Task 9 `fetchOfEmptyTypeCompletesWithNoRounds`.
5. **Export with an empty store, or with the phone in a non-UTC time zone.** All 13 CSVs are still written with headers, the counts are 0, and timestamps end in `Z`. Pinned by Task 12 `emptyStoreExportsHeadersOnly` and `timestampsAreUTCInAnyTimeZone`.

---

## File Map

| Path | Responsibility |
|---|---|
| `ios/Oxygen/project.yml` | XcodeGen spec for the `Oxygen` app and `OxygenTests` |
| `ios/Oxygen/.gitignore` | Ignores the generated project, `Generated/` and `Signing.xcconfig` |
| `ios/Oxygen/scripts/record-upstream-commit.sh` | Writes `BuildConstants.swift` from `git merge-base HEAD upstream/HEAD` |
| `ios/Oxygen/Sources/App/BuildConstants.swift` | `upstreamKitCommit` (generated, committed) |
| `ios/Oxygen/Sources/App/OxygenApp.swift` | Composition root |
| `ios/Oxygen/Sources/Sync/StrapFetchType.swift` | The 13 fetch types, sync order, display names, file names |
| `ios/Oxygen/Sources/Sync/SyncState.swift` | `SyncState`, `SyncPhase`, `SyncStep`, `SyncFailureReason` |
| `ios/Oxygen/Sources/Sync/SyncEvent.swift` | `SyncEvent`, `SyncEffect`, `SyncTimer`, `SyncTransition` |
| `ios/Oxygen/Sources/Sync/SyncCoordinator.swift` | Pure reducer and `initialState` |
| `ios/Oxygen/Sources/Sync/StrapSession.swift` | Pure ZeppKit session state machine |
| `ios/Oxygen/Sources/Sync/FetchedRound.swift` | One history round as received from the session |
| `ios/Oxygen/Sources/Sync/StrapCharacteristic.swift` | `typealias StrapCharacteristic = ZeppCharacteristic` |
| `ios/Oxygen/Sources/Sync/StrapConnecting.swift` | Connection protocol and `StrapConnectionEvent` |
| `ios/Oxygen/Sources/Sync/StrapConnection.swift` | CoreBluetooth implementation |
| `ios/Oxygen/Sources/Sync/SyncTimerScheduling.swift` | Timer protocol and its `Task`-based implementation |
| `ios/Oxygen/Sources/Sync/SyncRunner.swift` | Effect executor; the single entry point for all inputs |
| `ios/Oxygen/Sources/Sync/LastSyncRecord.swift` | Last successful sync time (UserDefaults) |
| `ios/Oxygen/Sources/Log/SyncLogDescription.swift` | `logDescription` for states and events |
| `ios/Oxygen/Sources/Log/TransitionLog.swift` | Fixed-size line buffer |
| `ios/Oxygen/Sources/Log/TransitionLogRecorder.swift` | Appends to the log and writes `TransitionLogFile` |
| `ios/Oxygen/Sources/Keys/StrapAuthKey.swift` | Key parsing |
| `ios/Oxygen/Sources/Keys/StrapKeyStore.swift` | Keychain storage and the rejection mark |
| `ios/Oxygen/Sources/Store/StrapHistoryRound.swift` | SwiftData model for raw rounds |
| `ios/Oxygen/Sources/Store/StrapFetchWatermark.swift` | SwiftData model for watermarks |
| `ios/Oxygen/Sources/Store/StoredRound.swift` | Value type plus SHA-256 identity |
| `ios/Oxygen/Sources/Store/RawStore.swift` | `RawStoring` protocol and its SwiftData implementation |
| `ios/Oxygen/Sources/Decode/StrapRecordDecoder.swift` | Decodes a round with ZeppKit's parser |
| `ios/Oxygen/Sources/Decode/RecordDeduplicator.swift` | Unique by (type, timestamp); the later receipt wins |
| `ios/Oxygen/Sources/Decode/WatermarkRule.swift` | Fetch start and watermark advance, built on upstream's `HelioFetchPlan` constants |
| `ios/Oxygen/Sources/ResignGuard/ProvisioningProfileReader.swift` | Reads `ExpirationDate` |
| `ios/Oxygen/Sources/ResignGuard/ResignStatus.swift` | Status from the expiry date and now |
| `ios/Oxygen/Sources/ResignGuard/ResignReminder.swift` | Local notification 24 h before expiry |
| `ios/Oxygen/Sources/Export/CSVWriter.swift` | RFC 4180 rendering |
| `ios/Oxygen/Sources/Export/ExportManifest.swift` | `manifest.json` model |
| `ios/Oxygen/Sources/Export/ExportBundleWriter.swift` | Folder, files and zip |
| `ios/Oxygen/Sources/Screens/SyncStatusText.swift` | Status line copy |
| `ios/Oxygen/Sources/Screens/RecordSummary.swift` | One row per fetch type |
| `ios/Oxygen/Sources/Screens/ResignStatusText.swift` | Re-sign line and banner copy |
| `ios/Oxygen/Sources/Screens/FoundationScreen.swift` | SwiftUI view |
| `ios/Oxygen/Tests/…` | One test file per source file under test, named `<Type>Tests.swift` |
| `docs/superpowers/notes/2026-10-07-upstream-api-map.md` | Upstream API facts that later tasks consume |

---

### Task 1: Workstation, private repository, key and smoke test (owner)

**Files:**
- Create: `docs/superpowers/specs/2026-10-06-oxygen-design.md` (copy of the approved spec)
- Create: `docs/superpowers/plans/2026-10-07-oxygen-foundation.md` (this plan)

**Interfaces:**
- Produces:
  - Repository at `~/Developer/oxygen` with remotes `origin` (private) and `upstream`.
  - Key file `~/.oxygen/helio-auth-key.txt`.
  - Capture `~/oxygen-captures/helioverify-first-sync.json`.

- [ ] **Step 1: Install and check the tools**

Install Xcode 26 from the App Store, then open it once so it installs its components. Then run:

```bash
xcodebuild -version
brew install xcodegen && xcodegen --version
```

Expected: `Xcode 26.` followed by a minor version, then an XcodeGen version line.

- [ ] **Step 2: Add the Apple ID**

In Xcode → Settings → Accounts, add your Apple ID.

Expected: a team named "<your name> (Personal Team)" appears.

- [ ] **Step 3: Create the private repository**

On github.com, create an empty **private** repository `emanuelefalli/oxygen` with no README and no licence. Then run:

```bash
mkdir -p ~/Developer && cd ~/Developer
git clone https://github.com/perezjuanj/OpenCircuit.git oxygen && cd oxygen
git remote rename origin upstream
git remote set-head upstream --auto
git remote add origin https://github.com/emanuelefalli/oxygen.git
git push -u origin HEAD:main
git checkout -B main --track origin/main
git remote -v
```

Expected: `origin` points to `emanuelefalli/oxygen` and `upstream` points to `perezjuanj/OpenCircuit`. `git log -1 upstream/HEAD` prints a commit.

- [ ] **Step 4: Commit the spec and the plan**

The `docs/superpowers/` folders don't exist upstream, so this step creates them.

1. Download both files from the chat on the MacBook: `2026-10-06-oxygen-design.md` and `2026-10-07-oxygen-foundation.md`. They land in `~/Downloads`.
2. Run:

```bash
cd ~/Developer/oxygen
mkdir -p docs/superpowers/specs docs/superpowers/plans
cp ~/Downloads/2026-10-06-oxygen-design.md docs/superpowers/specs/
cp ~/Downloads/2026-10-07-oxygen-foundation.md docs/superpowers/plans/
ls docs/superpowers/specs docs/superpowers/plans
git add docs/superpowers
git commit -m "docs: add Oxygen design spec and foundation plan"
git push
```

Expected: `ls` lists one file in each folder, and `git push` ends with `main -> main`.

- [ ] **Step 5: Extract the auth key**

The key is saved in a hidden folder in your home folder, `~/.oxygen/`, outside the repository so git can never commit it.

1. In a browser on the MacBook, sign in at `https://watchface.zepp.com/` with your Zepp account. The strap must already be paired and synced in the Zepp app.
2. Open the developer console. In Safari, first turn on Settings → Advanced → "Show features for web developers", then press `Cmd+Option+C`. In Chrome, press `Cmd+Option+J`.
3. Copy the snippet from the "Zepp watchface website" section of `https://gadgetbridge.org/basics/pairing/huami-xiaomi-server/`. Paste it into the console and press Enter. If Chrome asks, type `allow pasting` first.
4. In the output, find the Helio Strap entry. Inside its `additionalInfo`, copy only the value after `"auth_key":`: the 32 characters between the quotes, without the quotes.
5. In Terminal, while the key is still on the clipboard:

```bash
mkdir -p ~/.oxygen && chmod 700 ~/.oxygen
pbpaste > ~/.oxygen/helio-auth-key.txt && chmod 600 ~/.oxygen/helio-auth-key.txt
grep -Eic '^(0x)?[0-9a-f]{32}$' ~/.oxygen/helio-auth-key.txt
```

Expected: `1`. If you get `0`, the clipboard held extra characters. Run `open -e ~/.oxygen/helio-auth-key.txt`, leave only the 32 characters on one line, save, and run the `grep` line again.

If the device list in step 4 is empty, sync the strap in Zepp and run the snippet again.

- [ ] **Step 6: Release the strap from Zepp**

On the iPhone, set Settings → Zepp → Bluetooth to off. Leave the strap paired inside Zepp.

- [ ] **Step 7: Run the HelioVerify smoke test, read-only**

```bash
cd ~/Developer/oxygen/ios/OpenCircuitKit
swift run HelioVerify --help
mkdir -p ~/oxygen-captures
swift run HelioVerify --key-file ~/.oxygen/helio-auth-key.txt --since-hours 24 --out ~/oxygen-captures/helioverify-first-sync.json
```

- Use the flag spellings that `--help` prints. Never add `--allow-delete` or `--allow-write`.
- Allow the macOS Bluetooth prompt for Terminal.
- Expected: authentication succeeds and the output file is non-empty JSON. Check with `python3 -m json.tool ~/oxygen-captures/helioverify-first-sync.json | head`.

- [ ] **Step 8: Turn on Developer Mode on the iPhone**

Connect the iPhone by cable and trust the Mac. Then go to Settings → Privacy & Security → Developer Mode → On, and restart.

Expected: after the restart, the iPhone asks you to confirm Developer Mode.

---

### Task 2: Upstream API map (owner, or an agent with read access to the clone)

**Files:**
- Create: `docs/superpowers/notes/2026-10-07-upstream-api-map.md`

**Interfaces:**
- Consumes: the clone from Task 1.
- Produces: one table row per question below, each answered with exact Swift signatures or values and `file:line` sources. Tasks 3, 8, 9 and 14 read it.

- [ ] **Step 1: Run the upstream test baseline**

Run: `swift test --package-path ios/OpenCircuitKit`

Expected: all tests pass. Record the passed-test count in row 0.

- [ ] **Step 2: Fill the API map**

Read `ios/OpenCircuitKit/Sources/ZeppKit/`, `ios/OpenCircuitKit/Sources/ZeppKitTesting/`, `ios/OpenCircuitKit/Tests/ZeppKitTests/`, `ios/OpenCircuit/Helio/` and `ios/project.yml`. Write a table with columns `| # | Question | Answer | Source |`, with these rows in this order:

| # | Question |
|---|---|
| 0 | Upstream commit (`git rev-parse upstream/HEAD`) and the upstream test count from Step 1 |
| 1 | How to build a `ZeppAuthKey` from 16 bytes |
| 2 | How to start auth and feed it notifications. What signals success (`10 05 01`) and rejection (`10 05 25`) |
| 3 | GATT service and characteristic UUIDs ZeppKit writes to and subscribes to. Write type (with or without response). Which MTU or maximum write length input ZeppKit needs |
| 4 | Post-auth calls for the services list, set time (inputs: date, time zone), device info and battery. What each one returns |
| 5 | How to start a history fetch for one `ZeppFetchType` from a start timestamp. How progress, round completion and "no more rounds" are signalled. How the `.keepOnDevice` ack is issued |
| 6 | What a completed round contains: type, round start timestamp and payload bytes, with the exact type and property names |
| 7 | `ZeppFetchType` case names for the 13 codes in spec section 12.1 |
| 8 | For each of the 13 types: the `ZeppRecordParser` entry point (input, output type), the output's property names in declaration order, and which property is the record timestamp |
| 9 | For each of the 13 types: one upstream test vector in `ZeppKitTests` (file, test name, payload bytes, round start), with its expected record count, first timestamp and first-record property values |
| 10 | `FakeZeppDevice`: initializer (key, seeded history per type), how to feed it phone writes, how to read its notifications, and whether a keep-ack (`03 09`) leaves rounds offered again |
| 11 | `HelioConnection`: scan strategy (service UUIDs, or name matching with `ZeppDeviceModel.match`), how "strap busy" is detected, and the `CBCentralManager` options |
| 12 | `HelioFetchPlan` or `HelioSyncPolicy`: any per-type rule for the fetch start that differs from "start at the watermark" |
| 13 | `OpenCircuitTests` target dependencies in `ios/project.yml` (which package products the test bundle links next to `FakeZeppDevice.swift`) |
| 14 | HelioVerify flag spellings confirmed in Task 1 Step 7 |

Every answer cell is filled. If a fact does not exist upstream, write "not present" plus what upstream does instead.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/notes/2026-10-07-upstream-api-map.md
git commit -m "docs: record upstream ZeppKit API map for Oxygen"
```

---

### Task 3: Oxygen project skeleton that signs and installs

**Files:**
- Create: `ios/Oxygen/project.yml`
- Create: `ios/Oxygen/.gitignore`
- Create: `ios/Oxygen/scripts/record-upstream-commit.sh`
- Create: `ios/Oxygen/Sources/App/BuildConstants.swift` (generated by the script)
- Create: `ios/Oxygen/Sources/App/OxygenApp.swift`
- Create: `ios/Oxygen/Signing.xcconfig` (gitignored)
- Test: `ios/Oxygen/Tests/BuildConstantsTests.swift`

**Interfaces:**
- Consumes: API map row 13.
- Produces:
  - `enum BuildConstants { static let upstreamKitCommit: String }`.
  - The `Oxygen` scheme with the `OxygenTests` test target.

- [ ] **Step 1: Write `ios/Oxygen/project.yml`**

```yaml
name: Oxygen
options:
  bundleIdPrefix: com.emanuelefalli
  deploymentTarget:
    iOS: "17.0"
configFiles:
  Debug: Signing.xcconfig
  Release: Signing.xcconfig
settings:
  base:
    SWIFT_VERSION: "5.0"
    CODE_SIGN_STYLE: Automatic
packages:
  OpenCircuitKit:
    path: ../OpenCircuitKit
targets:
  Oxygen:
    type: application
    platform: iOS
    sources:
      - path: Sources
    dependencies:
      - package: OpenCircuitKit
        product: OpenCircuitKit
      - package: OpenCircuitKit
        product: ZeppKit
    info:
      path: Generated/Info.plist
      properties:
        CFBundleDisplayName: Oxygen
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        UILaunchScreen: {}
        NSBluetoothAlwaysUsageDescription: "Oxygen connects to your Helio Strap to sync your health data."
        UIBackgroundModes: [bluetooth-central]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.emanuelefalli.oxygen
  OxygenTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests
      - path: ../OpenCircuitKit/Sources/ZeppKitTesting/FakeZeppDevice.swift
    dependencies:
      - target: Oxygen
schemes:
  Oxygen:
    build:
      targets:
        Oxygen: all
        OxygenTests: [test]
    test:
      targets: [OxygenTests]
```

API map row 13 confirms that the test bundle needs no extra package products. It compiles `FakeZeppDevice.swift` from source, so ZeppKit resolves against the app's single copy.

- [ ] **Step 2: Write `ios/Oxygen/.gitignore`**

```
Oxygen.xcodeproj/
Generated/
Signing.xcconfig
```

- [ ] **Step 3: Write the commit recorder script, then run it**

`ios/Oxygen/scripts/record-upstream-commit.sh`:
- Starts with `#!/bin/sh` and `set -eu`.
- Resolves `commit=$(git merge-base HEAD upstream/HEAD)`.
- Writes `ios/Oxygen/Sources/App/BuildConstants.swift`, relative to the repository root, with exactly this content:

```swift
enum BuildConstants {
    static let upstreamKitCommit = "<the 40-character commit>"
}
```

Then run:

```bash
chmod +x ios/Oxygen/scripts/record-upstream-commit.sh
ios/Oxygen/scripts/record-upstream-commit.sh
```

Expected: `BuildConstants.swift` contains a 40-character hex commit.

- [ ] **Step 4: Write the failing test**

`ios/Oxygen/Tests/BuildConstantsTests.swift`:

```swift
import Testing
@testable import Oxygen

struct BuildConstantsTests {
    @Test func upstreamCommitIsFullSHA1() {
        let commit = BuildConstants.upstreamKitCommit
        #expect(commit.count == 40)
        #expect(commit.allSatisfy { "0123456789abcdef".contains($0) })
    }
}
```

`ios/Oxygen/Sources/App/OxygenApp.swift`: an `@main struct OxygenApp: App` whose `WindowGroup` shows `Text("Oxygen")`. Task 14 replaces the body.

- [ ] **Step 5: Create the signing config, generate the project and run the tests**

- Generate the project: `xcodegen generate --spec ios/Oxygen/project.yml`.
- Find the Personal Team ID:
  - Open `ios/Oxygen/Oxygen.xcodeproj`.
  - On the Oxygen target, open Signing & Capabilities and choose your Personal Team.
  - Read the team ID from Build Settings → Development Team.
- Write `ios/Oxygen/Signing.xcconfig` containing `DEVELOPMENT_TEAM = <that ID>`.
- Regenerate, then run all tests (Global Constraints).

Expected: `** TEST SUCCEEDED **`, with 1 test passed.

- [ ] **Step 6: Install on the iPhone**

- In Xcode, select the iPhone as the run destination and Run.
- On the phone, trust the developer under Settings → General → VPN & Device Management, then Run again.
- Expected: Oxygen opens and shows "Oxygen". Signing with `bluetooth-central` succeeded, which is part 1 of the capability check.
- Then in Window → Devices and Simulators, select the iPhone and tick "Connect via network".

- [ ] **Step 7: Commit**

```bash
git add ios/Oxygen
git commit -m "feat(oxygen): add XcodeGen project skeleton that signs with a Personal Team"
```

---

### Task 4: Fetch types and the SyncCoordinator reducer

**Files:**
- Create: `ios/Oxygen/Sources/Sync/StrapFetchType.swift`
- Create: `ios/Oxygen/Sources/Sync/SyncState.swift`
- Create: `ios/Oxygen/Sources/Sync/SyncEvent.swift`
- Create: `ios/Oxygen/Sources/Sync/SyncCoordinator.swift`
- Test: `ios/Oxygen/Tests/StrapFetchTypeTests.swift`
- Test: `ios/Oxygen/Tests/SyncCoordinatorTests.swift`

**Interfaces:**
- Produces:

```swift
enum StrapFetchType: UInt8, CaseIterable, Sendable {
    case activity = 0x01, manualHeartRate = 0x02, pai = 0x0d, stressManual = 0x12,
         stressAutomatic = 0x13, bloodOxygenNormal = 0x25, bloodOxygenSleep = 0x26,
         temperature = 0x2e, sleepRespiratoryRate = 0x38, restingHeartRate = 0x3a,
         maximumHeartRate = 0x3d, sleepSession = 0x48, heartRateVariability = 0x49
    static let syncOrder: [StrapFetchType]          // ascending rawValue
    var nextInSyncOrder: StrapFetchType? { get }
    var displayName: String { get }                 // table below
    var exportFileName: String { get }              // "\(self).csv"
}

enum SyncStep: Equatable, Sendable {
    case scanning, connecting, authenticating, preparing
    case fetching(StrapFetchType), persisting(StrapFetchType)
}
enum SyncFailureReason: Equatable, Sendable {
    case bluetoothOff, bluetoothUnauthorized, strapNotFound, strapBusy, keyRejected, keyMissing
    case linkLost(during: SyncStep), fetchTimeout(StrapFetchType), persistFailed(StrapFetchType)
}
enum SyncPhase: Equatable, Sendable {
    case idle, active(SyncStep), waitingForRetry(SyncFailureReason), failed(SyncFailureReason)
}
struct SyncState: Equatable, Sendable { var phase: SyncPhase; var retryUsed: Bool }

enum SyncEvent: Equatable, Sendable {
    case syncRequested, authKeyEntered, authKeyMissing
    case bluetoothPoweredOn, bluetoothPoweredOff, bluetoothUnauthorized
    case strapDiscovered, strapBusyDetected, scanTimedOut, connected, connectionFailed
    case authSucceeded, authRejected, authTimedOut
    case preparationStepStarted, preparationStepTimedOut, sessionPrepared
    case fetchProgressed(StrapFetchType), fetchCompleted(StrapFetchType), fetchTimedOut(StrapFetchType)
    case linkLost, persistSucceeded(StrapFetchType), persistFailed(StrapFetchType), retryTimerFired
}
enum SyncTimer: Equatable, Hashable, Sendable { case scan, session, fetch, retry }
enum SyncEffect: Equatable, Sendable {
    case startScan, stopScan, connect, disconnect, authenticate, prepareSession, skipPreparationStep
    case fetch(StrapFetchType), persist(StrapFetchType)
    case armTimer(SyncTimer, seconds: Int), cancelTimer(SyncTimer)
    case markKeyRejected, recordSyncCompleted
}
struct SyncTransition: Equatable, Sendable { let nextState: SyncState; let effects: [SyncEffect] }

enum SyncCoordinator {
    static let scanTimeoutSeconds = 15
    static let authenticationTimeoutSeconds = 10
    static let preparationStepTimeoutSeconds = 5
    static let fetchTimeoutSeconds = 30
    static let retryDelaySeconds = 10
    static func initialState(hasKey: Bool, keyRejected: Bool) -> SyncState
    static func reduce(_ state: SyncState, _ event: SyncEvent) -> SyncTransition
}
```

`displayName` values:

| Case | Display name |
|---|---|
| activity | "activity" |
| manualHeartRate | "manual heart rate" |
| pai | "PAI" |
| stressManual | "manual stress" |
| stressAutomatic | "stress" |
| bloodOxygenNormal | "blood oxygen" |
| bloodOxygenSleep | "sleep blood oxygen" |
| temperature | "skin temperature" |
| sleepRespiratoryRate | "sleep respiratory rate" |
| restingHeartRate | "resting heart rate" |
| maximumHeartRate | "maximum heart rate" |
| sleepSession | "sleep" |
| heartRateVariability | "heart rate variability" |

- [ ] **Step 1: Write the failing fetch type tests**

```swift
struct StrapFetchTypeTests {
    @Test func syncOrderIsAscendingCodes() {
        #expect(StrapFetchType.syncOrder.map(\.rawValue) ==
                [0x01, 0x02, 0x0d, 0x12, 0x13, 0x25, 0x26, 0x2e, 0x38, 0x3a, 0x3d, 0x48, 0x49])
    }
    @Test func nextInSyncOrder() {
        #expect(StrapFetchType.temperature.nextInSyncOrder == .sleepRespiratoryRate)
        #expect(StrapFetchType.heartRateVariability.nextInSyncOrder == nil)
    }
    @Test func exportFileName() {
        #expect(StrapFetchType.heartRateVariability.exportFileName == "heartRateVariability.csv")
    }
}
```

- [ ] **Step 2: Write the failing reducer tests**

`SyncCoordinatorTests.swift` has five parts:

1. Helpers.
2. One parameterized test over the listed rows.
3. Generic-rule tests.
4. An "everything else is ignored" test.
5. `initialState` tests.

Helpers and generic expectations:

```swift
func state(_ phase: SyncPhase, retryUsed: Bool = false) -> SyncState { SyncState(phase: phase, retryUsed: retryUsed) }
func step(_ step: SyncStep, retryUsed: Bool = false) -> SyncState { state(.active(step), retryUsed: retryUsed) }

func expectedTeardown(_ step: SyncStep) -> [SyncEffect] {
    switch step {
    case .scanning: return [.cancelTimer(.scan), .stopScan]
    case .authenticating, .preparing: return [.cancelTimer(.session), .disconnect]
    case .fetching: return [.cancelTimer(.fetch), .disconnect]
    case .connecting, .persisting: return [.disconnect]
    }
}
let connectedSteps: [SyncStep] = [.connecting, .authenticating, .preparing, .fetching(.temperature), .persisting(.temperature)]
let allSteps: [SyncStep] = [.scanning] + connectedSteps
```

Listed rows, as `(name, state, event, next state, effects)`:

| Name | State | Event | Next state | Effects |
|---|---|---|---|---|
| idleSyncRequestedStartsScan | idle | syncRequested | step(.scanning) | [.startScan, .armTimer(.scan, seconds: 15)] |
| idleBluetoothPoweredOffFails | idle | bluetoothPoweredOff | failed(.bluetoothOff) | [] |
| idleBluetoothUnauthorizedFails | idle | bluetoothUnauthorized | failed(.bluetoothUnauthorized) | [] |
| scanningStrapDiscoveredConnects | step(.scanning) | strapDiscovered | step(.connecting) | [.cancelTimer(.scan), .stopScan, .connect] |
| scanningTimeoutFailsNotFound | step(.scanning) | scanTimedOut | failed(.strapNotFound) | [.stopScan] |
| scanningSyncRequestedIsIgnored | step(.scanning) | syncRequested | step(.scanning) | [] |
| connectingConnectedAuthenticates | step(.connecting) | connected | step(.authenticating) | [.authenticate, .armTimer(.session, seconds: 10)] |
| connectingFailureWaitsForRetry | step(.connecting) | connectionFailed | state(.waitingForRetry(.linkLost(during: .connecting)), retryUsed: true) | [.disconnect, .armTimer(.retry, seconds: 10)] |
| connectingFailureAfterRetryFails | step(.connecting, retryUsed: true) | connectionFailed | state(.failed(.linkLost(during: .connecting)), retryUsed: true) | [.disconnect] |
| authenticatingSuccessPrepares | step(.authenticating) | authSucceeded | step(.preparing) | [.cancelTimer(.session), .prepareSession] |
| authenticatingRejectedMarksKey | step(.authenticating) | authRejected | failed(.keyRejected) | [.cancelTimer(.session), .markKeyRejected, .disconnect] |
| authenticatingKeyMissingFails | step(.authenticating) | authKeyMissing | failed(.keyMissing) | [.cancelTimer(.session), .disconnect] |
| authenticatingBusyFails | step(.authenticating) | strapBusyDetected | failed(.strapBusy) | [.cancelTimer(.session), .disconnect] |
| authenticatingTimeoutFailsBusy | step(.authenticating) | authTimedOut | failed(.strapBusy) | [.disconnect] |
| preparingStepStartedArmsTimer | step(.preparing) | preparationStepStarted | same | [.armTimer(.session, seconds: 5)] |
| preparingStepTimeoutSkipsStep | step(.preparing) | preparationStepTimedOut | same | [.skipPreparationStep] |
| preparingDoneFetchesActivity | step(.preparing) | sessionPrepared | step(.fetching(.activity)) | [.cancelTimer(.session), .fetch(.activity), .armTimer(.fetch, seconds: 30)] |
| fetchingProgressRearmsTimer | step(.fetching(.temperature)) | fetchProgressed(.temperature) | same | [.armTimer(.fetch, seconds: 30)] |
| fetchingCompletedPersists | step(.fetching(.temperature)) | fetchCompleted(.temperature) | step(.persisting(.temperature)) | [.cancelTimer(.fetch), .persist(.temperature)] |
| fetchingTimeoutWaitsForRetry | step(.fetching(.temperature)) | fetchTimedOut(.temperature) | state(.waitingForRetry(.fetchTimeout(.temperature)), retryUsed: true) | [.cancelTimer(.fetch), .disconnect, .armTimer(.retry, seconds: 10)] |
| fetchingTimeoutAfterRetryFails | step(.fetching(.temperature), retryUsed: true) | fetchTimedOut(.temperature) | state(.failed(.fetchTimeout(.temperature)), retryUsed: true) | [.cancelTimer(.fetch), .disconnect] |
| fetchingSyncRequestedIsIgnored | step(.fetching(.temperature)) | syncRequested | same | [] |
| persistingSuccessFetchesNextType | step(.persisting(.temperature)) | persistSucceeded(.temperature) | step(.fetching(.sleepRespiratoryRate)) | [.fetch(.sleepRespiratoryRate), .armTimer(.fetch, seconds: 30)] |
| persistingLastTypeCompletesSync | step(.persisting(.heartRateVariability), retryUsed: true) | persistSucceeded(.heartRateVariability) | state(.idle) | [.disconnect, .recordSyncCompleted] |
| persistingFailureFails | step(.persisting(.temperature)) | persistFailed(.temperature) | failed(.persistFailed(.temperature)) | [.disconnect] |
| waitingRetryTimerScansAgain | state(.waitingForRetry(.linkLost(during: .connecting)), retryUsed: true) | retryTimerFired | step(.scanning, retryUsed: true) | [.startScan, .armTimer(.scan, seconds: 15)] |
| failedKeyRejectedIgnoresSync | failed(.keyRejected) | syncRequested | same | [] |
| failedKeyRejectedKeyEnteredIdles | failed(.keyRejected) | authKeyEntered | state(.idle) | [] |
| failedKeyMissingIgnoresSync | failed(.keyMissing) | syncRequested | same | [] |
| failedKeyMissingKeyEnteredIdles | failed(.keyMissing) | authKeyEntered | state(.idle) | [] |
| failedBluetoothOffPoweredOnIdles | failed(.bluetoothOff) | bluetoothPoweredOn | state(.idle) | [] |
| failedBluetoothUnauthorizedPoweredOnIdles | failed(.bluetoothUnauthorized) | bluetoothPoweredOn | state(.idle) | [] |

In this table, `failed(x)` means `state(.failed(x))`.

Generic rules, each a parameterized `@Test`:

- `linkLostInConnectedStepWaitsForRetry(step)` over `connectedSteps`, with `retryUsed: false`.
  - Next state: `state(.waitingForRetry(.linkLost(during: step)), retryUsed: true)`.
  - Effects: `expectedTeardown(step) + [.armTimer(.retry, seconds: 10)]`.
- `linkLostAfterRetryFails(step)` over `connectedSteps`, with `retryUsed: true`.
  - Next state: `state(.failed(.linkLost(during: step)), retryUsed: true)`.
  - Effects: `expectedTeardown(step)`.
- `bluetoothPoweredOffInEveryActiveStepFails(step)` over `allSteps`.
  - Next state: `state(.failed(.bluetoothOff))`.
  - Effects: `expectedTeardown(step)`.
- `bluetoothUnauthorizedInEveryActiveStepFails(step)` over `allSteps`.
  - Next state: `state(.failed(.bluetoothUnauthorized))`.
  - Effects: `expectedTeardown(step)`.
- `bluetoothEventsWhileWaitingForRetryFail`.
  - `waitingForRetry(.linkLost(during: .connecting))` with `retryUsed: true`, plus `bluetoothPoweredOff`: next state `state(.failed(.bluetoothOff), retryUsed: true)`, effects `[.cancelTimer(.retry)]`.
  - The same with `bluetoothUnauthorized`: next state `state(.failed(.bluetoothUnauthorized), retryUsed: true)`, effects `[.cancelTimer(.retry)]`.
- `syncRequestedAfterFailureScans(reason)` over `[.bluetoothOff, .bluetoothUnauthorized, .strapNotFound, .strapBusy, .linkLost(during: .connecting), .fetchTimeout(.temperature), .persistFailed(.temperature)]`, starting from `retryUsed: true`.
  - Next state: `step(.scanning)` (`retryUsed` resets to false).
  - Effects: `[.startScan, .armTimer(.scan, seconds: 15)]`.

Ignored pairs:

- `ignoredPairLeavesStateUnchanged` iterates the representative states × all events, and skips any pair that a listed row or a generic rule covers.
- Each remaining pair must return `SyncTransition(nextState: input, effects: [])`.
- Representative states, all with `retryUsed: false`:
  - `idle`
  - each of `allSteps`
  - `waitingForRetry(.linkLost(during: .connecting))`
  - `failed` with each of `.bluetoothOff`, `.bluetoothUnauthorized`, `.strapNotFound`, `.strapBusy`, `.keyRejected`, `.keyMissing`, `.persistFailed(.temperature)`.
- All events: every `SyncEvent` case. Type-carrying cases are instantiated once with `.temperature` and once with `.activity`.

`initialState`:

| hasKey | keyRejected | Result |
|---|---|---|
| false | false | `failed(.keyMissing)` |
| false | true | `failed(.keyMissing)` |
| true | true | `failed(.keyRejected)` |
| true | false | `idle` |

All four results have `retryUsed: false`.

- [ ] **Step 3: Run the tests and confirm they fail**

Run: the `StrapFetchTypeTests` and `SyncCoordinatorTests` suites.

Expected: compile failure, because the types are not defined yet.

- [ ] **Step 4: Implement the four source files**

- Use an exhaustive `switch` on `(state.phase, event)` with early returns for the rows and the generic rules.
- The final `default` returns the unchanged state with no effects.
- Teardown effects per step are exactly as `expectedTeardown` lists them.
- `retryUsed` changes only in three places: it becomes true when entering `waitingForRetry`, and false on `syncRequested` from `idle` or `failed`, and on the final `persistSucceeded`.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: the same two suites.

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/Oxygen/Sources/Sync ios/Oxygen/Tests
git commit -m "feat(oxygen): add fetch types and pure SyncCoordinator reducer"
```

---

### Task 5: Transition log

**Files:**
- Create: `ios/Oxygen/Sources/Log/SyncLogDescription.swift`
- Create: `ios/Oxygen/Sources/Log/TransitionLog.swift`
- Create: `ios/Oxygen/Sources/Log/TransitionLogRecorder.swift`
- Test: `ios/Oxygen/Tests/TransitionLogTests.swift`

**Interfaces:**
- Consumes: `SyncState`, `SyncEvent` (Task 4).
- Produces:

```swift
extension SyncStep { var logDescription: String { get } }
extension SyncFailureReason { var logDescription: String { get } }
extension SyncState { var logDescription: String { get } }
extension SyncEvent { var logDescription: String { get } }

struct TransitionLogEntry: Equatable, Sendable { let timestamp: Date; let from: SyncState; let event: SyncEvent; let to: SyncState }
struct TransitionLog: Equatable, Sendable {
    static let capacity = 2000
    private(set) var lines: [String]                // oldest first
    init(lines: [String])                            // keeps the last `capacity` lines
    mutating func append(_ entry: TransitionLogEntry)
    func renderedText() -> String                    // lines joined by "\n", plus a trailing "\n"; "" when empty
}
struct TransitionLogFile: Sendable {
    let url: URL
    func load() -> [String]                          // [] when the file is missing
    func write(_ log: TransitionLog) throws          // atomic write
}
@MainActor final class TransitionLogRecorder {
    private(set) var log: TransitionLog
    init(file: TransitionLogFile?)                   // loads lines from file when present
    func record(_ entry: TransitionLogEntry)         // appends, then writes the file when present; a write error is dropped
}
```

Description rules:

- **Steps:** the case name, with the fetch type's case name in parentheses, e.g. `fetching(temperature)`.
- **Reasons:**
  - The case name, e.g. `bluetoothOff`.
  - `linkLost` shows the step: `linkLost(fetching(temperature))`.
  - `fetchTimeout` and `persistFailed` show the type: `fetchTimeout(temperature)`, `persistFailed(temperature)`.
- **States:**
  - `idle`.
  - An active step uses the step's description.
  - `waitingForRetry(<reason>)` and `failed(<reason>)`.
  - When `retryUsed` is true, append ` retryUsed`.
- **Events:** the case name, with the type's case name in parentheses, e.g. `fetchCompleted(temperature)`.
- **Line:** `<timestamp ISO-8601 UTC with milliseconds> <from> --<event>--> <to>`.

- [ ] **Step 1: Write the failing tests**

```swift
struct TransitionLogTests {
    let instant = Date(timeIntervalSince1970: 1_791_355_333.512)   // 2026-10-07T06:42:13.512Z

    @Test func lineFormat() {
        var log = TransitionLog(lines: [])
        log.append(TransitionLogEntry(timestamp: instant, from: SyncState(phase: .idle, retryUsed: false),
                                      event: .syncRequested,
                                      to: SyncState(phase: .active(.scanning), retryUsed: false)))
        #expect(log.lines == ["2026-10-07T06:42:13.512Z idle --syncRequested--> scanning"])
    }
    @Test func describesNestedReasonAndRetryFlag() {
        let state = SyncState(phase: .failed(.linkLost(during: .fetching(.temperature))), retryUsed: true)
        #expect(state.logDescription == "failed(linkLost(fetching(temperature))) retryUsed")
        #expect(SyncEvent.fetchCompleted(.temperature).logDescription == "fetchCompleted(temperature)")
    }
    @Test func keepsOnlyLastCapacityLines() {
        var log = TransitionLog(lines: (0..<2000).map { "line \($0)" })
        log.append(TransitionLogEntry(timestamp: instant, from: SyncState(phase: .idle, retryUsed: false),
                                      event: .linkLost, to: SyncState(phase: .idle, retryUsed: false)))
        #expect(log.lines.count == 2000)
        #expect(log.lines.first == "line 1")
    }
    @Test func renderedTextEndsWithNewline() {
        #expect(TransitionLog(lines: ["a", "b"]).renderedText() == "a\nb\n")
        #expect(TransitionLog(lines: []).renderedText() == "")
    }
    @Test func fileRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        let file = TransitionLogFile(url: url)
        try file.write(TransitionLog(lines: ["a", "b"]))
        #expect(file.load() == ["a", "b"])
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `-only-testing:OxygenTests/TransitionLogTests`.

Expected: compile failure.

- [ ] **Step 3: Implement the three files**

The milliseconds formatter is an `ISO8601DateFormatter` with `[.withInternetDateTime, .withFractionalSeconds]` and the time zone set to UTC.

- [ ] **Step 4: Run the tests and confirm they pass**

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Oxygen/Sources/Log ios/Oxygen/Tests/TransitionLogTests.swift
git commit -m "feat(oxygen): add fixed-size transition log"
```

---

### Task 6: Auth key parsing and Keychain storage

**Files:**
- Create: `ios/Oxygen/Sources/Keys/StrapAuthKey.swift`
- Create: `ios/Oxygen/Sources/Keys/StrapKeyStore.swift`
- Test: `ios/Oxygen/Tests/StrapAuthKeyTests.swift`
- Test: `ios/Oxygen/Tests/StrapKeyStoreTests.swift`

**Interfaces:**
- Consumes: upstream `ios/OpenCircuit/Helio/HelioKeyStore.swift` (reference only) and the commit in API map row 0, both for the adaptation header.
- Produces:

```swift
struct StrapAuthKey: Equatable, Sendable {
    let bytes: Data                                  // exactly 16 bytes
    static func parse(_ text: String) -> StrapAuthKey?
    var hexString: String { get }                    // 32 lowercase hex characters
}
protocol StrapKeyStoring {
    func load() throws -> StrapAuthKey?
    func save(_ key: StrapAuthKey) throws            // also clears the rejection mark
    func markRejected() throws
    func isRejected() throws -> Bool
}
enum StrapKeyStoreError: Error, Equatable { case keychainStatus(Int32) }
struct StrapKeyStore: StrapKeyStoring {
    static let productionService = "com.emanuelefalli.oxygen.strap-auth-key"
    let service: String
    func delete() throws                             // removes the key and the rejection mark
}
```

Parse rule (API map row 1):

- `HelioKeyText.normalized(text)` gives 32 lowercase hex digits, or nil.
- `ZeppHex.bytes(_:)` turns them into the 16 `bytes`.
- `ZeppAuthKey(bytes:)` builds `zeppAuthKey`. `ZeppAuthKey` keeps its bytes internal, so Oxygen holds its own copy for the Keychain.

`HelioKeyText.normalized` does this:

1. Trim whitespace.
2. Strip one leading `0x` or `0X`.
3. Remove whitespace and colons anywhere.
4. Require exactly 32 ASCII hex digits.

Add `var zeppAuthKey: ZeppAuthKey { get }` for `StrapSession`.

Keychain details:

- Item class: `kSecClassGenericPassword`.
- Accounts: `auth-key` (the 16 bytes) and `auth-key-rejected` (the single byte `0x01`).
- Accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- `errSecItemNotFound` maps to `nil` or `false`. Any other non-success status throws `keychainStatus`.

- [ ] **Step 1: Write the failing tests**

```swift
struct StrapAuthKeyTests {
    let expected = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff])

    @Test(arguments: [
        "00112233445566778899aabbccddeeff",
        "0x00112233445566778899AABBCCDDEEFF\n",
        "00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff",
        "  0011 2233 4455 6677 8899 aabb ccdd eeff  ",
    ])
    func acceptsValidSpellings(_ text: String) {
        #expect(StrapAuthKey.parse(text)?.bytes == expected)
        #expect(StrapAuthKey.parse(text)?.hexString == "00112233445566778899aabbccddeeff")
    }

    @Test(arguments: [
        "", "0x",
        "0011223344556677889 9aabbccddeef",
        "00112233445566778899aabbccddeeff0",
        "g0112233445566778899aabbccddeeff",
    ])
    func rejectsInvalidSpellings(_ text: String) {
        #expect(StrapAuthKey.parse(text) == nil)
    }
}

final class StrapKeyStoreTests {
    let store = StrapKeyStore(service: "com.emanuelefalli.oxygen.tests.\(UUID().uuidString)")
    deinit { try? store.delete() }

    @Test func emptyStoreLoadsNil() throws {
        #expect(try store.load() == nil)
        #expect(try store.isRejected() == false)
    }
    @Test func saveThenLoadRoundTrips() throws {
        let key = try #require(StrapAuthKey.parse("00112233445566778899aabbccddeeff"))
        try store.save(key)
        #expect(try store.load() == key)
    }
    @Test func saveClearsRejectionMark() throws {
        let key = try #require(StrapAuthKey.parse("00112233445566778899aabbccddeeff"))
        try store.markRejected()
        #expect(try store.isRejected())
        try store.save(key)
        #expect(try store.isRejected() == false)
    }
}
```

The second invalid case has 31 hex characters once the space is removed, and the third has 33.

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `-only-testing:OxygenTests/StrapAuthKeyTests -only-testing:OxygenTests/StrapKeyStoreTests`.

Expected: compile failure.

- [ ] **Step 3: Implement both files**

`StrapKeyStore.swift` starts with the adaptation header for upstream `HelioKeyStore`.

- [ ] **Step 4: Run the tests and confirm they pass**

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Oxygen/Sources/Keys ios/Oxygen/Tests/StrapAuthKeyTests.swift ios/Oxygen/Tests/StrapKeyStoreTests.swift
git commit -m "feat(oxygen): parse strap auth key and store it in the Keychain"
```

---

### Task 7: Raw store

**Files:**
- Create: `ios/Oxygen/Sources/Sync/FetchedRound.swift`
- Create: `ios/Oxygen/Sources/Store/StoredRound.swift`
- Create: `ios/Oxygen/Sources/Store/StrapHistoryRound.swift`
- Create: `ios/Oxygen/Sources/Store/StrapFetchWatermark.swift`
- Create: `ios/Oxygen/Sources/Store/RawStore.swift`
- Test: `ios/Oxygen/Tests/RawStoreTests.swift`

**Interfaces:**
- Consumes: `StrapFetchType` (Task 4).
- Produces:

```swift
struct FetchedRound: Equatable, Sendable {
    let fetchType: StrapFetchType; let roundStart: Date; let payload: Data; let receivedAt: Date
    let nextSince: Date?                             // ZeppFetchRound.nextSince: last record + 1 minute; nil when empty
}

struct StoredRound: Equatable, Sendable {
    let fetchType: StrapFetchType; let roundStart: Date; let payload: Data
    let payloadDigest: String                        // SHA-256, lowercase hex
    let receivedAt: Date
    init(fetched: FetchedRound)
    var identity: String { get }                     // "\(code)-\(Int64(roundStart.timeIntervalSince1970 * 1000))-\(payloadDigest)"
}

@Model final class StrapHistoryRound {
    @Attribute(.unique) var identity: String
    var fetchTypeCode: Int; var roundStart: Date; var payload: Data; var payloadDigest: String; var receivedAt: Date
}
@Model final class StrapFetchWatermark {
    @Attribute(.unique) var fetchTypeCode: Int
    var watermark: Date
}

@MainActor protocol RawStoring: AnyObject {
    func watermark(for type: StrapFetchType) throws -> Date?
    func commit(rounds: [StoredRound], type: StrapFetchType, watermark: Date?) throws
    func allRounds() throws -> [StoredRound]         // sorted by fetch type code, then roundStart, then receivedAt
}
@MainActor final class RawStore: RawStoring {
    static func makeContainer(inMemory: Bool) throws -> ModelContainer
    init(container: ModelContainer)
}
```

`commit` rules:

- Insert every round whose `identity` is not stored yet. A round whose identity already exists is skipped, never replaced.
- Set the watermark to `max(existing, watermark)`. If `watermark` is nil, leave it unchanged.
- Everything above goes into one `ModelContext.save()`.

- [ ] **Step 1: Write the failing tests**

```swift
@MainActor struct RawStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_791_355_320)            // 2026-10-07T06:42:00Z
    let t1 = Date(timeIntervalSince1970: 1_791_528_120)            // 2026-10-09T06:42:00Z

    func makeStore() throws -> RawStore { RawStore(container: try RawStore.makeContainer(inMemory: true)) }
    func round(_ bytes: [UInt8], start: Date) -> StoredRound {
        StoredRound(fetched: FetchedRound(fetchType: .activity, roundStart: start, payload: Data(bytes), receivedAt: t0, nextSince: nil))
    }

    @Test func digestAndIdentity() {
        let stored = round([0x01, 0x02, 0x03], start: t0)
        #expect(stored.payloadDigest == "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81")
        #expect(stored.identity == "1-1791355320000-039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81")
    }
    @Test func commitStoresRoundsAndWatermark() throws {
        let store = try makeStore()
        try store.commit(rounds: [round([0x01, 0x02, 0x03], start: t0), round([0x0a, 0x0b], start: t0)], type: .activity, watermark: t1)
        #expect(try store.allRounds().count == 2)
        #expect(try store.watermark(for: .activity) == t1)
        #expect(try store.watermark(for: .temperature) == nil)
    }
    @Test func committingSameRoundTwiceStoresOnce() throws {
        let store = try makeStore()
        try store.commit(rounds: [round([0x01, 0x02, 0x03], start: t0)], type: .activity, watermark: t0)
        try store.commit(rounds: [round([0x01, 0x02, 0x03], start: t0)], type: .activity, watermark: t0)
        #expect(try store.allRounds().count == 1)
    }
    @Test func watermarkNeverMovesBackward() throws {
        let store = try makeStore()
        try store.commit(rounds: [], type: .activity, watermark: t1)
        try store.commit(rounds: [], type: .activity, watermark: t0)
        try store.commit(rounds: [], type: .activity, watermark: nil)
        #expect(try store.watermark(for: .activity) == t1)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `-only-testing:OxygenTests/RawStoreTests`.

Expected: compile failure.

- [ ] **Step 3: Implement the files**

- The digest uses `CryptoKit.SHA256`.
- `makeContainer` builds a `ModelConfiguration(isStoredInMemoryOnly: inMemory)` with both models.

- [ ] **Step 4: Run the tests and confirm they pass**

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Oxygen/Sources/Store ios/Oxygen/Sources/Sync/FetchedRound.swift ios/Oxygen/Tests/RawStoreTests.swift
git commit -m "feat(oxygen): add append-only raw round store with monotonic watermarks"
```

---

### Task 8: Record decoding, de-duplication and the watermark rule

**Files:**
- Create: `ios/Oxygen/Sources/Decode/StrapRecordDecoder.swift`
- Create: `ios/Oxygen/Sources/Decode/RecordDeduplicator.swift`
- Create: `ios/Oxygen/Sources/Decode/WatermarkRule.swift`
- Test: `ios/Oxygen/Tests/DecoderFixtures.swift`
- Test: `ios/Oxygen/Tests/StrapRecordDecoderTests.swift`
- Test: `ios/Oxygen/Tests/RecordDeduplicatorTests.swift`
- Test: `ios/Oxygen/Tests/WatermarkRuleTests.swift`

**Interfaces:**
- Consumes: `StoredRound` (Task 7), and API map rows 7, 8, 9 and 12.
- Produces:

```swift
struct StrapRecordField: Equatable, Sendable { let name: String; let value: String }
struct DecodedStrapRecord: Equatable, Sendable {
    let fetchType: StrapFetchType; let timestamp: Date; let fields: [StrapRecordField]; let receivedAt: Date
}
enum StrapRecordDecoder {
    static func fieldNames(for type: StrapFetchType) -> [String]   // parser property names in declaration order, without the timestamp property
    static func decode(_ round: StoredRound) throws -> [DecodedStrapRecord]
}
enum RecordDeduplicator {
    static func merge(_ records: [DecodedStrapRecord]) -> [DecodedStrapRecord]
}
enum WatermarkRule {
    static func fetchStart(watermark: Date?, now: Date) -> Date
    static func advanced(previous: Date?, nextSince: Date?, now: Date) -> Date?
}
```

- **Field formatting:**
  - Integers in decimal.
  - Floating point with `String(describing:)`.
  - `Date` as ISO-8601 UTC without fractional seconds.
  - `Bool` as `true` or `false`.
  - Enums by case name (`String(describing:)`).
  - Byte arrays as lowercase hex without separators (`ZeppHex.string`).
  - Sleep stages as `start/end/kind` triples joined by `;`. `start` and `end` are ISO-8601 UTC, and `kind` is the case name, e.g. `other(2)`.
  - `nil` as an empty string.
- **Field names:** `fieldNames(for:)` returns the stored properties listed in API map row 8, in that order, without `time`.
- **Type mapping:** `ZeppFetchType(rawValue: type.rawValue)`. The 13 codes are identical (API map row 7).
- **`merge`:**
  - Records are unique by (fetchType, timestamp). On a clash, the record with the later `receivedAt` wins.
  - The output is sorted by fetch type code, then timestamp.
- **`fetchStart`** (upstream's `HelioFetchPlan.plan` rule for one type, using its constants):

  ```
  first  = floorToMinute(now − firstSyncLookback)
  oldest = floorToMinute(now − maxLookback)
  latest = floorToMinute(now)
  watermark nil, or watermark > now + futureTolerance   → first
  otherwise                                              → min(max(floorToMinute(watermark), oldest), latest)
  ```

  Upstream's activity and sleep-session re-fetch tied to temperature is not copied (API map row 12).
- **`advanced`** (upstream's `HelioFetchPlan.advancedCursor`, applied to a `nextSince`):

  ```
  nextSince nil     → previous
  clamped           = min(nextSince, floorToMinute(now))
  previous nil      → clamped
  otherwise         → max(previous, clamped)
  ```

- [ ] **Step 1: Transcribe the fixtures**

`DecoderFixtures.swift` declares `struct DecoderFixture: Sendable, CustomTestStringConvertible` with these fields:

- `fetchType`
- `roundStart: Date`
- `payload: [UInt8]`
- `expectedRecordCount: Int`
- `expectedFirstTimestamp: Date`
- `expectedFirstFields: [StrapRecordField]`

Add `static let all: [DecoderFixture]` with one entry per fetch type, transcribed from the "Decoder fixtures" table of the API map. The 6-byte heart-rate vector serves manual, resting and maximum heart rate. Rebuild the PAI and sleep-session payloads with the upstream builders the table points to, ported as private helpers in this file. Expected values are formatted with the field-formatting rules above.

- [ ] **Step 2: Write the failing tests**

```swift
struct StrapRecordDecoderTests {
    @Test(arguments: DecoderFixture.all)
    func decodesUpstreamVector(_ fixture: DecoderFixture) throws {
        let round = StoredRound(fetched: FetchedRound(fetchType: fixture.fetchType, roundStart: fixture.roundStart,
                                                      payload: Data(fixture.payload), receivedAt: fixture.roundStart,
                                                      nextSince: nil))
        let records = try StrapRecordDecoder.decode(round)
        #expect(records.count == fixture.expectedRecordCount)
        #expect(records.first?.timestamp == fixture.expectedFirstTimestamp)
        #expect(records.first?.fields == fixture.expectedFirstFields)
        #expect(records.first?.fields.map(\.name) == StrapRecordDecoder.fieldNames(for: fixture.fetchType))
    }
    @Test func coversAllThirteenTypes() {
        #expect(Set(DecoderFixture.all.map(\.fetchType)) == Set(StrapFetchType.allCases))
    }
}

struct RecordDeduplicatorTests {
    let t0 = Date(timeIntervalSince1970: 1_791_355_320)
    let t1 = Date(timeIntervalSince1970: 1_791_355_380)
    func record(_ type: StrapFetchType, _ at: Date, received: Date, value: String) -> DecodedStrapRecord {
        DecodedStrapRecord(fetchType: type, timestamp: at, fields: [StrapRecordField(name: "v", value: value)], receivedAt: received)
    }
    @Test func laterReceiptWins() {
        let merged = RecordDeduplicator.merge([
            record(.activity, t1, received: t0, value: "b"),
            record(.activity, t0, received: t0, value: "old"),
            record(.activity, t0, received: t1, value: "new"),
        ])
        #expect(merged.map { $0.fields[0].value } == ["new", "b"])
    }
    @Test func differentTypesWithSameTimestampAreKept() {
        let merged = RecordDeduplicator.merge([record(.activity, t0, received: t0, value: "a"),
                                               record(.temperature, t0, received: t0, value: "t")])
        #expect(merged.count == 2)
    }
}

struct WatermarkRuleTests {
    let now = Date(timeIntervalSince1970: 1_791_355_320)                 // 2026-10-07T06:42:00Z, a whole minute
    let sevenDaysBack = Date(timeIntervalSince1970: 1_790_750_520)

    @Test func defaultStartIsSevenDaysBack() {
        #expect(WatermarkRule.fetchStart(watermark: nil, now: now) == sevenDaysBack)
    }
    @Test func startsAtWatermarkFlooredToMinute() {
        #expect(WatermarkRule.fetchStart(watermark: Date(timeIntervalSince1970: 1_791_000_030), now: now)
                == Date(timeIntervalSince1970: 1_791_000_000))
    }
    @Test func futureWatermarkBeyondToleranceCountsAsMissing() {
        #expect(WatermarkRule.fetchStart(watermark: now.addingTimeInterval(300), now: now) == now)
        #expect(WatermarkRule.fetchStart(watermark: now.addingTimeInterval(301), now: now) == sevenDaysBack)
    }
    @Test func neverMoreThanThirtyDaysBack() {
        #expect(WatermarkRule.fetchStart(watermark: now.addingTimeInterval(-40 * 86_400), now: now)
                == Date(timeIntervalSince1970: 1_788_763_320))
    }
    @Test func advanceFollowsUpstreamCursorRule() {
        let earlier = Date(timeIntervalSince1970: 1_791_000_000)
        #expect(WatermarkRule.advanced(previous: nil, nextSince: earlier, now: now) == earlier)
        #expect(WatermarkRule.advanced(previous: nil, nextSince: now.addingTimeInterval(3600), now: now) == now)
        #expect(WatermarkRule.advanced(previous: now, nextSince: earlier, now: now) == now)
        #expect(WatermarkRule.advanced(previous: earlier, nextSince: nil, now: now) == earlier)
        #expect(WatermarkRule.advanced(previous: nil, nextSince: nil, now: now) == nil)
    }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: the four suites.

Expected: compile failure.

- [ ] **Step 4: Implement the three files**

- `decode` calls `ZeppRecordParser.parse(zeppType, data: [UInt8](round.payload), start: round.roundStart)`, then switches on the `ZeppRecordBatch` case.
- It maps each record's stored properties to `StrapRecordField`s, in the order `fieldNames(for:)` returns. `timestamp` is the record's `time`.
- `WatermarkRule` uses `HelioFetchPlan.firstSyncLookback`, `.maxLookback`, `.futureTolerance` and `.floorToMinute`. It never repeats their values.

- [ ] **Step 5: Run the tests and confirm they pass**

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/Oxygen/Sources/Decode ios/Oxygen/Tests
git commit -m "feat(oxygen): decode strap rounds with ZeppKit, de-duplicate records, add watermark rule"
```

---

### Task 9: StrapSession, a pure state machine around ZeppKit

**Files:**
- Create: `ios/Oxygen/Sources/Sync/StrapCharacteristic.swift`
- Create: `ios/Oxygen/Sources/Sync/StrapSession.swift`
- Test: `ios/Oxygen/Tests/FakeStrapDeviceLink.swift`
- Test: `ios/Oxygen/Tests/StrapSessionTests.swift`

**Interfaces:**
- Consumes:
  - `StrapAuthKey` (Task 6), `FetchedRound` (Task 7) and `DecoderFixture` (Task 8).
  - API map rows 1–7 and 10.
  - The upstream reference `ios/OpenCircuit/Helio/HelioSession.swift`: setup at lines 700–760, messages at 810–875, fetch at 936–990.
- Produces:

```swift
typealias StrapCharacteristic = ZeppCharacteristic          // StrapCharacteristic.swift

struct StrapDeviceSummary: Equatable, Sendable { let batteryPercent: Int?; let firmwareVersion: String? }

enum StrapSessionInput: Equatable, Sendable {
    case authenticate(key: StrapAuthKey, maximumWriteLength: Int, notifiable: Set<StrapCharacteristic>)
    case prepare(now: Date, timeZone: TimeZone)
    case skipPreparationStep
    case fetch(StrapFetchType, since: Date, now: Date, timeZone: TimeZone)
    case notification(StrapCharacteristic, Data)
    case notifyStateChanged(StrapCharacteristic, enabled: Bool)
}
enum StrapSessionOutput: Equatable, Sendable {
    case write(StrapCharacteristic, Data)
    case setNotify(StrapCharacteristic, enabled: Bool)
    case authSucceeded, authRejected, authBusy
    case preparationStepStarted
    case sessionPrepared(StrapDeviceSummary)
    case fetchProgressed(StrapFetchType)
    case fetchCompleted(StrapFetchType, [FetchedRound])
}
final class StrapSession {
    init()
    func handle(_ input: StrapSessionInput) -> [StrapSessionOutput]
}
```

Rules (API map rows 2–6):

- **No I/O.** Writes and subscription changes are returned as outputs.
- **Authenticate:**
  1. Build `ZeppLink(authKey: key.zeppAuthKey, random: .system, maxWriteLength: maximumWriteLength)`.
  2. Emit `.setNotify(.chunkedRead, enabled: true)`, plus `.setNotify(.chunkedWrite, enabled: true)` when `notifiable` contains `.chunkedWrite`.
  3. Once every requested subscription is confirmed by `.notifyStateChanged(_, enabled: true)`, emit the writes of `link.startAuthentication()`.
- **Link events:**
  - Notifications on `.chunkedRead` and `.chunkedWrite` go to `link.receive`. Its writes are always emitted.
  - `.authenticated`: emit `.setNotify(.chunkedWrite, enabled: false)` if it was subscribed, then `.authSucceeded`.
  - `.authenticationFailed(.wrongAuthKey)`: emit `.authRejected`.
  - Any other `.authenticationFailed`: emit `.authBusy`.
  - `.message` on `ZeppEndpoint.connection` (`0x0015`):
    - Payload `03` (ping): send `[0x04]` on `0x0015`.
    - Payload `02 lo hi` with an announced length ≥ 20: call `link.setMaxWriteLength(min(announced, maximumWriteLength))`.
  - Any other `.message` answers the current preparation step, if it matches that step's endpoint.
- **Prepare:**
  - The steps are services list, device info, battery, set time, in that order.
  - Starting a step emits `.preparationStepStarted` and sends its request.
  - The services-list reply is applied with `link.apply(servicesList:)`. Later steps whose endpoint is not in the list are skipped without starting. If there is no list, because that step was skipped, every later step is skipped.
  - A matching reply, or `.skipPreparationStep`, ends the current step.
  - After the last step, emit `.sessionPrepared(StrapDeviceSummary(batteryPercent: battery?.level, firmwareVersion: deviceInfo?.firmwareVersion))`. A `ZeppDeviceInfo` with `isAmbiguous` is ignored.
- **Fetch:**
  1. Emit `.setNotify(.activityControl, enabled: true)` and `.setNotify(.activityData, enabled: true)`.
  2. Once both are confirmed, create `ZeppHistoryFetch(plan: [(zeppType, since)], now: now, configuration: .init(ackPolicy: .keepOnDevice, timeZone: timeZone))` and process `start()`.
  3. `.activityControl` notifications go to `receiveControl`. `.activityData` notifications emit `.fetchProgressed(type)`, then go to `receiveData`.
  4. Actions:
     - `.sendControl(bytes)` becomes `.write(.activityControl, Data(bytes))`.
     - `.roundReady(round)`: append `FetchedRound(fetchType: type, roundStart: round.start, payload: Data(round.rawData), receivedAt: now, nextSince: round.nextSince)`, then process `commit(roundID: round.id, durable: false)`. Under `.keepOnDevice` the ack is `03 09` either way.
     - `.roundFailed` and `.noData` add nothing.
     - `.finished`: emit `.setNotify(.activityControl, enabled: false)`, `.setNotify(.activityData, enabled: false)`, then `.fetchCompleted(type, rounds)`.
- **Out-of-order input:** an input that does not fit the session's current step returns `[]`.
- **Header:** the file starts with the adaptation header for `HelioSession.swift`.

- [ ] **Step 1: Write the test helper**

`FakeStrapDeviceLink.swift` wraps `FakeZeppDevice` (API map row 10):

```swift
final class FakeStrapDeviceLink {
    static let notifiable: Set<StrapCharacteristic> = [.chunkedRead, .chunkedWrite, .activityControl, .activityData]
    let device: FakeZeppDevice
    init(deviceKey: StrapAuthKey, seeded fixtures: [DecoderFixture], listsDeviceInfo: Bool = false)
}

func drive(_ session: StrapSession, _ link: FakeStrapDeviceLink, _ input: StrapSessionInput) -> [StrapSessionOutput]
```

The initializer:

- Creates `FakeZeppDevice(authKey: [UInt8](deviceKey.bytes), privateKey: Array(UInt8(0x81)...UInt8(0x98)), random: Array(UInt8(0xf0)...UInt8(0xff)), writeLength: 244)`.
- Seeds `device.fetchData[zeppType] = (start: ZeppFetchTimestamp.encode(fixture.roundStart, timeZone: TimeZone(identifier: "UTC")!), data: fixture.payload)` for each fixture.
- Removes `0x0043` from `device.services` unless `listsDeviceInfo` is true. The fake has no device-info reply by default, so a listed device-info step can only end by being skipped.

`drive` hands `input` to the session, then works through the outputs first in, first out:

- `.write(c, d)`: pass `ZeppWrite(c, [UInt8](d))` to `link.device.phoneWrote`, and feed every returned notification back as `.notification(n.characteristic, Data(n.bytes))`.
- `.setNotify(c, e)`: feed back `.notifyStateChanged(c, enabled: e)`.

It returns every output except `.write`, in order.

- [ ] **Step 2: Write the failing tests**

```swift
struct StrapSessionTests {
    let deviceKey = StrapAuthKey.parse("00112233445566778899aabbccddeeff")!
    let otherKey = StrapAuthKey.parse("ffeeddccbbaa99887766554433221100")!
    let now = Date(timeIntervalSince1970: 1_791_355_320)
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let activity = DecoderFixture.all.first { $0.fetchType == .activity }!

    func authenticate(_ session: StrapSession, _ link: FakeStrapDeviceLink, key: StrapAuthKey) -> [StrapSessionOutput] {
        drive(session, link, .authenticate(key: key, maximumWriteLength: 244, notifiable: FakeStrapDeviceLink.notifiable))
    }
    func prepared(_ link: FakeStrapDeviceLink) -> StrapSession {
        let session = StrapSession()
        _ = authenticate(session, link, key: deviceKey)
        _ = drive(session, link, .prepare(now: now, timeZone: berlin))
        return session
    }

    @Test func authenticatesWithMatchingKey() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [])
        let outputs = authenticate(StrapSession(), link, key: deviceKey)
        #expect(outputs.contains(.authSucceeded))
        #expect(outputs.contains(.setNotify(.chunkedWrite, enabled: false)))
        #expect(link.device.authenticated)
    }
    @Test func rejectsWrongKey() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [])
        #expect(authenticate(StrapSession(), link, key: otherKey).contains(.authRejected))
    }
    @Test func secondPrepareIsIgnoredAndTimeWasSetOnce() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [])
        let outputs = drive(prepared(link), link, .prepare(now: now, timeZone: berlin))
        #expect(outputs.isEmpty)                                        // already prepared: out of order
        #expect(link.device.timeSetCount == 1)
    }
    @Test func preparedSummaryCarriesBattery() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [])
        let session = StrapSession()
        _ = authenticate(session, link, key: deviceKey)
        let outputs = drive(session, link, .prepare(now: now, timeZone: berlin))
        #expect(outputs.contains(.preparationStepStarted))
        #expect(outputs.last == .sessionPrepared(StrapDeviceSummary(batteryPercent: 87, firmwareVersion: nil)))
    }
    @Test func unansweredStepIsSkippedOnRequest() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [], listsDeviceInfo: true)
        let session = StrapSession()
        _ = authenticate(session, link, key: deviceKey)
        let waiting = drive(session, link, .prepare(now: now, timeZone: berlin))
        #expect(waiting.last == .preparationStepStarted)                // device info never answers
        let resumed = drive(session, link, .skipPreparationStep)
        #expect(resumed.last == .sessionPrepared(StrapDeviceSummary(batteryPercent: 87, firmwareVersion: nil)))
    }
    @Test func fetchActivityReturnsSeededRounds() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [activity])
        let outputs = drive(prepared(link), link, .fetch(.activity, since: activity.roundStart, now: now, timeZone: berlin))
        #expect(outputs.contains(.fetchProgressed(.activity)))
        #expect(outputs.contains(.setNotify(.activityData, enabled: false)))
        guard case .fetchCompleted(.activity, let rounds)? = outputs.last else { Issue.record("no completion"); return }
        #expect(!rounds.isEmpty)
        #expect(rounds.allSatisfy { $0.payload == Data(activity.payload) && $0.receivedAt == now })
        #expect(rounds.first?.nextSince == Date(timeIntervalSince1970: 1_790_632_980))   // last record + 1 min
    }
    @Test func fetchAcksAreAlwaysKeep() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [activity])
        _ = drive(prepared(link), link, .fetch(.activity, since: activity.roundStart, now: now, timeZone: berlin))
        #expect(!link.device.fetchAcks.isEmpty)
        #expect(link.device.fetchAcks.allSatisfy { $0 == 0x09 })
    }
    @Test func fetchOfEmptyTypeCompletesWithNoRounds() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [activity])
        let outputs = drive(prepared(link), link, .fetch(.temperature, since: activity.roundStart, now: now, timeZone: berlin))
        #expect(outputs.last == .fetchCompleted(.temperature, []))
    }
    @Test func answersPing() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [])
        link.device.services.append((endpoint: 0x0015, flag: 0))
        let session = prepared(link)
        for notification in link.device.unsolicited(endpoint: 0x0015, [0x03]) {
            _ = drive(session, link, .notification(notification.characteristic, Data(notification.bytes)))
        }
        #expect(link.device.receivedEndpoints.last == 0x0015)
    }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `-only-testing:OxygenTests/StrapSessionTests`.

Expected: compile failure.

- [ ] **Step 4: Implement `StrapSession`**

- Compose `ZeppLink` and `ZeppHistoryFetch` exactly as the rules above describe.
- Keep the internal step as a private `enum`: `idle`, `subscribingForAuthentication(pending: Set<StrapCharacteristic>)`, `authenticating`, `authenticated`, `preparing(PreparationStep)`, `ready`, `subscribingForFetch(StrapFetchType, pending: Set<StrapCharacteristic>)`, `fetching(StrapFetchType)`.

- [ ] **Step 5: Run the tests and confirm they pass**

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/Oxygen/Sources/Sync/StrapCharacteristic.swift ios/Oxygen/Sources/Sync/StrapSession.swift ios/Oxygen/Tests
git commit -m "feat(oxygen): add pure StrapSession over ZeppKit, tested against FakeZeppDevice"
```

---

### Task 10: SyncRunner, the effect executor

**Files:**
- Create: `ios/Oxygen/Sources/Sync/StrapConnecting.swift`
- Create: `ios/Oxygen/Sources/Sync/SyncTimerScheduling.swift`
- Create: `ios/Oxygen/Sources/Sync/LastSyncRecord.swift`
- Create: `ios/Oxygen/Sources/Sync/SyncRunner.swift`
- Test: `ios/Oxygen/Tests/FakeStrapConnection.swift`
- Test: `ios/Oxygen/Tests/RecordingTimerScheduler.swift`
- Test: `ios/Oxygen/Tests/InMemoryStrapKeyStore.swift`
- Test: `ios/Oxygen/Tests/FailingRawStore.swift`
- Test: `ios/Oxygen/Tests/SyncRunnerTests.swift`

**Interfaces:**
- Consumes: Tasks 4–9.
- Produces:

```swift
enum StrapConnectionEvent: Equatable, Sendable {
    case bluetoothPoweredOn, bluetoothPoweredOff, bluetoothUnauthorized
    case strapDiscovered
    case connected(maximumWriteLength: Int, notifiable: Set<StrapCharacteristic>)
    case connectionFailed, linkLost
    case notification(StrapCharacteristic, Data)
    case notifyStateChanged(StrapCharacteristic, enabled: Bool)
}
@MainActor protocol StrapConnecting: AnyObject {
    func startScan(); func stopScan(); func connect(); func disconnect()
    func write(_ data: Data, to characteristic: StrapCharacteristic)
    func setNotify(_ characteristic: StrapCharacteristic, enabled: Bool)
}
@MainActor protocol SyncTimerScheduling: AnyObject {
    func schedule(_ timer: SyncTimer, afterSeconds seconds: Int)   // replaces a pending timer of the same kind
    func cancel(_ timer: SyncTimer)
}
@MainActor final class TaskSyncTimerScheduler: SyncTimerScheduling {
    init(fired: AsyncStream<SyncTimer>.Continuation)                // yields the timer when it fires
}
struct LastSyncRecord {
    static let key = "oxygen.lastSyncCompletedAt"
    let defaults: UserDefaults
    func load() -> Date?
    func save(_ date: Date)
}
enum SyncRunnerInput: Equatable, Sendable {
    case syncRequested, authKeyEntered
    case connection(StrapConnectionEvent)
    case timerFired(SyncTimer)
}
@MainActor @Observable final class SyncRunner {
    private(set) var state: SyncState
    private(set) var deviceSummary: StrapDeviceSummary?
    var transitionLogLines: [String] { get }                        // logRecorder.log.lines; also read by the export in Task 14
    init(initialState: SyncState, connection: StrapConnecting, timers: SyncTimerScheduling, store: RawStoring,
         keyStore: StrapKeyStoring, lastSync: LastSyncRecord, logRecorder: TransitionLogRecorder,
         now: @escaping () -> Date, timeZone: TimeZone)
    func receive(_ input: SyncRunnerInput)
}
```

**Input mapping:**

| Input | Effect |
|---|---|
| `.syncRequested`, `.authKeyEntered` | The `SyncEvent` of the same name |
| `.connection(.connected(m, notifiable))` | Store `m` and `notifiable`, create a fresh `StrapSession`, then send `.connected` |
| `.connection(.notification(c, d))` | `session.handle(.notification(c, d))`, then process the outputs |
| `.connection(.notifyStateChanged(c, e))` | `session.handle(.notifyStateChanged(c, enabled: e))`, then process the outputs |
| Other connection events | The `SyncEvent` of the same name |
| `.timerFired(.scan)` | `.scanTimedOut` |
| `.timerFired(.session)` | `.authTimedOut` in `active(.authenticating)`; `.preparationStepTimedOut` in `active(.preparing)`; ignored otherwise |
| `.timerFired(.fetch)` | `.fetchTimedOut(t)` in `active(.fetching(t))`; ignored otherwise |
| `.timerFired(.retry)` | `.retryTimerFired` |

**Session output mapping:**

| Output | Effect |
|---|---|
| `.write(c, d)` | `connection.write(d, to: c)` |
| `.setNotify(c, e)` | `connection.setNotify(c, enabled: e)` |
| `.authSucceeded`, `.authRejected` | The `SyncEvent` of the same name |
| `.authBusy` | `.strapBusyDetected` |
| `.preparationStepStarted` | `.preparationStepStarted` |
| `.sessionPrepared(s)` | Set `deviceSummary = s`, then send `.sessionPrepared` |
| `.fetchProgressed(t)` | `.fetchProgressed(t)` |
| `.fetchCompleted(t, rounds)` | Hold `rounds` as the pending rounds for `t`, then send `.fetchCompleted(t)` |

**Effect execution:**

| Effect | Execution |
|---|---|
| `startScan`, `stopScan`, `connect`, `disconnect` | The connection method of the same name |
| `authenticate` | `keyStore.load()`. If it returns nil or throws, send `.authKeyMissing`. Otherwise call `session.handle(.authenticate(key:maximumWriteLength:notifiable:))` with the stored values |
| `prepareSession` | `session.handle(.prepare(now: now(), timeZone: timeZone))` |
| `skipPreparationStep` | `session.handle(.skipPreparationStep)` |
| `fetch(t)` | `session.handle(.fetch(t, since: WatermarkRule.fetchStart(watermark: try? store.watermark(for: t), now: now()), now: now(), timeZone: timeZone))` |
| `persist(t)` | Run the three persist steps below |
| `armTimer` / `cancelTimer` | The `timers` method |
| `markKeyRejected` | `try? keyStore.markRejected()` |
| `recordSyncCompleted` | `lastSync.save(now())` |

`persist(t)` runs these steps:

1. Build `StoredRound` values from the pending rounds of `t`.
2. Fold the watermark: start from `try? store.watermark(for: t)`, then apply `WatermarkRule.advanced(previous:nextSince:now:)` with each pending round's `nextSince`, in order.
3. Call `store.commit(rounds:type:watermark:)`, then send `.persistSucceeded(t)`. If the commit throws, send `.persistFailed(t)` instead. Clear the pending rounds either way.

**Ordering:**

- `receive` appends mapped events to a FIFO queue and drains it if a drain is not already running.
- Each drained event runs `SyncCoordinator.reduce`, records a `TransitionLogEntry` with `now()`, assigns `state`, then executes the effects in order.
- Events produced while draining are queued, never handled recursively.

- [ ] **Step 1: Write the test doubles**

- `FakeStrapConnection`:
  - Has a `weak var runner: SyncRunner?` and a `link: FakeStrapDeviceLink` (Task 9).
  - Records method names in `calls: [String]`.
  - `startScan` sends `.strapDiscovered`.
  - `connect` sends `.connected(maximumWriteLength: 244, notifiable: FakeStrapDeviceLink.notifiable)`.
  - `setNotify(c, enabled:)` sends `.notifyStateChanged(c, enabled:)` back at once.
  - `write` passes `ZeppWrite(c, [UInt8](data))` to `link.device.phoneWrote` and relays every notification as `runner.receive(.connection(.notification(n.characteristic, Data(n.bytes))))`.
  - `stopScan` and `disconnect` only record.
  - With `isSilent = true`, it records calls but sends nothing.
- `RecordingTimerScheduler` records `scheduled: [(SyncTimer, Int)]` and `cancelled: [SyncTimer]`.
- `InMemoryStrapKeyStore` implements `StrapKeyStoring` with stored properties.
- `FailingRawStore(wrapping: RawStore, failingType: StrapFetchType)` throws from `commit` for `failingType` and forwards everything else.

`FakeZeppDevice` serves its seeded data whatever the requested start, so no watermark seeding is needed (API map row 10).

- [ ] **Step 2: Write the failing tests**

```swift
@MainActor struct SyncRunnerTests {
    let key = StrapAuthKey.parse("00112233445566778899aabbccddeeff")!
    let now = Date(timeIntervalSince1970: 1_791_355_320)

    struct Harness { let runner: SyncRunner; let connection: FakeStrapConnection; let store: RawStoring
                     let keyStore: InMemoryStrapKeyStore; let timers: RecordingTimerScheduler; let lastSync: LastSyncRecord }

    func makeHarness(deviceKey: StrapAuthKey? = nil, storedKey: StrapAuthKey?, store: RawStoring? = nil,
                     initialState: SyncState = SyncState(phase: .idle, retryUsed: false), silent: Bool = false) throws -> Harness
    // Seeds the fake device with DecoderFixture.all, keyed with deviceKey ?? key.
    // When `store` is nil, creates an in-memory RawStore.
    // Uses UserDefaults(suiteName: UUID().uuidString), TransitionLogRecorder(file: nil), now: { now } and TimeZone(identifier: "UTC")!.

    @Test func fullSyncReachesIdleAndCommitsEveryType() throws {
        let h = try makeHarness(storedKey: key)
        h.runner.receive(.syncRequested)
        #expect(h.runner.state == SyncState(phase: .idle, retryUsed: false))
        for type in StrapFetchType.syncOrder { #expect(try h.store.watermark(for: type) != nil) }
        #expect(h.lastSync.load() == now)
        #expect(h.connection.calls.first == "startScan")
        #expect(h.connection.calls.last == "disconnect")
        #expect(h.connection.link.device.fetchAcks.allSatisfy { $0 == 0x09 })
    }
    @Test func wrongKeyEndsInKeyRejected() throws {
        let h = try makeHarness(deviceKey: StrapAuthKey.parse("ffeeddccbbaa99887766554433221100")!, storedKey: key)
        h.runner.receive(.syncRequested)
        #expect(h.runner.state.phase == .failed(.keyRejected))
        #expect(try h.keyStore.isRejected())
    }
    @Test func missingKeyEndsInKeyMissing() throws {
        let h = try makeHarness(storedKey: nil)
        h.runner.receive(.syncRequested)
        #expect(h.runner.state.phase == .failed(.keyMissing))
    }
    @Test func authTimeoutEndsInStrapBusy() throws {
        let h = try makeHarness(storedKey: key, initialState: SyncState(phase: .active(.authenticating), retryUsed: false), silent: true)
        h.runner.receive(.timerFired(.session))
        #expect(h.runner.state.phase == .failed(.strapBusy))
        #expect(h.connection.calls.last == "disconnect")
    }
    @Test func persistFailureLeavesWatermarkUnchanged() throws {
        let inner = RawStore(container: try RawStore.makeContainer(inMemory: true))
        let h = try makeHarness(storedKey: key, store: FailingRawStore(wrapping: inner, failingType: .activity))
        h.runner.receive(.syncRequested)
        #expect(h.runner.state.phase == .failed(.persistFailed(.activity)))
        #expect(try h.store.watermark(for: .activity) == nil)
    }
    @Test func secondSyncAddsNoDuplicateRecords() throws {
        let h = try makeHarness(storedKey: key)
        h.runner.receive(.syncRequested)
        let roundsAfterFirst = try h.store.allRounds().count
        let recordsAfterFirst = RecordDeduplicator.merge(try h.store.allRounds().flatMap { try StrapRecordDecoder.decode($0) }).count
        h.runner.receive(.syncRequested)
        #expect(try h.store.allRounds().count == roundsAfterFirst)
        #expect(RecordDeduplicator.merge(try h.store.allRounds().flatMap { try StrapRecordDecoder.decode($0) }).count == recordsAfterFirst)
    }
    @Test func fetchTimerMapsToCurrentFetchType() throws {
        let h = try makeHarness(storedKey: key, initialState: SyncState(phase: .active(.fetching(.activity)), retryUsed: false), silent: true)
        h.runner.receive(.timerFired(.fetch))
        #expect(h.runner.state == SyncState(phase: .waitingForRetry(.fetchTimeout(.activity)), retryUsed: true))
        #expect(h.timers.scheduled.last?.0 == .retry)
        #expect(h.timers.scheduled.last?.1 == 10)
    }
    @Test func bluetoothOffMidFetchKeepsWatermark() throws {
        let h = try makeHarness(storedKey: key, initialState: SyncState(phase: .active(.fetching(.activity)), retryUsed: false), silent: true)
        h.runner.receive(.connection(.bluetoothPoweredOff))
        #expect(h.runner.state.phase == .failed(.bluetoothOff))
        #expect(try h.store.watermark(for: .activity) == nil)
    }
    @Test func transitionsAreLogged() throws {
        let h = try makeHarness(storedKey: key)
        h.runner.receive(.syncRequested)
        let lines = h.runner.transitionLogLines
        #expect(lines.first?.hasSuffix(" idle --syncRequested--> scanning") == true)
        #expect(lines.last?.hasSuffix(" persisting(heartRateVariability) --persistSucceeded(heartRateVariability)--> idle") == true)
    }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `-only-testing:OxygenTests/SyncRunnerTests`.

Expected: compile failure.

- [ ] **Step 4: Implement the four source files**

Follow the mapping tables and the ordering above. `TaskSyncTimerScheduler` holds `[SyncTimer: Task<Void, Never>]`. Each task runs `try await Task.sleep(for: .seconds(seconds))`, then `fired.yield(timer)`.

- [ ] **Step 5: Run the tests and confirm they pass**

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/Oxygen/Sources/Sync ios/Oxygen/Tests
git commit -m "feat(oxygen): add SyncRunner executing coordinator effects with ack-after-persist watermarks"
```

---

### Task 11: Re-sign guard

**Files:**
- Create: `ios/Oxygen/Sources/ResignGuard/ProvisioningProfileReader.swift`
- Create: `ios/Oxygen/Sources/ResignGuard/ResignStatus.swift`
- Create: `ios/Oxygen/Sources/ResignGuard/ResignReminder.swift`
- Test: `ios/Oxygen/Tests/ResignGuardTests.swift`

**Interfaces:**
- Produces:

```swift
enum ProvisioningProfileReader {
    static func expirationDate(fromProfileData data: Data) -> Date?
    static func embeddedProfileExpirationDate(bundle: Bundle) -> Date?    // reads "embedded.mobileprovision"; nil when absent
}
enum ResignStatus: Equatable, Sendable {
    case unknown
    case valid(daysRemaining: Int)
    case expiringSoon(daysRemaining: Int)
    static func evaluate(expiration: Date?, now: Date) -> ResignStatus
}
enum ResignReminder {
    static let identifier = "oxygen.resign-reminder"
    static let title = "Re-install Oxygen"
    static let body = "Oxygen stops opening tomorrow. Run it from Xcode on your Mac to renew it for 7 days."
    static func fireDate(expiration: Date, now: Date) -> Date?           // expiration − 86 400 s, or nil when that is not after now
    static func schedule(expiration: Date?, now: Date, center: UNUserNotificationCenter) async
}
```

Rules:

- **Reader:** find the byte range from `<?xml` to `</plist>` inclusive, decode it with `PropertyListSerialization`, and read `ExpirationDate` as a `Date`.
- **`evaluate`:**
  - `interval = expiration − now`.
  - `daysRemaining = max(0, Int(floor(interval / 86 400)))`.
  - `interval ≤ 172 800` gives `.expiringSoon`.
  - A nil expiration gives `.unknown`.
- **`schedule`:**
  - Always remove pending requests with `identifier` first.
  - Then add one `UNTimeIntervalNotificationTrigger(timeInterval: fireDate − now, repeats: false)` with `title` and `body`. Skip this when `fireDate` is nil.

- [ ] **Step 1: Write the failing tests**

```swift
struct ResignGuardTests {
    let now = Date(timeIntervalSince1970: 1_791_355_320)                 // 2026-10-07T06:42:00Z
    let expiry = Date(timeIntervalSince1970: 1_791_873_720)              // 2026-10-13T06:42:00Z

    func profileData(_ plistBody: String) -> Data {
        var data = Data([0x30, 0x82, 0x01])
        data.append(Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict>" + plistBody + "</dict></plist>").utf8))
        data.append(Data([0x00, 0xa0]))
        return data
    }

    @Test func readsExpirationDate() {
        let data = profileData("<key>ExpirationDate</key><date>2026-10-13T06:42:00Z</date>")
        #expect(ProvisioningProfileReader.expirationDate(fromProfileData: data) == expiry)
    }
    @Test func missingPlistOrKeyGivesNil() {
        #expect(ProvisioningProfileReader.expirationDate(fromProfileData: Data([0x01, 0x02])) == nil)
        #expect(ProvisioningProfileReader.expirationDate(fromProfileData: profileData("<key>Name</key><string>x</string>")) == nil)
    }
    @Test func statusBoundaries() {
        #expect(ResignStatus.evaluate(expiration: nil, now: now) == .unknown)
        #expect(ResignStatus.evaluate(expiration: expiry, now: now) == .valid(daysRemaining: 6))
        #expect(ResignStatus.evaluate(expiration: now.addingTimeInterval(172_800), now: now) == .expiringSoon(daysRemaining: 2))
        #expect(ResignStatus.evaluate(expiration: now.addingTimeInterval(172_801), now: now) == .valid(daysRemaining: 2))
        #expect(ResignStatus.evaluate(expiration: now.addingTimeInterval(-1), now: now) == .expiringSoon(daysRemaining: 0))
    }
    @Test func reminderFiresOneDayBeforeExpiry() {
        #expect(ResignReminder.fireDate(expiration: expiry, now: now) == Date(timeIntervalSince1970: 1_791_787_320))
        #expect(ResignReminder.fireDate(expiration: now.addingTimeInterval(86_400), now: now) == nil)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `-only-testing:OxygenTests/ResignGuardTests`.

Expected: compile failure.

- [ ] **Step 3: Implement the three files**

- [ ] **Step 4: Run the tests and confirm they pass**

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Oxygen/Sources/ResignGuard ios/Oxygen/Tests/ResignGuardTests.swift
git commit -m "feat(oxygen): add re-sign guard reading the provisioning profile expiry"
```

---

### Task 12: Raw data export

**Files:**
- Create: `ios/Oxygen/Sources/Export/CSVWriter.swift`
- Create: `ios/Oxygen/Sources/Export/ExportManifest.swift`
- Create: `ios/Oxygen/Sources/Export/ExportBundleWriter.swift`
- Test: `ios/Oxygen/Tests/ExportTests.swift`

**Interfaces:**
- Consumes: `StoredRound`, `RawStoring` (Task 7), `StrapRecordDecoder` and `RecordDeduplicator` (Task 8), and `BuildConstants` (Task 3).
- Produces:

```swift
enum CSVWriter { static func render(header: [String], rows: [[String]]) -> String }
struct ExportManifest: Encodable, Equatable {
    let appVersion: String; let upstreamKitCommit: String; let exportTimeUTC: String; let timeZoneIdentifier: String
    let recordCounts: [String: Int]; let roundCount: Int; let undecodableRoundCount: Int
}
enum ExportBundleWriter {
    static func folderName(exportTime: Date) -> String
    static func write(rounds: [StoredRound], records: [DecodedStrapRecord], undecodableRoundCount: Int,
                      transitionLogText: String, appVersion: String, upstreamKitCommit: String,
                      exportTime: Date, timeZone: TimeZone, into parentDirectory: URL) throws -> URL
    static func zip(folder: URL) throws -> URL
    @MainActor static func makeArchive(store: RawStoring, transitionLogText: String, appVersion: String,
                                       upstreamKitCommit: String, exportTime: Date, timeZone: TimeZone,
                                       into parentDirectory: URL) throws -> URL
}
```

**CSVWriter:**
- Fields are joined with `,` and lines end with `\n`.
- A field containing `,`, `"`, `\n` or `\r` is wrapped in `"`, and its inner `"` characters are doubled.

**Manifest:**
- JSON keys are the snake_case names: `app_version`, `upstream_kit_commit`, `export_time_utc`, `time_zone_identifier`, `record_counts`, `round_count`, `undecodable_round_count`.
- `record_counts` is keyed by fetch type case name.
- It is encoded with `.prettyPrinted` and `.sortedKeys`.

**Folder name:** `oxygen-export-yyyyMMdd-HHmmss`, in UTC, with locale `en_US_POSIX`.

**`write` creates the folder with these files:**

| File | Content |
|---|---|
| One `exportFileName` CSV per fetch type, 13 in total, always present | Header `["timestamp_utc"] + fieldNames(for:)`, rows sorted by timestamp |
| `rounds.csv` | Header `fetch_type,round_start_utc,received_at_utc,payload_sha256,payload_hex`, with `payload_hex` in lowercase |
| `manifest.json` | The manifest above |
| `transition-log.txt` | The transition log text |

**`zip`:** uses `NSFileCoordinator.coordinate(readingItemAt:options: .forUploading)` and copies the temporary zip to `<parent>/<folder name>.zip` inside the accessor block.

**`makeArchive`:**
- Loads `allRounds()` and decodes each round. A round that throws is counted as undecodable.
- Merges the records, writes the folder into `parentDirectory`, zips it, and returns the zip URL.
- `exportTimeUTC` uses the ISO-8601 UTC format without fractional seconds.

- [ ] **Step 1: Write the failing tests**

```swift
@MainActor struct ExportTests {
    let t0 = Date(timeIntervalSince1970: 1_791_355_320)               // 2026-10-07T06:42:00Z
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func writeExport(rounds: [StoredRound], records: [DecodedStrapRecord], timeZone: TimeZone) throws -> URL {
        try ExportBundleWriter.write(rounds: rounds, records: records, undecodableRoundCount: 0, transitionLogText: "a\n",
                                     appVersion: "0.1.0", upstreamKitCommit: String(repeating: "a", count: 40),
                                     exportTime: t0, timeZone: timeZone, into: try temporaryDirectory())
    }

    @Test func csvQuoting() {
        #expect(CSVWriter.render(header: ["a", "b"], rows: [["1", "x,y"], ["2", "say \"hi\""], ["3", "l1\nl2"]])
                == "a,b\n1,\"x,y\"\n2,\"say \"\"hi\"\"\"\n3,\"l1\nl2\"\n")
    }
    @Test func folderNameUsesUTC() {
        #expect(ExportBundleWriter.folderName(exportTime: Date(timeIntervalSince1970: 1_791_355_333.512)) == "oxygen-export-20261007-064213")
    }
    @Test func emptyStoreExportsHeadersOnly() throws {
        let folder = try writeExport(rounds: [], records: [], timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.count == 16)
        for type in StrapFetchType.allCases {
            let text = try String(contentsOf: folder.appendingPathComponent(type.exportFileName), encoding: .utf8)
            #expect(text == CSVWriter.render(header: ["timestamp_utc"] + StrapRecordDecoder.fieldNames(for: type), rows: []))
        }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("manifest.json"))) as! [String: Any]
        #expect(Set(manifest.keys) == ["app_version", "upstream_kit_commit", "export_time_utc", "time_zone_identifier",
                                       "record_counts", "round_count", "undecodable_round_count"])
        #expect((manifest["record_counts"] as! [String: Int]).values.allSatisfy { $0 == 0 })
        #expect(manifest["time_zone_identifier"] as? String == "Europe/Berlin")
    }
    @Test func timestampsAreUTCInAnyTimeZone() throws {
        let round = StoredRound(fetched: FetchedRound(fetchType: .activity, roundStart: t0, payload: Data([0x01, 0x02, 0x03]),
                                                      receivedAt: t0, nextSince: nil))
        let record = DecodedStrapRecord(fetchType: .activity, timestamp: t0,
                                        fields: StrapRecordDecoder.fieldNames(for: .activity).map { StrapRecordField(name: $0, value: "0") },
                                        receivedAt: t0)
        let folder = try writeExport(rounds: [round], records: [record], timeZone: TimeZone(identifier: "Pacific/Kiritimati")!)
        let activity = try String(contentsOf: folder.appendingPathComponent("activity.csv"), encoding: .utf8)
        #expect(activity.split(separator: "\n")[1].hasPrefix("2026-10-07T06:42:00Z,"))
        let rounds = try String(contentsOf: folder.appendingPathComponent("rounds.csv"), encoding: .utf8)
        #expect(rounds.split(separator: "\n")[1] ==
                "activity,2026-10-07T06:42:00Z,2026-10-07T06:42:00Z,039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81,010203")
    }
    @Test func zipProducesPKArchive() throws {
        let folder = try writeExport(rounds: [], records: [], timeZone: .gmt)
        let zipURL = try ExportBundleWriter.zip(folder: folder)
        #expect(try Data(contentsOf: zipURL).prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]))
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `-only-testing:OxygenTests/ExportTests`.

Expected: compile failure.

- [ ] **Step 3: Implement the three files**

- [ ] **Step 4: Run the tests and confirm they pass**

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Oxygen/Sources/Export ios/Oxygen/Tests/ExportTests.swift
git commit -m "feat(oxygen): export raw rounds, decoded CSVs and manifest as a zip"
```

---

### Task 13: Screen text and record summary

**Files:**
- Create: `ios/Oxygen/Sources/Screens/SyncStatusText.swift`
- Create: `ios/Oxygen/Sources/Screens/RecordSummary.swift`
- Create: `ios/Oxygen/Sources/Screens/ResignStatusText.swift`
- Test: `ios/Oxygen/Tests/ScreenTextTests.swift`

**Interfaces:**
- Consumes: `SyncState` (Task 4), `DecodedStrapRecord` (Task 8), `ResignStatus` (Task 11).
- Produces:

```swift
enum SyncStatusText { static func make(state: SyncState, lastSyncCompletedAt: Date?, now: Date, timeZone: TimeZone) -> String }
struct RecordSummaryRow: Equatable, Identifiable, Sendable {
    let fetchType: StrapFetchType; let count: Int; let oldest: Date?; let newest: Date?
    var id: UInt8 { fetchType.rawValue }
}
enum RecordSummary { static func make(records: [DecodedStrapRecord]) -> [RecordSummaryRow] }   // 13 rows, in sync order
enum ResignStatusText {
    static func line(_ status: ResignStatus) -> String
    static func banner(_ status: ResignStatus) -> String?
}
```

**Status copy.** `<name>` means `displayName`.

| State | Text |
|---|---|
| idle, no last sync | `Not synced yet` |
| idle, last sync on the same calendar day in `timeZone` | `Synced HH:mm` |
| idle, last sync on an earlier day | `Synced d MMM HH:mm` (locale `en_US_POSIX`) |
| scanning | `Looking for the strap` |
| connecting | `Connecting to the strap` |
| authenticating | `Authenticating` |
| preparing | `Preparing the strap` |
| fetching(t) | `Fetching <name>` |
| persisting(t) | `Saving <name>` |
| waitingForRetry(any) | `Connection lost, retrying in 10 s` |
| failed(bluetoothOff) | `Bluetooth is off` |
| failed(bluetoothUnauthorized) | `Bluetooth permission denied. Allow it in Settings.` |
| failed(strapNotFound) | `Strap not found` |
| failed(strapBusy) | `Strap busy: turn off Bluetooth for Zepp` |
| failed(keyRejected) | `Key rejected: paste a new key` |
| failed(keyMissing) | `Paste the strap's auth key` |
| failed(linkLost) | `Connection lost` |
| failed(fetchTimeout(t)) | `The strap stopped sending <name>` |
| failed(persistFailed(t)) | `Could not save <name>` |

**Re-sign copy.** "day" is singular when N is 1, and "days" otherwise.

| Status | Line | Banner |
|---|---|---|
| `.unknown` | `Re-sign status unknown` | nil |
| `.valid(N)` | `Re-install within N days` | nil |
| `.expiringSoon(N)` with N ≥ 1 | `Re-install within N days` | `Oxygen expires in N days. Re-install it from Xcode.` |
| `.expiringSoon(0)` | `Re-install today` | `Oxygen expires today. Re-install it from Xcode.` |

- [ ] **Step 1: Write the failing tests**

```swift
struct ScreenTextTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let now = Date(timeIntervalSince1970: 1_791_367_200)              // 2026-10-07T10:00:00Z
    let lastSync = Date(timeIntervalSince1970: 1_791_355_320)         // 2026-10-07T06:42:00Z

    @Test func idleSameDayShowsTime() {
        #expect(SyncStatusText.make(state: SyncState(phase: .idle, retryUsed: false), lastSyncCompletedAt: lastSync, now: now, timeZone: berlin) == "Synced 08:42")
    }
    @Test func idleEarlierDayShowsDate() {
        let twoDaysEarlier = lastSync.addingTimeInterval(-172_800)
        #expect(SyncStatusText.make(state: SyncState(phase: .idle, retryUsed: false), lastSyncCompletedAt: twoDaysEarlier, now: now, timeZone: berlin) == "Synced 5 Oct 08:42")
    }
    @Test(arguments: [
        (SyncPhase.idle, "Not synced yet"),
        (.active(.fetching(.heartRateVariability)), "Fetching heart rate variability"),
        (.active(.persisting(.pai)), "Saving PAI"),
        (.waitingForRetry(.linkLost(during: .connecting)), "Connection lost, retrying in 10 s"),
        (.failed(.strapBusy), "Strap busy: turn off Bluetooth for Zepp"),
        (.failed(.keyMissing), "Paste the strap's auth key"),
        (.failed(.fetchTimeout(.temperature)), "The strap stopped sending skin temperature"),
    ])
    func statusCopy(_ phase: SyncPhase, _ text: String) {
        #expect(SyncStatusText.make(state: SyncState(phase: phase, retryUsed: false), lastSyncCompletedAt: nil, now: now, timeZone: berlin) == text)
    }
    @Test func summaryHasThirteenRowsInSyncOrder() {
        let records = [
            DecodedStrapRecord(fetchType: .activity, timestamp: lastSync, fields: [], receivedAt: now),
            DecodedStrapRecord(fetchType: .activity, timestamp: now, fields: [], receivedAt: now),
        ]
        let rows = RecordSummary.make(records: records)
        #expect(rows.map(\.fetchType) == StrapFetchType.syncOrder)
        #expect(rows[0] == RecordSummaryRow(fetchType: .activity, count: 2, oldest: lastSync, newest: now))
        #expect(rows[1] == RecordSummaryRow(fetchType: .manualHeartRate, count: 0, oldest: nil, newest: nil))
    }
    @Test func resignCopy() {
        #expect(ResignStatusText.line(.valid(daysRemaining: 6)) == "Re-install within 6 days")
        #expect(ResignStatusText.line(.expiringSoon(daysRemaining: 1)) == "Re-install within 1 day")
        #expect(ResignStatusText.banner(.expiringSoon(daysRemaining: 1)) == "Oxygen expires in 1 day. Re-install it from Xcode.")
        #expect(ResignStatusText.line(.expiringSoon(daysRemaining: 0)) == "Re-install today")
        #expect(ResignStatusText.banner(.valid(daysRemaining: 6)) == nil)
        #expect(ResignStatusText.line(.unknown) == "Re-sign status unknown")
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `-only-testing:OxygenTests/ScreenTextTests`.

Expected: compile failure.

- [ ] **Step 3: Implement the three files**

- [ ] **Step 4: Run the tests and confirm they pass**

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/Oxygen/Sources/Screens ios/Oxygen/Tests/ScreenTextTests.swift
git commit -m "feat(oxygen): add status, summary and re-sign copy for the foundation screen"
```

---

### Task 14: StrapConnection, the foundation screen and the composition root (owner, on device)

**Files:**
- Create: `ios/Oxygen/Sources/Sync/StrapConnection.swift`
- Create: `ios/Oxygen/Sources/Screens/FoundationScreen.swift`
- Modify: `ios/Oxygen/Sources/App/OxygenApp.swift` (replace the Task 3 body)

**Interfaces:**
- Consumes: everything above, plus API map rows 3 and 11.
- Produces:

```swift
@MainActor final class StrapConnection: NSObject, StrapConnecting, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let peripheralIdentifierKey = "oxygen.strapPeripheralIdentifier"
    let events: AsyncStream<StrapConnectionEvent>
    init(defaults: UserDefaults)
}
```

No state restoration identifier is passed, because state restoration is out of scope (spec section 12.2).

`StrapConnection` behaviour, adapted from `HelioConnection.swift` with the adaptation header:

- **Central manager:**
  - `CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])`.
  - `centralManagerDidUpdateState` yields `.bluetoothPoweredOn`, `.bluetoothPoweredOff` or `.bluetoothUnauthorized`.
- **`startScan()`** (API map row 11):
  - When the central is not powered on, yield the matching state event and return.
  - When `retrievePeripherals(withIdentifiers:)` finds the stored identifier, adopt that peripheral and yield `.strapDiscovered` without scanning.
  - Otherwise run an unfiltered scan, `scanForPeripherals(withServices: nil, options: nil)`. Accept the first peripheral whose `CBAdvertisementDataLocalNameKey` (or `peripheral.name`) passes `ZeppDeviceModel.match(advertisedName:) == .helioStrap`, store its identifier, and yield `.strapDiscovered`.
  - "Strap busy" is not detected here; it comes from the session at auth.
- **`connect()`:**
  - Call `central.connect(peripheral, options: nil)`.
  - On `didConnect`, run `discoverServices(nil)`, then `discoverCharacteristics(nil, for:)` for each service.
  - Map each discovered characteristic to the `ZeppCharacteristic` whose `uuidString` matches, comparing the full 128-bit form case-insensitively. Never touch `ZeppGATT.firmwareUpdateServiceUUID`.
  - When every service has reported its characteristics, yield `.connected(maximumWriteLength: peripheral.maximumWriteValueLength(for: .withoutResponse), notifiable: <the mapped characteristics whose properties contain .notify or .indicate>)`.
- **`setNotify(c, enabled:)`:**
  - Calls `peripheral.setNotifyValue(enabled, for:)`.
  - `didUpdateNotificationStateFor` yields `.notifyStateChanged(c, enabled: characteristic.isNotifying)`.
- **`write(data, to:)`:**
  - Use `.withoutResponse` when the characteristic's properties contain `.writeWithoutResponse`, otherwise `.withResponse`.
  - Writes queue first in, first out. Without-response writes are sent only while `peripheral.canSendWriteWithoutResponse` is true, and the queue resumes in `peripheralIsReady(toSendWriteWithoutResponse:)`.
  - A write to a characteristic the strap does not have is dropped.
- **Disconnects:**
  - `didFailToConnect` yields `.connectionFailed`.
  - `didDisconnectPeripheral` yields `.linkLost`, unless `disconnect()` was called since the last connect. That case is tracked by the explicit `isDisconnectRequested` property.
- **Notifications:** `didUpdateValueFor` yields `.notification(<mapped characteristic>, value)`. Values from unmapped characteristics are ignored.

`FoundationScreen` is a single `List`, with sections in this order:

1. **Status:** `SyncStatusText.make(state: runner.state, lastSyncCompletedAt: lastSync.load(), now: Date(), timeZone: .current)`, plus the re-sign banner when it is non-nil.
2. **Strap:** battery from `deviceSummary` (`Battery N%`, or `Battery unknown`).
3. **Auth key:**
   - A `SecureField` labelled "Auth key", and a **Save key** button.
   - An invalid parse shows `The key must be 32 hexadecimal characters.`
   - A valid key runs `keyStore.save`, then `runner.receive(.authKeyEntered)`, then clears the field.
4. **Data:** one row per `RecordSummaryRow`, showing display name, count, and oldest to newest in `d MMM HH:mm` local time.
5. **Sync:** a **Sync** button that sends `.syncRequested`.
6. **Export:**
   - An **Export** button that runs `ExportBundleWriter.makeArchive` into `FileManager.default.temporaryDirectory`, then presents a `ShareLink` for the zip.
   - The log text is `TransitionLog(lines: runner.transitionLogLines).renderedText()`.
7. **Re-sign:** `ResignStatusText.line`.

The record summary is recomputed from `store.allRounds()` every time `runner.state` becomes idle, and once on appear.

`OxygenApp` builds these, in this order:

1. The on-disk `RawStore.makeContainer(inMemory: false)`.
2. `RawStore`.
3. `StrapKeyStore(service: StrapKeyStore.productionService)`.
4. `TransitionLogRecorder` with `TransitionLogFile(url: <Application Support>/Oxygen/transition-log.txt)`, creating the directory if needed.
5. `AsyncStream.makeStream(of: SyncTimer.self)` and `TaskSyncTimerScheduler`.
6. `StrapConnection(defaults: .standard)`.
7. `LastSyncRecord(defaults: .standard)`.
8. `SyncRunner`, with `initialState: SyncCoordinator.initialState(hasKey: (try? keyStore.load()) != nil, keyRejected: (try? keyStore.isRejected()) ?? false)`, `now: Date.init` and `timeZone: .current`.

It then wires:

- Two `.task` loops: `for await` over `connection.events` → `runner.receive(.connection(event))`, and over the timer stream → `runner.receive(.timerFired(timer))`.
- `.onChange(of: scenePhase)`: `.active` sends `runner.receive(.syncRequested)`.
- A launch `.task`: request notification authorization (`.alert`), then run `ResignReminder.schedule(expiration: ProvisioningProfileReader.embeddedProfileExpirationDate(bundle: .main), now: Date(), center: .current())`.

- [ ] **Step 1: Implement the three files**

- [ ] **Step 2: Regenerate and run the full test suite**

Run: `xcodegen generate --spec ios/Oxygen/project.yml`, then all tests.

Expected: `** TEST SUCCEEDED **`, with every suite from Tasks 3–13 passing.

- [ ] **Step 3: Run on the iPhone and paste the key**

- On the Mac, run `pbcopy < ~/.oxygen/helio-auth-key.txt`, then paste on the phone with Universal Clipboard. Run Oxygen from Xcode.
- Expected on first launch:
  - The notification prompt appears.
  - The status reads `Paste the strap's auth key`.
- Paste the key and tap **Save key**. Expected: the status reads `Not synced yet`.

- [ ] **Step 4: First sync on the device**

- Tap **Sync** and allow the Bluetooth prompt.
- Expected: the status passes through `Looking for the strap`, `Connecting to the strap`, `Authenticating`, `Preparing the strap`, then `Fetching …` / `Saving …` for each type, and ends with `Synced HH:mm`.
- Expected: the Data rows show non-zero counts for at least activity and heart rate variability.

- [ ] **Step 5: Commit**

```bash
git add ios/Oxygen/Sources
git commit -m "feat(oxygen): wire CoreBluetooth connection, foundation screen and composition root"
```

---

### Task 15: On-device acceptance (owner)

**Files:**
- Create: `docs/superpowers/notes/<YYYY-MM-DD>-foundation-acceptance.md`, named with the date the 7-day run ends.
- Modify: `docs/superpowers/specs/2026-10-06-oxygen-design.md`, the section 14 row "Capability check result".

**Interfaces:**
- Consumes: the installed build from Task 14.
- Produces: a table `| Criterion | Result (pass/fail) | Date | Evidence |` with one row per spec criterion 12.5.1–12.5.8.

- [ ] **Step 1: Criterion 1, install and launch**

Record Task 14 Step 3 as the evidence.

- [ ] **Step 2: Criterion 8, capability check**

- Tap **Sync**, lock the phone within 2 seconds, wait 90 seconds, then unlock.
- Expected: the status shows `Synced HH:mm`, with a time inside the locked interval.
- Record the result in spec section 14 as `bluetooth-central signs with the Personal Team; a locked-phone sync completed on <date>`. If the sync did not complete, record `failed` and note that sync is foreground-only.

- [ ] **Step 3: Criterion 3, reproduce the failure reasons**

| Reason | How to trigger it | Expected status | Then |
|---|---|---|---|
| `bluetoothOff` | Settings → Bluetooth off (not Control Center), open Oxygen | `Bluetooth is off` | Bluetooth on: status leaves the failure |
| `strapBusy` | Settings → Zepp → Bluetooth on, open Zepp until it shows the strap connected, then open Oxygen | `Strap busy: turn off Bluetooth for Zepp` | Turn Zepp's Bluetooth off again |
| `linkLost` | Tap **Sync**, and while it says `Fetching`, put the strap in a closed metal tin | `Connection lost, retrying in 10 s`, then `Strap not found` | Take the strap out and sync |
| `keyRejected` | Save the key `00000000000000000000000000000000`, then tap **Sync** | `Key rejected: paste a new key`, still shown after a relaunch | Save the real key |
| App killed mid-sync | Tap **Sync**, and while it says `Fetching`, swipe Oxygen away in the app switcher, then reopen it | The new sync ends with `Synced HH:mm`, and no Data row count is lower than before | Nothing |
| Airplane mode mid-sync | Tap **Sync**, and while it says `Fetching`, turn on airplane mode with Bluetooth included | `Bluetooth is off` | Turn airplane mode off, then sync |

Export once afterwards and confirm that `transition-log.txt` contains `--linkLost--> waitingForRetry(`.

- [ ] **Step 4: Criteria 2 and 4, a night of wear and seven days**

- Wear the strap overnight and open Oxygen the next morning.
- Expected: these rows are non-zero: activity, sleep, heart rate variability, resting heart rate, skin temperature and stress.
- Keep opening Oxygen at least once a day for 7 days. On day 8, export and AirDrop the zip to the Mac, then run:

```bash
unzip -o ~/Downloads/oxygen-export-*.zip -d ~/oxygen-captures/acceptance
python3 -I -c "
import csv, datetime, glob
path = sorted(glob.glob('$HOME/oxygen-captures/acceptance/*/activity.csv'))[-1]
times = [datetime.datetime.fromisoformat(r['timestamp_utc'].replace('Z', '+00:00')) for r in csv.DictReader(open(path))]
for a, b in zip(times, times[1:]):
    if (b - a).total_seconds() > 120: print(a.isoformat(), '->', b.isoformat())
"
```

Expected: every printed gap matches a time the strap was off the wrist or charging.

- [ ] **Step 5: Criterion 5, export contents**

Expected:
- The unzipped folder holds 13 type CSVs, `rounds.csv`, `manifest.json` and `transition-log.txt`.
- Each value in `record_counts` in `manifest.json` equals the matching Data row count on the screen at export time.

- [ ] **Step 6: Criterion 6, re-install keeps data**

Note the Data row counts and the status line. Run Oxygen again from Xcode over Wi-Fi.

Expected: the counts are the same, or higher after a sync, and the last-sync time is the same before you sync.

- [ ] **Step 7: Criterion 7, re-sign guard accuracy**

```bash
security cms -D -i "$(ls -t ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision | head -1)" | plutil -extract ExpirationDate raw -
```

Expected: the whole days between now and that date equal the N in `Re-install within N days`.

- [ ] **Step 8: Commit**

```bash
git add docs/superpowers
git commit -m "docs: record Oxygen foundation acceptance results"
git push
```
