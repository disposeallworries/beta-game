# Roguelite direction: a garden that changes between runs

**Design proposal — these mechanics are not implemented.** The current game is still the complete parkour course. This plan builds around its deliberate movement, planted ledge grabs, and readable jumps.

## Recommended loop

Start a short expedition with three hearts and no relics. Cross a garden sector, reach its sanctuary, and choose one of three relics. Follow the safe route or take a visibly harder detour for extra seeds. A fall costs one heart and returns you to the last checkpoint; losing the final heart ends the run and shows your distance, rewards, and a clear **Retry** button.

Keep the existing course for the first prototype: its eight checkpoints already divide a two-to-four-minute run into useful sectors. Offer relics at checkpoints 2, 4, and 6 so choices do not interrupt every landing. Winning reaches Sunset Garden; failing still leaves something useful to unlock.

Manual reset should cost a heart during an expedition, just like a fall, so it cannot become a free rescue. A separate Practice mode can retain the current unlimited checkpoint reset. Pause, inspect choices, and restart from menus without time pressure; keep difficulty in the platforming.

## Relics that change decisions without inflating speed

Choose a small pool first, with clear effects and icons:

- **Chalk Gloves:** extend the quick-vault follow-up window from 0.22 to 0.32 seconds. More forgiving timing, with the same movement speed and climb path.
- **Second Root:** prevent one fatal fall per run, consuming the relic and returning the blob to its checkpoint with one heart. Use a brief fade rather than an upward launch animation.
- **Heartbud:** gain one maximum heart and heal one heart for this run.
- **Seed Magnet:** collect nearby seeds without landing precisely on them. Risky routes still require reaching their platforms.
- **Steady Soles:** reduce wind push in later storm rooms; it never changes walk speed, gravity, or jump height.

Relics last for the run. Avoid mandatory speed stacking, extra jump height, or double jumps: those would undermine the calmer movement and require different obstacle spacing. Successful combinations should offer forgiveness, recovery, information, or better rewards.

## Risk and lasting progression

Put optional seeds on marked side platforms, with the reward visible before the jump. Bank collected seeds at sanctuaries. A run ending loses only unbanked seeds, making “one more detour” a real choice.

Spend banked seeds on blob colors, scarves, garden decorations, new room themes, and additional relic choices. New unlocks broaden future runs; permanent movement-speed upgrades would make old jumps feel inconsistent. Show exactly what was banked and what was lost on the result screen.

## Atmosphere and replayability

Later, assemble runs from hand-authored, tested parkour rooms with compatible entry and exit points. Give every run a seed so a good route can be replayed or shared. Start with garden courtyards, twilight ruins, and a wind tower, each with a clear landmark and its own soundscape.

Add one readable hazard at a time: crumbling platforms with visible cracks and a warning shake, periodic wind with drifting leaves, or moving stone gates with a predictable rhythm. A distant storm approaching the final sector can provide a climax without requiring combat.

## First milestone: three features

1. Three-heart expedition rules, fair checkpoint recovery, and a run-result/retry screen.
2. Relic choices at three existing checkpoints, using the first four relics above.
3. Collectible seeds, sanctuary banking, and one cosmetic unlock.

Keep the current fixed map while those choices become fun. Modular rooms, weather hazards, biome variation, and daily seeds belong to the next milestone.
