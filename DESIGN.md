# Plank Rush — Design Document

## Current Status
Two levels in development. Implemented: plank counter, global top-10 leaderboard, live run timer, finish screen with personal best and attempt count, level progression system, whirlpool hazards, level visibility tied to progress.

## Game Modes

**Full Run** — player completes all levels back-to-back without stopping. Global time is measured from the start of level 1 to the finish of the last level. Only players who complete every level qualify for the global leaderboard.

**Single Level** — player selects and practices one level independently. Results go to that level's leaderboard but don't affect global time.

## Screens

**Main Menu (Lobby)**
- Global leaderboard — top 10 best full runs
- Player's personal best across the whole game
- "Level Select" button — opens the level journal
- No save yet: single "Play" button
- Save exists: "Continue" and "Start Over" buttons

**Level Journal** — scrollable screen, per level:
- That level's leaderboard
- Player's personal best on that level
- "Play" button
- Arrows to switch between levels

**In-Game HUD**

Left side (kept minimal, especially for mobile):
- Plank counter
- Personal best (whole game)

Right panel — content depends on mode:
- Full Run: global leaderboard + "currently racing" with a live global timer
- Single Level: that level's leaderboard + a live timer for that level

It's the same UI component in both cases — the server sends the client a mode flag along with the data, and the client simply renders whatever it receives.

## Leaderboards
- **Global** — ranked by total time for a fully completed run. Only players who finished the last level qualify.
- **Per-level** — ranked by time on a specific level. Shown in the level journal and in the right panel during single-level play.
- **Personal** — best time per level and for the full run. Shown in the HUD and the level journal.

## Server-Side Mode Tracking
The server stores a per-player mode flag:
```lua
playerMode[userId] = "full"
-- or
playerMode[userId] = { mode = "level", levelId = 2 }
```
`LeaderboardService` broadcasts data based on the player's current mode. The client doesn't know where the data comes from — it just renders what it's given.

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

## Development Priorities
1. New levels — content first
2. Per-level leaderboards
3. Save system and global leaderboard
4. Main lobby and level journal
5. Mobile UI adaptation
6. Stickers

---
*This document reflects the current design direction; some systems are still in progress.*
