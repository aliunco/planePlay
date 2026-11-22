# Bluetooth Multiplayer — Integration Plan

## Status: architecture only, not functional yet

This project ships a **complete transport abstraction** and a **stub Bluetooth
transport**. Bluetooth matches do **not** work today:

- `scripts/multiplayer/bluetooth_transport.gd` reports `is_supported() == false`
  on every platform and refuses to connect.
- The main menu's "Bluetooth Match" button is disabled and says it needs a
  plugin.
- Nothing in the gameplay layer knows Bluetooth exists, so adding a native
  bridge later requires **no gameplay changes**.

Two-player **local** multiplayer (same device, shared screen) and player-vs-AI
are fully playable today.

---

## 1. How the game consumes input

```
PlayerPlaneController ─┐
AIController ──────────┼──> PlaneInput { turn, fire, launch } ──> Airplane
RemotePlaneController ─┘                                          (movement,
                                                                   firing,
                                                                   damage)
```

`Airplane` pulls exactly one `PlaneInput` per physics tick from its attached
`AirplaneController`. A transport never touches airplane code: it pushes
`PlaneInput` snapshots into a `RemotePlaneController`, and reads local snapshots
out of the local controller.

The transport interface (`scripts/multiplayer/multiplayer_transport.gd`):

| Method | Purpose |
| --- | --- |
| `connect_to_peer(config)` | start discovery/advertising, returns false if unsupported |
| `disconnect_from_peer()` | tear the link down |
| `send_input(player_id, input)` | send one frame of local intent |
| `input_received(player_id, input)` signal | one frame of remote intent |
| `get_connection_state()` | `DISCONNECTED / SEARCHING / CONNECTING / CONNECTED / FAILED` |
| `get_status_text()` | human-readable status for the UI |
| `is_supported()` | whether this build can even try |

Wire it into the match like this (already the shape used by `GameManager`):

```gdscript
var transport := BluetoothTransport.new()      # or LocalTransport / WifiTransport
var controller := RemotePlaneController.new()  # pilot for the remote airplane
transport.deliver_to(controller)               # forwards input_received -> controller
# each tick: transport.send_input(1, local_controller.get_plane_input(delta))
```

`RemotePlaneController` zeroes its input after 0.6 s without packets, so a
dropped link cannot leave a plane turning forever.

`LocalTransport` is a working loopback implementation. Use it to validate the
whole remote-input path (including the 0.6 s timeout) without any platform
plugin.

### Why not Godot's high-level `MultiplayerAPI`?

`MultiplayerAPI` (ENet/WebSocket peers + RPCs) assumes an IP socket and a known
peer address. Bluetooth needs its own **device discovery**, pairing/permission
handling and RFCOMM/GATT socket lifecycle, which `MultiplayerAPI` does not
provide. Discovery and connection management are therefore explicit, and only
the final byte pipe is implemented natively.

---

## 2. Wire format

`bluetooth_transport.gd` already contains platform-independent, unit-testable
framing (`encode_frame` / `decode_frame`):

```
byte 0: magic  0xA5
byte 1: flags  bit0 = fire, bit1 = launch
byte 2: turn   0..255  ->  -1.0 .. 1.0   (0.5 = neutral)
byte 3: seq    0..255, wraps (drop out-of-order frames)
```

4 bytes per frame, sent at 30 Hz (~15 B/s of payload plus MTU overhead) — well
inside Bluetooth LE / RFCOMM limits. If more state is needed later, switch to
`[u16 length][packed JSON]` and keep the same interface.

---

## 3. Android

### What is needed

1. **Godot Android plugin** (Kotlin/Java) exposing a `GodotPlugin` singleton.
2. **Manifest permissions**
   - API 31+ (`Android 12+`): `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`
     (declare `android:usesPermissionFlags="neverForLocation"` on `SCAN` if you
     do not need location).
   - API ≤ 30: `BLUETOOTH`, `BLUETOOTH_ADMIN`, and
     `ACCESS_FINE_LOCATION` for discovery results.
   - Mark both as `required="true"` for the game build.
3. **Runtime permission requests** for the API 31+ permissions before any scan
   or connect call (`ActivityCompat.requestPermissions`).
4. **Export setup**: build the `.aar`, place it in
   `android/plugins/`, and enable it in the Android export preset
   (`Plugins → BluetoothLink`).

### Plugin surface to implement

```kotlin
class BluetoothLink : GodotPlugin() {
    override fun getPluginName() = "BluetoothLink"

    @UsedByGodot fun discover()                                   // start scanning
    @UsedByGodot fun stopDiscovery()
    @UsedByGodot fun host(serviceName: String)                    // listen (server)
    @UsedByGodot fun connectTo(deviceAddress: String)             // client
    @UsedByGodot fun send(frame: ByteArray)
    @UsedByGodot fun close()
    @UsedByGodot fun isConnected(): Boolean

    // Emit to GDScript with:
    //   emitSignal("device_found", name)
    //   emitSignal("connected", peerName)
    //   emitSignal("input", frame)
    //   emitSignal("error", message)
}
```

Implementation notes:

- Use **RFCOMM** (`BluetoothDevice.createRfcommSocketToServiceRecord(UUID)`) with
  one fixed UUID for the game. Classic RFCOMM has higher throughput and lower
  complexity than GATT for a real-time game; BLE is acceptable but adds MTU
  negotiation and write-queue back-pressure.
- Host: `BluetoothServerSocket.listenUsingRfcommWithServiceRecord(name, UUID)`.
- Client: `createRfcommSocketToServiceRecord` → `socket.connect()` on a worker
  thread (never the main thread).
- Discovery: `BluetoothAdapter.startDiscovery()` +
  `BroadcastReceiver(BluetoothDevice.ACTION_FOUND)`.
- Keep all socket I/O on a background thread and post results to Godot with
  `GodotPlugin`'s signal mechanism (Godot callbacks must be on the main thread).
- Close sockets in `onMainDestroy` / `disconnect`.

### GDScript side

```gdscript
func connect_to_peer(config := {}) -> bool:
    var plugin := Engine.get_singleton("BluetoothLink")
    if plugin == null:
        return false
    plugin.connect("device_found", _on_device_found)
    plugin.connect("input", _on_bytes)
    plugin.discover()
    return true

func send_input(player_id: int, input: PlaneInput) -> void:
    Engine.get_singleton("BluetoothLink").send(encode_frame(input))
```

Then set `_state = State.CONNECTED` from the plugin's `connected` signal and
forward `decode_frame(bytes)` to `input_received`.

---

## 4. iOS

iOS has no public raw-RFCOMM API for third-party apps. The supported route is
**MultipeerConnectivity** (`MCSession` + `MCNearbyServiceAdvertiser` /
`MCNearbyServiceBrowser`), which uses Bluetooth and peer Wi-Fi transparently.
It discovers and connects peers by display name; there is no device-address
pairing step.

### What is needed

1. An iOS **GDScript plugin** (`.gdip` + framework) OR a small static library
   compiled into custom iOS engine templates (Godot iOS plugins require building
   the engine from source with the plugin included).
2. `Info.plist` entries:
   - `NSLocalNetworkUsageDescription`
   - `NSBonjourServices` = `["_godotplane._tcp", "_godotplane._udp"]` (match your
     service type)
3. Objective-C/Swift bridge with the same surface as the Android plugin:

```objc
- (void)discover;              // MCNearbyServiceBrowser startBrowsingForPeers
- (void)host:(NSString *)name; // MCNearbyServiceAdvertiser startAdvertisingPeer
- (void)connectTo:(NSString *)peerId;
- (void)send:(NSData *)frame;  // [session sendData:toPeers:withMode:]
- (void)close;
```

`MCSessionDelegate` → `didReceiveData` is where you call back into Godot with
`engine->push_script_signal("input", ...)`.

### Notes

- iOS requires **Bluetooth + Local Network** permission prompts; handle denial
  gracefully (return `FAILED` with a message).
- Discovery of nearby devices cannot run while the app is backgrounded.
- Test on two physical devices; the Simulator has no Bluetooth.

---

## 5. Recommended path to shipping

| Step | Work | Risk |
| --- | --- | --- |
| 1 | Ship single-player + local 2P (done) | none |
| 2 | Add `WifiTransport` (UDP + broadcast discovery, same interface) | low, no native code |
| 3 | Android `BluetoothLink` plugin (RFCOMM) | medium, ~1–2 days |
| 4 | iOS MultipeerConnectivity plugin (needs custom engine templates) | high, 3–5 days |
| 5 | Optional: host migration, reconnect, rematch handshake | medium |

A LAN transport is worth doing before Bluetooth: it exercises the same
transport/controller wiring on real devices, is testable in CI, and gives iOS a
shipping multiplayer option without custom engine templates.

---

## 6. Gameplay integration checklist (when a plugin exists)

1. `BluetoothTransport.is_supported()` returns true; `connect_to_peer` performs
   discovery and resolves to `CONNECTED`.
2. `GameManager.Mode.BLUETOOTH` already spawns `RemotePlaneController` for
   player 2 and follows the local plane with the camera.
3. Feed the transport:
   - each physics tick: `transport.send_input(1, local_input)`
   - `transport.input_received → remote_controller.push_input(...)`
4. Show `get_status_text()` in the HUD while connecting.
5. Enable the menu's "Bluetooth Match" button and call the same
   `play_requested(mode, difficulty)` flow.
6. Handle disconnect: `peer_left` → pause the match and offer "Main menu".

---

## 7. How to test without hardware

- Set the game mode to `LOCAL_VERSUS` for two-player rules on one device.
- Use `LocalTransport` to exercise `RemotePlaneController`, framing
  (`encode_frame`/`decode_frame`) and the 0.6 s input timeout in a headless
  test. Both are pure GDScript and run in CI.
- `tools/smoke_test.gd` already covers the controller/plumbing paths.
