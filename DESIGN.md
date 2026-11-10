# Plank Rush: Game Design Document

**Platform:** Roblox (PC and mobile)
**Genre:** Auto-run obstacle course / speedrun
**Status:** In development.
---

## 1. Overview

### 1.1 High Concept
You sprint across a lake with an armful of planks. Every step over water spends one. Collect more than you need, avoid what takes them away, and reach the end before the water takes you.

### 1.2 Design Pillars
1. **Planks are life.** The plank count is both the player's health and their currency. Every hazard, bonus and route choice is a decision about planks.
2. **Simple input, sharp decisions.** The character runs on its own. The player only steers, so difficulty comes from routing and risk, not from execution complexity.
3. **Short runs, instant retry.** Dying costs seconds, not minutes. The timer pauses on death and loading time is never counted.

### 1.3 Target Audience
Players who enjoy short, repeatable runs and beating their own or others' times. Must work well on mobile.

---

## 2. Core Gameplay

### 2.1 Controls
The character runs forward automatically. The player steers left and right only.

| Platform | Input |
|---|---|
| Desktop | A / D or arrow keys |
| Mobile | Thumbstick (horizontal component only) |

### 2.2 Core Loop
1. Collect planks scattered across the level.
2. Run out over the water. A plank is placed automatically under each step.
3. Run out of planks over water and you fall in.
4. Hazards and walls change how many planks you carry, so the route and the risks you take decide the outcome.
5. Reach the end of a level to unlock the next one. Reach the final finish to set a time.

### 2.3 Death and Respawn
- Falling in water, lethal hazards and HP loss all end the attempt.
- The player respawns at the checkpoint of the last unlocked level, not at the start of the game.
- Carried planks are lost on death and scatter visually.
- The run timer pauses on death and resumes only when the client confirms control.

---

## 3. Level Structure and Progression

- The game is a sequence of levels. Each level ends with an invisible trigger that unlocks the next.
- Locked levels are hidden on the client and physically blocked by collision groups. Hazard triggers also verify the player's unlocked level on the server.
- Each level has its own plank pickups, bonus walls and hazards.
- Each level has one respawn checkpoint, activated when the previous level is completed.
- Planks collected on a level respawn on death.

---

## 4. Resources and Modifiers

| Element | Behavior |
|---|---|
| Plank pickup | Adds planks to the stack. Amount is set per pickup. |
| Bonus wall | Multiplies the carried planks. |
| Penalty wall | Removes a share of the carried planks. |
| Automatic bridge | One plank is spent per step over water. Placed planks fade and are recycled. |

---

## 5. Hazards

| Hazard | Behavior | Lethal | Effect on the player |
|---|---|---|---|
| Spike trap | Rises, stays up, retracts on a timer. Each spike starts at a random offset. | Yes, while up | Death |
| Whirlpool | Pulls the player to its center. | Yes | Death |
| Falling platform | Bobs up and down. Drops after a short warning if someone is standing on it. | Indirect | Death if dropped into water |
| Predator fish | Patrols its zone, chases anyone who enters, attacks on a cooldown. Tuned per zone. | If HP reaches 0 | HP damage and plank theft |
| Swinging log | Knocks the player away along its swing direction. | No | Drops all carried planks |
| Geyser | Launches the player up and in a random direction. | No | Can help or hurt; the risk is the point |
| Trampoline | Launches the player across gaps. | No | Displacement |
| Current zone | Pushes the player and any planks placed inside it downstream. | No | Displacement |

---

## 6. Planned Hazards (ideas, not designed yet)

Grouped by what they attack. Details will change as the ideas are developed.

**Control**
- Mirror zone: left and right steering are swapped inside the zone.
- Wind zone / tornado: constant sideways push, or a speed-up / slow-down effect.
- Speed and slow pads: temporary speed change on touch.

**Resource**
- Rotten plank: looks like a normal pickup, takes planks instead of giving them.
- Toll gate: opens for a number of planks. A risky free route runs beside it.

**Rhythm and reaction**
- Floating mines: drift on the water and are carried by current zones. Knock the player back on contact.
- Electric pulse: water in a zone shocks on a timer with a visible warning. Safe only on solid ground.
- Seagull bomber: flies over its zone and marks a target with a red spot on the map before dropping a bomb on it. A hit knocks the player back.

**Priority:** rotten plank, floating mines, mirror zone. The rest is planned for level 3 and beyond.
