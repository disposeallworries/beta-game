# Validation

Use the **Godot 4.5.1** executable. Replace `godot` below with its path if necessary. Run from the project root.

```sh
godot --headless --editor --path . --import
godot --headless --path . --script tests/controller_test.gd
godot --headless --path . --script tests/vault_test.gd
godot --headless --path . --script tests/game_test.gd
godot --headless --path . --script tests/course_route_test.gd
godot --headless --path . --quit-after 240
```

- `controller_test.gd`: 69 checks for walking/sprinting, diagonal and camera-relative input, air momentum, short/full jumps, jump buffer, coyote time, collision, wall slide/jump/drop/release, ledge hang/climb/drop/clearance/cooldown, events and respawn resets.
- `vault_test.gd`: 49 checks for the quick follow-up window, held-forward flow, fast and regular climb durations, pre-collision momentum carry, bounded boost, halfway assistance (including rising jumps), no downward snapping, drop priority, cooldowns, destination/headroom/path clearance, an obstruction appearing mid-vault, and reset behavior.
- `game_test.gd`: 75 checks for original course geometry and checkpoints, imported model and all four animation clips, animation blending, controls, timer, checkpoint progression, death/normal respawn, completion/restart, HUD, camera collision/FOV/landing dip and dust lifecycle. It also exercises the real character animation during a quick vault and boosted exit.

- `course_route_test.gd`: 31 assertions replaying a deterministic, controls-only run from Start to Finish. Its 2,602 fixed ticks visit all six checkpoints in order, land on all 17 route platforms, jump between shaft walls, and clear three ledges: one quick follow-through vault and two halfway-height assists. All three exits carry forward momentum. After the initial spawn it never teleports the player or assigns movement state/velocity. The recorded input is in `tests/route.json`.

All **224 assertions passed** on the exact 4.5.1 release. These tests run the actual game scripts. Fixture tests and checkpoint state-transition tests are distinguished from complete course traversal.

The main scene was also rendered with the Compatibility/OpenGL renderer on Godot 4.5.1 and visually inspected for model appearance, platform colors, shadows and UI layout. Desktop screenshots are in `docs/`.

The default `godot` command on the build machine was a newer version; all final import, gameplay and integration checks used the explicit 4.5.1 binary. If a newer editor has already generated an import cache, close it and remove only the generated `.godot/` folder before reimporting with 4.5.1.

On a CI system that disallows writes to its standard user directories, set `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` to writable locations before invoking Godot. This is not needed on a normal desktop.
