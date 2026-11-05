# Plank Rush: Design Document

## Current Status

Two levels are in development. The core loop is playable end to end: collect planks, build a bridge over water, get through hazards, unlock the next level, finish, and race for a place on the global leaderboard.

**Implemented**
- Plank counter and automatic bridge building over water
- Bonus walls (multiply planks) and penalty walls (take a share away)
- Multi-level progression: finishing a level unlocks the next one, reveals its content and moves the respawn point forward (checkpoint per level)
- Hazards: spike traps, geysers, swinging logs, whirlpools, current zones, predator-fish zones, trampolines, falling platforms
- Persistent global leaderboard (top 20) on DataStore + OrderedDataStore, with a live list of players currently running
- Live run timer that pauses on death and never counts loading time
- Finish screen with personal best and attempt count
- Level gating: locked levels are hidden on the client and blocked by collision groups and server-side checks
- Session analytics with a developer-only panel
- Mobile and desktop controls

**Not implemented yet**
- Game modes (Full Run / Single Level), lobby, level journal
- Per-level leaderboards
- Save data for full runs
- Mobile adaptation of the UI (controls are done, interface layout is not)
- Stickers

## Game Modes

**Full Run**: the player completes all levels back-to-back without stopping. Global time is measured from the start of level 1 to the finish of the last level. Only players who complete every level qualify for the global leaderboard.

**Single Level**: the player selects and practices one level independently. Results go to that level's leaderboard but don't affect global time.

## Core Loop

1. Collect planks scattered across the level.
2. Run out over the water. Planks are placed automatically under the player, one per step.
3. Run out of planks over water and you fall in. Respawn at the last unlocked level's checkpoint.
4. Hazards and walls change how many planks you carry, so the route and the risks you take decide the outcome.
5. Reach the end of a level to unlock the next one. Reach the final finish to set a time.

## Hazards

| Hazard | Behavior | Effect on the player |
|---|---|---|
| Spike trap | Rises, stays up, retracts on a timer; each spike starts at a random offset | Lethal while up |
| Geyser | Launches the player up and in a random direction | Non-lethal; can help or hurt, the risk is the point |
| Swinging log | Knocks the player away along its swing direction | Drops all carried planks, non-lethal |
| Whirlpool | Pulls the player to the center | Lethal |
| Predator fish | Patrols its zone, chases a player who enters, attacks on a cooldown | Damages HP and steals planks; lethal if HP reaches 0. Tuned per zone through attributes |
| Current zone | Pushes the player and any planks placed inside it downstream | Displacement |
| Trampoline | Launches the player across gaps | Displacement |
| Falling platform | Bobs up and down; after a short warning it drops if someone is still standing on it | Lethal if it drops the player into water |
| Bonus wall | Multiplies carried planks | Positive |
| Penalty wall | Takes a share of carried planks | Negative |

Every hazard is checked against the player's unlocked level, so a trigger from a locked level can never affect them.

## Screens

**Main Menu (Lobby)**
- Global leaderboard (top 20 best full runs)
- Player's personal best across the whole game
- "Level Select" button opens the level journal
- No save yet: single "Play" button
- Save exists: "Continue" and "Start Over" buttons

**Level Journal**: scrollable screen, per level:
- That level's leaderboard
- Player's personal best on that level
- "Play" button
- Arrows to switch between levels

**In-Game HUD**

Left side (kept minimal, especially for mobile):
- Plank counter
- Personal best (whole game)

Right panel, content depends on mode:
- Full Run: global leaderboard + "currently racing" with a live global timer
- Single Level: that level's leaderboard + a live timer for that level

It's the same UI component in both cases. The server sends the client a mode flag along with the data, and the client simply renders whatever it receives.

## Leaderboards
- **Global**: ranked by total time for a fully completed run. Only players who finished the last level qualify.
- **Per-level**: ranked by time on a specific level. Shown in the level journal and in the right panel during single-level play.
- **Personal**: best time per level and for the full run. Shown in the HUD and the level journal.

Today there is a single flat global top by best single run. Splitting it by mode is the next big step.

## Server-Side Mode Tracking
The server stores a per-player mode flag:
```lua
playerMode[userId] = "full"
-- or
playerMode[userId] = { mode = "level", levelId = 2 }
```
`LeaderboardService` broadcasts data based on the player's current mode. The client doesn't know where the data comes from, it just renders what it's given.

## Save Data
Progress is saved only in the context of a full run:
```lua
{
    currentLevel = 4,
    accumulatedTime = 80.0,   -- seconds
    levelBestTimes = { 18.4, 21.2, 19.8, 20.6 }
}
```
On "Continue," the timer resumes from the accumulated time. "Start Over" wipes the save.

## Rewards
Stickers are awarded for completing each level. Details TBD.

## Visual Style
- Panels: RGB(40, 40, 40) at 0.35 transparency, 5 px corner radius
- Primary text: white
- Accent (times, records): RGB(100, 255, 120)
- Gold (first place, countdown, level-up label): RGB(255, 200, 70)
- Bonus feedback: RGB(52, 255, 29). Penalty feedback: RGB(255, 0, 0) / RGB(255, 80, 80)

## Development Priorities
1. New levels and hazards. Content first
2. Per-level leaderboards
3. Lobby and level journal, plus mobile UI adaptation
4. Save system for full runs
5. Stickers

## Ideas Under Consideration
- **Level progress indicator.** Show the level number next to each player's name in the "currently racing" list. A progress bar under the player's own entry is a possible follow-up, but the approach isn't settled
- **Checkpoints inside a level.** The infrastructure for level-based respawn exists; open question is whether planks collected before a mid-level checkpoint stay collected after a death
- **Tornadoes** that speed up or slow down the player
- **No jumping inside current zones**, to make them harder
- More hazard content for levels 1 and 2

## Technical Backlog
- Typed Luau (`--!strict`) across all modules; currently part of the codebase is strict
- Automated tests for core systems
- Shared `Config` module for constants
- API docs for the main modules
- Evaluate ProfileStore for player save data
- Evaluate dependency management (Wally)

---
*This document reflects the current design direction; some systems are still in progress.*
