# Validation

Use **Godot 4.5.1**. Replace `godot` with its executable path when necessary. Run from the project root:

```sh
godot --headless --editor --path . --import
godot --headless --path . --script tests/controller_test.gd
godot --headless --path . --script tests/vault_test.gd
godot --headless --path . --script tests/contact_animation_test.gd
godot --headless --path . --script tests/game_test.gd
godot --headless --path . --script tests/course_route_test.gd
godot --headless --path . --quit-after 240
```

| Suite | Checks | Coverage |
| --- | ---: | --- |
| `controller_test.gd` | 76 | Reduced walk/sprint/acceleration, diagonal and camera-relative movement, momentum, full/short jumps, coyote time, input buffer, collisions, wall actions, no-teleport ledge catches, climb and respawn. |
| `vault_test.gd` | 56 | Quick window, 0.48/0.32-second durations, pre-impact momentum, scaled boost/caps, halfway assistance, no height snap or upward exit, clearance, blocked path, drop priority and reset. |
| `contact_animation_test.gd` | 186 | Actual world-space hand tips stay on the lip in four directions over reachable catch heights/gaps; neutral root during contact; no double jump displacement; hand release, limb lengths, foot bracing and slower animation cadence. |
| `game_test.gd` | 157 | Expanded course size/route/native shapes, every checkpoint's standing clearance and stability under actual physics, imported clips, input/timer, camera, particles, HUD, finish/restart and animated vault integration. |
| `course_route_test.gd` | 59 | Full controls-only traversal of all 45 route platforms and eight checkpoints, shaft wall jumps, one supported quick vault, two halfway assists, bounded exit momentum and finish. |

**534 checks passed with zero failures** on `4.5.1.stable.official.f62fdbde1`. The full course replay uses 13,475 fixed ticks (about 112 seconds of gameplay); it does not teleport the player or assign its movement state or velocity after the initial spawn. Its recorded inputs are in `tests/route.json`.

The game and hanging/pull-up poses were also rendered using Godot's Compatibility/OpenGL renderer. Screenshots in `docs/` include the starting courtyard, sky-gate route, map overview and a close-up contact fixture. The overview disables fog for a clear distant view; gameplay uses normal fog.

The editable ZIP excludes generated `.godot` caches. If a newer editor already imported the project, close it and regenerate that cache using 4.5.1. CI machines with read-only user directories can set `XDG_DATA_HOME`, `XDG_CONFIG_HOME` and `XDG_CACHE_HOME` to writable locations before running the commands.
