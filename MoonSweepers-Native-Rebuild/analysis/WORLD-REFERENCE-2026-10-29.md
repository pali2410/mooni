# Original gameplay environment capture

The original PC game was inspected on its own Unity main thread using read-only getters and existing IL2CPP field metadata. No PC balance, entity state, save, authentication or game binary was modified by this capture. `pc-world-capture/scene.json` records the results and method-level failures.

The base export's SpawnOutpost prefab contains a missing ConnectedLunarBase prefab reference. The live game creates TheCollector and clipped geometry at runtime. The Android prototype's flat arena and manually positioned kiosk/props therefore did not reproduce the actual starting environment.

The completed capture contains 587 nearby visible mesh instances, 97 runtime mesh buffers and 31 relevant non-trigger colliders. The new world packages 215 render instances: the original TheCollector base and four generated terrain chunks. Source mesh matches use both name and vertex count, with no ambiguous or unresolved matches in this selected environment. Generated meshes preserve submesh boundaries. Instance transforms retain the exact captured positions, rotations and scales, translated to a local coordinate frame at the intake. Runtime material color, texture references, metallic and smoothness values are retained; original custom Unity shaders still require separate reconstruction.

The 31 physics shapes come from the original scene: 25 boxes and 6 mesh colliders, including stable bedrock and the combined collector collision shell. Earlier trial collision generated from visible meshes incorrectly blocked the doorway with a decorative sun shade. Those trial shapes are replaced by the actual collision definitions. The original bedrock proxy is approximately 0.10 m below the visible surface at the tested starting point; this difference is preserved.

The entrance's two leaf meshes and box colliders move together. Closed/open frame-space positions and 0.55-second opening duration come from the running MoonCollectorDoor. The 1.25-second presence hold and smoothstep motion follow the readable scalar portions of its recovered FixedUpdate. Godot's character and physics behavior is still a new implementation; copying shapes does not establish identical PhysX behavior.

The dust patch now follows sampled original terrain heights. Cleaning uses a physics ray against the original colliders and rejects structural-wall contacts, replacing the old infinite-plane intersection. Dust mass, geometry and stroke behavior still use the reconstruction's finite heightfield algorithm and are not the full source dust simulation.

The PC save used for inspection contains user-built machinery. Saved robots, factories, conveyors, canisters, player meshes, old dust contours and personal dynamic displays are excluded from the starting scene. Their original gameplay behavior remains unfinished. This capture covers the starting base area, not the entire spherical world or a new terrain generator.

Existing schema-2 Android balances, equipment and surface state are retained. A one-time world-revision migration relocates players from the old prototype layout to a safe spawn outside the original base. Android saves were copied to `android-before-world-update` before installation. No original PC save was reset.

Reproduction: run `moon-mod/capture-pc-world.py` while the original PC game is in gameplay, followed by `moon-mod/prepare-captured-world.py`. The capture helper preserves the last completed report when an attempt fails. The isolated native smoke test checks zero-dollar starter progression, dust mass conservation, deposits, purchase deductions, original terrain raycast height and capsule collision against the closed/open doorway.

Tablet traversal caught missing entrance-step handling. The native walker now checks full capsule clearance up to the recovered MoonWalker StepHeight of 0.62 m, casts down to a walkable landing and uses the original 30-degree slope limit. A regression test approaches the entrance from the exterior bedrock height and must climb the steps and pass the open doorway. This is a tested reconstruction of step handling, not recovered original PhysX code.

Save reload normalization converts JSON numeric equipment IDs to unique valid integer catalog IDs. This fixes owned tools becoming unavailable after restart; the isolated save/reload regression purchases a tool, serializes/parses the state and checks that selection and ownership persist. Existing duplicate starter IDs are consolidated.
