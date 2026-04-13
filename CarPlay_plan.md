# WheelBro CarPlay Integration Plan

## Goal

Mirror the TTE view cards onto a CarPlay `CPInformationTemplate` screen that
becomes active as soon as the user connects their BLE/OBD-II device.
The iOS app continues to work exactly as it does today; CarPlay is an
additive, read-only consumer of the same live data.

---

## Step 0 — Apple Entitlement (do this first, it takes days/weeks)

CarPlay requires a per-app entitlement that Apple must grant manually.

1. Log in to developer.apple.com → Account → Additional Capabilities
2. Request **"Driving Task"** entitlement
   - Entitlement key: `com.apple.developer.carplay-driving-task`
   - Justification: OBD-II telemetry monitor that assists drivers with
     fuel range and vehicle health awareness
3. Once approved, download the updated provisioning profile and add the
   entitlement key to the app's `.entitlements` file

> While waiting for approval you can prototype and test everything using
> **Xcode's built-in CarPlay Simulator** (Xcode → Open Developer Tool →
> Simulator → I/O → External Displays → CarPlay). It works without the
> real entitlement during development.

---

## Step 1 — Xcode Project Changes

### 1a. Add Entitlement
Create `wheelbro/wheelbro.entitlements` (or add to existing):

```xml
<key>com.apple.developer.carplay-driving-task</key>
<true/>
```

Enable "CarPlay" in the target's Signing & Capabilities tab so Xcode
knows to include it in the provisioning profile.

### 1b. Info.plist — Declare CarPlay Scene

Add a second `UIApplicationSceneManifest` entry alongside the existing
iOS window scene:

```xml
<key>CPTemplateApplicationSceneSessionRoleApplication</key>
<array>
    <dict>
        <key>UISceneClassName</key>
        <string>CPTemplateApplicationScene</string>
        <key>UISceneDelegateClassName</key>
        <string>$(PRODUCT_MODULE_NAME).CarPlaySceneDelegate</string>
        <key>UISceneConfigurationName</key>
        <string>CarPlay Configuration</string>
    </dict>
</array>
```

---

## Step 2 — CarPlay Scene Delegate

Create `wheelbro/CarPlay/CarPlaySceneDelegate.swift`.

This is the entry point Apple calls when the user plugs into CarPlay.
It receives a `CPInterfaceController` (the handle for pushing/popping
templates onto the car screen) and holds a reference to the main
`CarPlayCoordinator` that owns all template logic.

```swift
import CarPlay

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    var interfaceController: CPInterfaceController?
    var coordinator: CarPlayCoordinator?

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        // Grab the shared managers from the iOS app delegate / environment
        coordinator = CarPlayCoordinator(interfaceController: interfaceController)
        coordinator?.start()
    }

    func templateApplicationScene(
        _ scene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        coordinator?.stop()
        coordinator = nil
        self.interfaceController = nil
    }
}
```

---

## Step 3 — CarPlay Coordinator

Create `wheelbro/CarPlay/CarPlayCoordinator.swift`.

The coordinator owns the template lifecycle and observes the same
`OBDDataManager`, `BluetoothManager`, `LocationManager`, and
`MotionManager` instances that the iOS UI already uses. It pushes a
`CPInformationTemplate` as the root and refreshes it whenever data
changes or BLE connection state changes.

### Behavior

| BLE State | CarPlay screen shows |
|---|---|
| Disconnected | Placeholder: "Connect OBD-II adapter in the WheelBro app" |
| Connected, ignition off | "Connected — turn ignition ON" + static zeroed cards |
| Connected, data flowing | Live TTE + all active cards (see below) |

### Key responsibilities

- Hold a strong reference to the `CPInterfaceController`
- Set up a polling/observation loop (1-second timer, same cadence as
  `TTEView`'s `tickCount`) to rebuild `CPInformationItem` arrays
- Push the initial template on `start()`, invalidate on `stop()`
- Observe `bleManager.isConnected` to switch between the disconnected
  placeholder and the live data template

---

## Step 4 — CarPlay Template Layout

### Template type: `CPInformationTemplate`

`CPInformationTemplate` displays a title, an array of
`CPInformationItem` (label/value pairs), and up to two action buttons.
This is the closest CarPlay equivalent to the `OBDValueCard` grid.

### Cards to mirror from TTEView (active, non-commented cards)

These map directly to `CPInformationItem(title:detail:)` pairs:

| iOS card | CarPlay label | Value source |
|---|---|---|
| TTE (giant block) | "Time to Empty" | `obdManager.calculateTimeToEmpty(...)` |
| DTE | "Distance to Empty" | `"\(obdManager.distanceToEmpty, format: "%.1f") mi"` |
| Fuel Level | "Fuel Level" | `"\(obdManager.fuelLevel, format: "%.1f")%"` |
| Speed | "Speed" | `"\(obdManager.speed, format: "%.0f") mph"` |
| Pitch / Roll | "Pitch / Roll" | `"\(pitch)° Up/Down  \(roll)° Left/Right"` (single item, combined string) |
| Heading | "Heading" | `"\(headingText) \(compassPoint)"` |
| Altitude | "Altitude" | `"\(altitude) ft"` |
| Latitude | "Latitude" | `"\(lat, format: "%.5f") N/S"` |
| Longitude | "Longitude" | `"\(lon, format: "%.5f") E/W"` |
| DTC | "Fault Codes" | `obdManager.errorCodes` (e.g. "None" or "P0128 P0420") |
| VIN | "VIN" | `obdManager.vin` |

> Cards that are currently commented out in TTEView (RPM, Oil Temp,
> Coolant Temp, Battery) are omitted from CarPlay for now. They can be
> added back to both TTEView and CarPlay simultaneously when re-enabled.

### Template title

Use the same dynamic status label from TTEView's `statusLabel`:
- "Simulator ON"
- "Connected to \(peripheralName)"
- "Connected — turn ignition ON"
- BLE connection status string while scanning

### Action buttons (optional, up to 2)

CarPlay `CPInformationTemplate` supports action buttons. Consider:
- No buttons needed in v1 (read-only display, no user interaction required)
- Possible future: "Dismiss Fault" or "Refresh" button

---

## Step 5 — Data Observation / Refresh Strategy

CarPlay templates are **not data-binding aware** — you must call
`interfaceController.updateRootTemplate(_:animated:)` (or
`template.updateItems(_:)` if the API allows it) manually to push new
values to the screen.

Recommended approach: **1-second `DispatchSourceTimer`** in the
coordinator (same interval as the iOS `tickCount` heartbeat) that
rebuilds the `[CPInformationItem]` array from current manager state and
calls the update API.

```swift
// Inside CarPlayCoordinator
private var refreshTimer: DispatchSourceTimer?

func startRefreshTimer() {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: 1.0)
    timer.setEventHandler { [weak self] in self?.refreshTemplate() }
    timer.resume()
    refreshTimer = timer
}

func refreshTemplate() {
    let items = buildInformationItems()   // reads from managers
    infoTemplate.items = items            // CPInformationTemplate.items is settable
    infoTemplate.title = currentTitle()
}
```

> Check whether `CPInformationTemplate.items` is directly settable in
> the CarPlay framework version targeting your iOS deployment target
> (iOS 17+). If not, call `interfaceController.updateRootTemplate` with
> a fresh template instance.

---

## Step 6 — Wiring Managers to the Coordinator

The iOS app currently creates manager instances once in `ContentView`
and injects them via `.environment()`. The CarPlay coordinator needs
access to these same singletons.

Options (pick one):

**Option A — App-level singletons (recommended for this use case)**
Promote `OBDDataManager`, `BluetoothManager`, `LocationManager`, and
`MotionManager` from environment-injected instances to `static shared`
singletons. The coordinator accesses them via `OBDDataManager.shared`,
etc. No architectural churn — the SwiftUI environment injection stays
the same, just pointing to the shared instance.

**Option B — Pass through AppDelegate**
Store manager references on `AppDelegate` (or a top-level `AppState`
object). The `CarPlaySceneDelegate` grabs them from there on connect.

Either approach requires zero changes to the existing manager logic —
only where they're instantiated changes.

---

## File Checklist

```
wheelbro/
└── wheelbro/
    ├── wheelbro.entitlements           ← NEW: carplay-driving-task key
    ├── Info.plist                      ← EDIT: add CPTemplateApplicationScene
    ├── WheelBroApp.swift               ← EDIT: if promoting managers to singletons
    ├── CarPlay/                        ← NEW directory
    │   ├── CarPlaySceneDelegate.swift  ← NEW
    │   └── CarPlayCoordinator.swift    ← NEW
    └── Managers/
        ├── OBDDataManager.swift        ← EDIT: add `static let shared`
        ├── BluetoothManager.swift      ← EDIT: add `static let shared`
        ├── LocationManager.swift       ← EDIT: add `static let shared`
        └── MotionManager.swift         ← EDIT: add `static let shared`
```

---

## Testing Without a Car

1. Run on a physical iPhone (or simulator)
2. In Xcode Simulator: **I/O → External Displays → CarPlay**
3. The CarPlay window opens — you should see your template
4. Enable Simulator mode in WheelBro Settings to generate fake OBD data
5. Verify the CarPlay template refreshes every second with live values

---

## Open Questions / Decisions Needed

- [ ] **Singleton promotion** — confirm Option A (shared singletons) is
      acceptable before implementation begins
- [ ] **Disconnected state** — show a placeholder template, or push no
      template and let CarPlay show a default empty state?
- [ ] **Entitlement approval** — has the Driving Task entitlement been
      requested yet?
- [ ] **Minimum deployment target** — CarPlay template API stabilized
      well before iOS 17, so no changes expected here

---

## Implementation Order

1. Apply for entitlement (async, do immediately)
2. Decide on singleton vs. AppDelegate approach for manager access
3. Xcode project: add entitlement file + Info.plist scene entry
4. Build `CarPlaySceneDelegate` (thin — just lifecycle hooks)
5. Build `CarPlayCoordinator` with disconnected placeholder template
6. Add 1-second refresh timer + `buildInformationItems()` from managers
7. Wire BLE connect/disconnect to switch between placeholder and live template
8. Test end-to-end in CarPlay Simulator with Simulator mode on
9. Test end-to-end with a real OBD-II dongle
