# Reconstruction brief

Target: reproduce the original PC game's behavior and visual design in a native Android implementation with touch controls and normal earned-money progression.

The current project is a Godot rebuild. It is not a recovered complete Unity source project. Keep the original game, raw extracted data and new implementation separate.

## Current environment

`game/assets/pc_world/world.json` records 215 selected original render instances, four runtime-generated terrain chunks, 31 original collision definitions and the captured sliding-door frame/leaf positions. `scripts/captured_world.gd` loads these into the native world.

All transforms consistently reflect Unity's Z basis into Godot and translate the starting area to a local coordinate system. Source meshes are matched by name and vertex count; the selected environment has no unresolved matches. Generated binary meshes preserve submesh boundaries. Custom Unity shaders still require recreation.

Copy actual physics definitions rather than inferring collision from every visible mesh. A decorative sun shade incorrectly blocked the entrance during an earlier trial; the current implementation uses the original non-trigger shapes instead.

The walker uses source gravity/speed/jump settings, a 30-degree slope limit and capsule-clearance tests up to the original 0.62 m step height. Godot physics is still a separate implementation. Entrance movement tests cover a closed door blocking the capsule, an open door allowing entry and climbing from exterior bedrock onto the entrance steps.

Cleaning raycasts against physical ground rather than an infinite mathematical plane. The dust patch follows sampled terrain heights but still uses a reconstructed finite heightfield algorithm, with 0.20 m spacing instead of the original 0.06 m target.

## Saves and progression

Fresh slots start with zero dollars and the Toothbrush. Tool catalog prices, capacity and held transforms come from recovered data. Deposits award collected mass times the source dollars-per-kilogram setting. Purchases debit balance. JSON numeric tool IDs are converted to valid unique integers on restore so ownership and selection survive restarting.

Schema-1 unlimited-money prototype saves are not imported. Schema-2 progress is retained; the world-revision migration moves an old prototype-layout player to a safe spawn. Tests use separate local test files and must never inject test funds into a player's saves.

## Remaining acceptance work

- Original humanoid clips, idle/walk/jump/sweep animation, hand grips and IK.
- Exact custom shaders, source lighting, shadows, sky and postprocessing comparisons.
- Original dust-generation/removal algorithms, clumps, polish and feedback.
- Complete world generation, streaming, regions and spherical grounding.
- Working vehicles, robots, factories, conveyors, power and logistics.
- All upgrades, contracts/story, extra activities, appearance UI and settings.
- Multiplayer, physical-controller verification and comprehensive device/performance testing.

Do not label a frozen machine model as functional, a successful APK build as gameplay parity, or reduced decompiler errors as recovered executable source. Record the tested version alongside each device result.
