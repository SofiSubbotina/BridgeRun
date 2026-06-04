# 🌉 Bridge Run
<img width="1351" height="646" alt="image" src="https://github.com/user-attachments/assets/eb21cfe6-90b5-490c-ba7b-3e42cc4f9c71" />

A Roblox game where players collect planks and build a bridge across water in real time — racing against others to reach the finish line.

## Gameplay

- Collect planks scattered across the map
- Walk over water to automatically place planks and build your bridge
- Fall in if you run out — try again with a countdown
- Hit bonus zones to multiply your planks, or penalty zones to lose some
- Use trampolines to launch across gaps
- Finish the run and compete for the best time on the leaderboard

## Technical Highlights

**Server architecture**
- Modular service layer: `BridgeService`, `PlankService`, `BonusService`, `LeaderboardService`
- Object pool for bridge planks (100 parts pre-allocated in batches to avoid frame spikes)
- Raycast-based water detection with per-player frame cache
- DataStore with async save queue, exponential backoff retry, and `BindToClose` safety save
- OrderedDataStore for persistent top-10 leaderboard

**Client**
- Auto-run with mobile/desktop input handling
- Animated plank stack that updates in real time for all players
- Trampoline flip animation synced across clients
- Drown effect with particles, screen overlay, and sinking tween
- Bonus/penalty floating text with particle burst
- Live leaderboard with client-side timer interpolation
- Countdown system with shared state module

**Tools & workflow**
- [Rojo](https://rojo.space/) for VS Code ↔ Roblox Studio sync
- Git + GitHub for version control

## Project Structure

```
src/
├── ReplicatedStorage/
│   └── CountdownState.luau
├── ServerScriptService/
│   ├── FinishTrigger.server.luau
│   ├── Trampoline.server.luau
│   └── MainGame/
│       ├── init.server.luau
│       └── Services/
│           ├── BonusService.luau
│           ├── BridgeService.luau
│           ├── LeaderboardService.luau
│           └── PlankService.luau
├── StarterCharacterScripts/
│   ├── AutoRun.client.luau
│   ├── PersonalPlanks.client.luau
│   └── PlankStack.client.luau
├── StarterPlayerScripts/
│   ├── BonusEffectClient.client.luau
│   ├── CameraLocal.client.luau
│   ├── DrownEffect.client.luau
│   ├── MapEffects.client.luau
│   └── SoundClient.client.luau
└── StarterGui/
    ├── CountdownGui/
    ├── FinishScreen/
    ├── HudGui/
    └── LeaderboardGui/
```
## Play
[Play on Roblox]([https://www.roblox.com/games/10159407224](https://www.roblox.com/games/97476080303924/Plank-Rush))

## Built With

- Luau
- Roblox Studio
- Rojo
- Git
