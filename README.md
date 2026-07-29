# 🌉 Plank Rush
<img width="1351" height="646" alt="image" src="https://github.com/user-attachments/assets/eb21cfe6-90b5-490c-ba7b-3e42cc4f9c71" />

A Roblox game where players collect planks and build a bridge across water in real time — racing against others to reach the finish line.

## Gameplay

- Collect planks scattered across the map
- Walk over water to automatically place planks and build your bridge
- Fall in if you run out — try again with a countdown
- Hit bonus zones to multiply your planks, or penalty zones to lose some
- Use trampolines to launch across gaps
- Navigate whirlpools, geysers, and spike traps along the way
- Finish the run and compete for the best time on the leaderboard

## Technical Highlights

**Server architecture**
- Modular service layer under `MainGame/Services`: `BridgeService`, `PlankService`, `BonusService`, `LeaderboardService`, `LevelProgress`, `CharacterLock`, `CollisionGroups`, `AnalyticsService`
- Trap/interactable system (`InteractablesManager` + `Interactables/`) with per-trap modules: `Trampoline`, `SpikeTrap`, `Geyser`
- Object pool for bridge planks (100 parts pre-allocated in batches to avoid frame spikes)
- Raycast-based water detection with per-player frame cache
- DataStore with async save queue, exponential backoff retry, and `BindToClose` safety save
- OrderedDataStore for persistent top-10 leaderboard
- Player session analytics (join time, attempts, finish status, region) written to a separate DataStore, exposed through a `RemoteFunction` gated server-side to a developer-only allowlist — no client-side trust involved

**Client**
- Auto-run with mobile/desktop input handling
- Animated plank stack that updates in real time for all players
- Trampoline flip animation synced across clients
- Drown effect with particles, screen overlay, and sinking tween
- Bonus/penalty floating text with particle burst
- Live leaderboard with client-side timer interpolation
- Countdown system with shared state module
- Developer-only analytics panel (in-game, hotkey-toggled), destroyed client-side for anyone outside the allowlist


## Technical Decisions

**Object pooling for performance**
Cloning parts every time a plank is placed caused visible frame spikes.
I switched to pre-allocating a pool of 100 parts in batches (20 per frame)
so the server never stalls mid-run.

**Reliable DataStore saves**
A simple SetAsync call loses data under Roblox throttling.
I built an async save queue with exponential backoff retry and a BindToClose
safety flush — so records survive both normal play and server shutdowns.

**Client-server sync without spam**
The leaderboard timer updates every frame on the client via local interpolation,
while the server only broadcasts on actual state changes.
This keeps the UI smooth without flooding the network.

**Separating concerns in a game server**
Splitting logic into BridgeService / PlankService / BonusService / LeaderboardService
made it easy to reason about each system independently and avoid spaghetti
between unrelated features.

**Admin tooling that never trusts the client**
The analytics panel looks like a normal in-game GUI, but every piece of data
it displays is fetched through a RemoteFunction whose server-side handler checks
the caller's UserId against an allowlist before returning anything. A non-admin
client gets an empty response and the GUI destroys itself — access control lives
entirely on the server, not hidden behind a client-side check.

## Design Document

The full game design — modes, leaderboard structure, save system, and UI flow — is documented in [DESIGN.md](./DESIGN.md).

## Tools & Workflow
- [Rojo](https://rojo.space/) for VS Code ↔ Roblox Studio sync
- Git + GitHub for version control

## Project Structure

```
src/
├── ReplicatedStorage/
│ ├── CountdownState.luau
│ └── DevConfig.example.luau (copy to DevConfig.luau and fill in your own UserId — gitignored)
├── ServerScriptService/
│ ├── FinishTrigger.server.luau
│ ├── LevelEnds.server.luau
│ ├── AnalyticsAdmin.server.luau
│ └── MainGame/
│ ├── init.server.luau
│ └── Services/
│ ├── AnalyticsService.luau
│ ├── BonusService.luau
│ ├── BridgeService.luau
│ ├── CharacterLock.luau
│ ├── CollisionGroups.luau
│ ├── LeaderboardService.luau
│ ├── LevelProgress.luau
│ ├── PlankService.luau
│ └── InteractablesManager.server.luau
│ └── Interactables/
│ ├── Geyser.luau
│ ├── SpikeTrap.luau
│ └── Trampoline.luau
├── StarterCharacterScripts/
│ ├── AutoRun.client.luau
│ ├── PersonalPlanks.client.luau
│ └── PlankStack.client.luau
├── StarterPlayerScripts/
│ ├── BonusEffectClient.client.luau
│ ├── CameraLocal.client.luau
│ ├── DrownEffect.client.luau
│ ├── LevelTransitionEffect.client.luau
│ ├── LevelVisibility.client.luau
│ ├── MapEffects.client.luau
│ ├── PlankScatterEffect.client.luau
│ └── SoundClient.client.luau
└── StarterGui/
├── AdminAnalyticsGui/
├── CountdownGui/
├── FinishScreen/
├── HudGui/
└── LeaderboardGui/
```
## Play
[Play on Roblox](https://www.roblox.com/games/97476080303924/Plank-Rush)


