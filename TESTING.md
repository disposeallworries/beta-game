# Validation · Godot 4.5.1

Run from the project root with the **4.5.1 Standard** executable. Replace `godot` with its actual path if needed.

```sh
godot --headless --editor --path . --import
godot --headless --path . --script tests/run_state_test.gd
godot --headless --path . --script tests/expedition_map_test.gd
godot --headless --path . --script tests/defense_arena_test.gd
godot --headless --path . --script tests/expedition_hud_test.gd
godot --headless --path . --script tests/combat_animation_test.gd
godot --headless --path . --script tests/expedition_game_test.gd
godot --headless --path . --script tests/expedition_routes_test.gd
godot --headless --path . --script tests/full_run_test.gd
godot --headless --path . --quit-after 240
```

**All 1,655 checks passed** across the complete suite on `4.5.1.stable.official.f62fdbde1`.

## What the new checks prove

- `run_state_test.gd`: lifetime, accepted mana/capacity, normal/forced portal, shared costs, exact-zero loss, victory, frozen terminal states and clean resets.
- `expedition_map_test.gd`: all resource locations, finite channeling, standing/height/speed requirements, full-core conservation, unique swords, portal gating and stable anchors.
- `defense_arena_test.gd`: real projectile sweeps and walls, melee cone/range/cooldowns/weapon ownership, two monster types, attacks, four waves, tower auto-fire costs, damage, victory/loss and synchronous depletion. Includes a controls-only four-wave battle with real mana costs.
- `expedition_hud_test.gd`: phase objectives, resources, transition/results, warnings, mouse-transparent controls, minimum-size layout and radar/heading markers.
- `combat_animation_test.gd`: held-blade attachment, attack return, no attack root displacement, core charge and parkour-contact priority.
- `expedition_game_test.gd`: actual main-scene harvesting, pickups, portal placement and inventory transfer, active-world collision changes, combat costs, zero-mana and tower outcomes, pause/focus recovery and Enter restart. Isolated encounter placement is explicitly a fixture.
- `expedition_routes_test.gd`: four independent controls-only recordings from the real sanctuary. They reach all seven pools, both sword tiers, every designated route platform, and the wall-jump shaft. The prepared-return recording is one continuous route with **310 mana, a blade and a physical return to the portal in 93.89 seconds**, within the 180-second limit.
- `full_run_test.gd`: one uninterrupted actual main-scene run, using engine movement actions and the public attack API. It replays preparation, crosses the portal and wins four waves. After ready it never edits the player's position/state/velocity, resource values, enemies or damage.

The full run wins with **28 kills, 30 real sword attacks, 167.5 mana and 152 tower health** after about 94 seconds gathering, three seconds transferring, and 72 seconds fighting. Its inputs are deterministic and its pool sources really deplete. Default mechanics and resource costs remain enabled.

## Existing parkour regression checks

```sh
godot --headless --path . --script tests/controller_test.gd
godot --headless --path . --script tests/vault_test.gd
godot --headless --path . --script tests/contact_animation_test.gd
godot --headless --path . --script tests/game_test.gd
godot --headless --path . --script tests/course_route_test.gd
```

These retain coverage for the calmer movement, hand-contact/climb geometry, camera, dust, original GLB clips and practice course. `game_test.gd` intentionally loads `scenes/practice.tscn`; `expedition_game_test.gd` and `full_run_test.gd` load the actual new main scene.

Screenshots in `docs/` include the exploration HUD, actual pool channeling, portal transfer and monster arena. Screenshots can use deliberate camera/encounter placement; gameplay reachability and victory claims come from the separate controls-only tests.

The ZIP excludes generated `.godot` caches. Import with 4.5.1 before running command-line suites from a fresh extraction. CI machines with read-only user directories may set `XDG_DATA_HOME`, `XDG_CONFIG_HOME` and `XDG_CACHE_HOME` to writable locations. No external services or credentials are needed.
