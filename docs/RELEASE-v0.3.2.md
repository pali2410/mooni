## Native Android reconstruction — v0.3.2

ARM64 debug APK, installed and checked on a Xiaomi Pad 8 with Android 16. This remains an incomplete independent reconstruction of Moon Sweepers.

Included: original captured starting base/terrain, 215 render instances, 31 source collision shapes, moving entrance door, source-based step-height/slope settings, touch controls, finite dust collection, earned deposits and normal tool purchases. Purchased tool ownership now survives JSON save/reload. Unlimited money and max-upgrade presets are removed.

Validation: current isolated tests cover terrain raycast, door/capsule entry, entrance steps, dust mass conservation, deposit earnings, purchase deductions and purchase save/reload. The installed v0.3.2 APK hash was checked against the built file. Earlier v0.3.0 tablet testing collected 0.50 kg and deposited it for $0.50; the base interior was reached on the tablet with v0.3.1.

Unfinished: original animations/IK, exact lighting/shaders, complete world and dust simulation, functional machinery/robots/vehicles, all upgrades/contracts and multiplayer. See the repository's parity checklist.

**Download:** `MoonSweepers-Rebuild-arm64.apk` below.

SHA-256: `2454b3f9f991478ae538a9a76c4d3062334d5fd34d748047ae98b51f8d901a16`
