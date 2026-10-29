# PC / Android parity status — version 0.3

**Exact original-game parity is not complete.** This version also replaces the prototype arena with the original captured base/terrain, source collision shapes and entrance travel/timing. Read the repository root `BUILD-STATUS.json` for the latest device/build evidence.

| Area | Current implementation | Open parity work |
| --- | --- | --- |
| Original geometry | 2,133 nonempty source meshes decoded; original prefab hierarchies now preserve large reference IDs exactly | 215 captured base/terrain render instances now load; all other world regions, LOD/streaming and generated systems remain open |
| Menu | Original logo, source 3D menu stage/camera, recovered fonts, dark sidebar, orange stripe, four main choices and five local save slots | Exact camera/aspect behavior, animated character/tool poses, appearance UI, online matchmaking and complete settings |
| HUD | Prototype top banner removed; compass, sector progress, lower-left tool/container, bottom tool slots and lower-right balance/icon | Complete original status indicators, hotbar assignment, context prompts, map, vehicle HUD and responsive comparisons |
| Progression | Zero-dollar fresh slots, Toothbrush starter, original recovered tool prices, only purchased tools unlock | Full original upgrade tree and every original progression effect |
| Money | Finite earned balance; deposits credit collected mass × source dollars-per-kilogram; purchases subtract prices | Original decimal accounting/display transitions, all material/reward types |
| Saves | Five independent schema-2 slots; prototype schema-1 save is not imported | Full original world/session schema, all entities, all settings and compatibility |
| Cleaning | Terrain-backed continuous raised dust surface; swept brush contact changes local geometry and transfers finite mass to cargo | Exact original procedural dust algorithm, 0.06 source mesh spacing (current mobile field is 0.20), clumps, polish, substrate types and all feedback |
| Movement and collision | Source gravity/speed/jump settings; 31 original starting-area collision shapes; raycast ground contact; original door travel/duration and capsule entry test | Original spherical-world grounding, all regions, dynamic rigid bodies and identical physics-engine behavior |
| Materials | Source resource textures/fonts restored, tiling and normal maps, dedicated packed-regolith and visor-eye reconstruction | Exact custom shader/postprocessing behavior, color/lighting/material comparisons |
| Character skin | Original 21,771 vertices, four weights/indices per vertex and 58 bind matrices imported into Skeleton3D/Skin | Humanoid muscle animation retargeting, idle/walk/jump/sweep clips, hand IK and exact tool poses |
| Animations | Six original serialized clips preserved; read-only PC sampling helper prepared | No original evaluated idle motion captured yet; PC reference remained in gameplay/build panel during the attempt |
| Tool models | Original names, models, held transforms and visual scales | Full original stroke/grip logic and upgrades |
| Construction | Building-tool ownership gate and visual prefab placement | Original build menus, fit/grid/collider validation, costs, removal/move modes and complete simulation |
| Robots, vehicles, factories, belts and power | Original assets available; earlier free prototype robot/rover shortcuts removed | Full operational recreation of these original systems |
| Story/contracts/manual/extra activities | Reference assets and APIs retained | Full interactions and content presentation remain unfinished |
| Touch | Movement, look, sweep, jump, interact, equipment and pause controls adapted to the reference palette | Full multi-pointer regression, remapping and parity across screen sizes |
| Controller | Basic mappings present | Physical-controller verification and complete UI focus/navigation |
| Native Android | ARM64 local APK build and installation workflow | Full game regression, performance/thermal profiling and complete system parity |

The original Unity project/source was not completely recovered. Decompiled code still contains unresolved operations. A complete “copy and convert” of all original gameplay cannot be claimed from the current files. The reconstruction brief lists the remaining systems rather than treating placeholder bodies or static models as working functionality.

Tooling references: [official Godot release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable), [Android export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html), [UnityPy source](https://github.com/K0lb3/UnityPy). These establish tooling, not original-game fidelity.

Version-0.3 capture and limitations: `analysis/WORLD-REFERENCE-2026-10-29.md`.
