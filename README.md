# Mint Blob Parkour · Godot 4.5.1

A native, offline Godot conversion of the supplied **Mint Blob Parkour.html** game. The original embedded GLB character and its four animations are included. No Three.js, browser wrapper, plug-ins, package installation, or network access is needed to play.

## Run

1. Install **Godot 4.5.1 Standard** (GDScript version; .NET is unnecessary).
2. Extract the complete project folder. In Godot, choose **Import** and select `project.godot`.
3. Let Godot import the model, then press **F5**. Click in the game to capture the mouse.

The project uses the Compatibility renderer, runs physics at 120 Hz, and starts at a resizable 1280 × 720. The main scene is `scenes/main.tscn`. When opening in 4.5.1, allow that version to generate its own `.godot` cache; caches from newer Godot versions are not included.

## Controls

| Key | Action |
| --- | --- |
| W / A / S / D | Move relative to the camera |
| Shift | Sprint; sustained grounded running builds speed from 9.5 to 13 m/s |
| Space | Jump, jump away from a wall, or climb a grabbed ledge |
| Release Space early | Shorten a normal jump |
| W / ↑ / Space immediately after a grab | Quick vault with a speed boost; holding W through the grab also works |
| S / Ctrl | Let go of a wall or ledge |
| Mouse | Orbit the camera after clicking the game |
| Esc | Release the mouse; click to recapture |
| R | Respawn at the current checkpoint, keeping the timer |
| Enter | Start a new run after completing the course |

The timer begins with WASD or Space. Reach the gold platform to finish. Holding Shift and jumping near platform edges helps clear the wider gaps. Jump toward a wall, then press Space again to push away; alternate walls in the shaft to gain height. Ledges grab automatically when your hands reach their tops. Keep W held through a grab, or follow up with W, ↑ or Space within 0.22 seconds, to vault in 0.24 seconds instead of doing the regular 0.95-second pull-up. The vault keeps your approach speed and adds 1.5 m/s, capped at 14.5 m/s (minimum exit speed 5.2 m/s). If half your body is already above the lip, a 0.18-second step-over helps you clear it automatically, even while rising. Both paths require clear headroom and standing space; S/Ctrl still lets you drop. Waiting at a ledge retains the normal pull-up. Keep Space held for full jump height.

## Movement and features

- All 19 solid course pieces, their original dimensions and colors, six checkpoints, checkpoint disks, and finish flag.
- Camera-relative acceleration, sprint buildup, air momentum, buffered jumps, coyote time, variable jump height, and terminal fall speed.
- Wall sliding, momentum-sensitive wall jumps, same-wall reattachment lockout, dropping and away-input release.
- Ledge grabbing, hanging, headroom checks, quick follow-through vaults with momentum boosts, halfway-above assistance, regular automatic/manual climbing, and drop cooldown.
- Original idle/walk/run/jump clips, speed blending, hand/foot contact poses for walls and ledges, and wall-jump/drop pose overlays.
- Jump, landing, wall-contact and sprint dust; soft shadows, distance fog, camera landing dip, automatic following, obstacle avoidance and speed-dependent FOV.
- Checkpoint, time and speed display; control guide; start and completion prompts; death respawn; full restart.

Respawning also clears stale movement timers and buffered input, preventing a prior jump or wall state from leaking into the new spawn. Lighting is tuned for Godot's color pipeline so the source's pastel palette remains visible.

## Project layout

- `scripts/game.gd`: input, run timer, checkpoints, respawn and completion.
- `scripts/player.gd`: the source game's axis-separated AABB controller, ported at its original fixed timestep to preserve jump distances and wall/ledge tuning.
- `scripts/course.gd`: course construction, matching Godot collision shapes, lighting and fog.
- `scripts/blob_visual.gd`: blending of the original imported clips and procedural contact poses.
- `scripts/follow_camera.gd`, `dust.gd`, `game_hud.gd`: camera, particle pool and native UI.
- `assets/mint_blob.glb`: character extracted directly from the uploaded HTML.

The course is generated at startup from its original coordinates; edit `course.gd` to change platforms. Input actions are registered by `game.gd` without an external setup step. No progress is saved between runs, matching the original game.

## Validation

Tested using **Godot 4.5.1.stable.official.f62fdbde1**: 224 automated assertions passed, including quick vaults, halfway assistance, and a full controls-only course traversal. See `TESTING.md` for checks and reproducible commands.

To distribute a standalone game, install the matching **4.5.1 export templates**, then use Godot's **Project → Export** for your target platform. The included files are the editable project, not an operating-system-specific executable.
