# Hikili (WoTLK 3.3.5a)

`Hikili` is a lightweight priority helper inspired by Hekili, adapted for WoW 3.3.5a API.

## Included right now

- UI focused on next action (default: 1 icon, optional preview up to 3).
- Suggestions are filtered to your learned spells from spellbook.
- Saved frame position and visual settings.
- Slash commands for lock/unlock and appearance.
- Priority profiles for all Wrath classes and all 3 talent trees per class:
  - Death Knight (`DEATHKNIGHT:1/2/3`)
  - Druid (`DRUID:1/2/3`)
  - Hunter (`HUNTER:1/2/3`)
  - Mage (`MAGE:1/2/3`)
  - Paladin (`PALADIN:1/2/3`)
  - Priest (`PRIEST:1/2/3`)
  - Rogue (`ROGUE:1/2/3`)
  - Shaman (`SHAMAN:1/2/3`)
  - Warlock (`WARLOCK:1/2/3`)
  - Warrior (`WARRIOR:1/2/3`)

Fallback mode remains as a safety net if a profile returns no castable action.

## Slash commands

- `/hikili` - help
- `/hikili lock`
- `/hikili unlock`
- `/hikili show`
- `/hikili hide`
- `/hikili toggle`
- `/hikili scale 1.0`
- `/hikili alpha 1.0`
- `/hikili size 52`
- `/hikili spacing 6`
- `/hikili queue 1` (1-3)
- `/hikili rescan`
- `/hikili reset`

## File layout

- `Hikili.toc`
- `Core.lua`
- `PriorityEngine.lua`
- `UI.lua`

## Notes

This is a practical baseline implementation for WoTLK private-server/client workflows.  
To expand class coverage, add more profile handlers in `PriorityEngine.lua` with the key format `CLASS:TREE_INDEX`.
