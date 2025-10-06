# Status Effects System Guide

## Overview
A comprehensive stacking status effect system for enemies with logarithmic scaling.

## Status Effects

### 1. **Burned** 🔥
- **Effect**: Continuous damage over time that decays as stacks decrease
- **Bonus**: Constant speed boost (+0.5 speed regardless of stacks)
- **Damage**: 4.0 damage per second per stack (applied continuously)
- **Duration**: 5 seconds per stack
- **Decay**: Accumulated stacks decay by 10% per second (stacks drop as accumulation falls below thresholds)
- **Scaling**: Logarithmic (accumulation), Linear (damage per stack), Constant (speed boost)

### 2. **Poisoned** ☠️
- **Effect**: Continuous constant damage over time
- **Damage**: 1.5 damage per second per stack (applied continuously)
- **Duration**: 8 seconds per stack
- **Scaling**: Logarithmic (accumulation), Linear (damage per stack)

### 3. **Frozen** ❄️
- **Effect**: Slows enemy movement
- **Slow**: 15% per stack
- **Minimum Speed**: 10% of base speed (max 90% slow)
- **Duration**: 3 seconds per stack
- **Decay**: Accumulated stacks decay by 15% per second
- **Scaling**: Logarithmic (accumulation), Linear (slow per stack)

### 4. **Weakened** 💔
- **Effect**: Increases damage taken from all sources
- **Multiplier**: +10% damage taken per stack
- **Duration**: 6 seconds per stack
- **Decay**: Accumulated stacks decay by 10% per second
- **Does NOT apply to**: DOT (Burn/Poison damage)
- **Scaling**: Logarithmic (accumulation), Linear (damage multiplier per stack)

## Logarithmic Stack Accumulation

Instead of linear stacking with logarithmic effects, stacks accumulate logarithmically:

**Formula:** `stacks = floor(log2(accumulated + 1))`

This means each additional stack requires exponentially more "application time":

**Accumulation Breakpoints:**
```
Accumulated → Stacks
0.0 → 0
1.0 → 1 (need 1.0 more)
3.0 → 2 (need 2.0 more) 
7.0 → 3 (need 4.0 more)
15.0 → 4 (need 8.0 more)
31.0 → 5 (need 16.0 more)
```

**Benefits:**
- Natural diminishing returns built into accumulation
- Stacks scale linearly with effects (simpler calculations)
- Beams apply at a constant rate (2.0/second)
- Early stacks are easy to get, later stacks require sustained exposure

## Usage

### Applying Status Effects

```gdscript
# In beam.gd - accumulate status effects over time:
if enemy.has_method("accumulate_status"):
    var application_rate = 2.0  # 2.0 points per second
    var amount = application_rate * delta
    enemy.accumulate_status(enemy.StatusEffect.BURNED, amount)
```

**How it works:**
1. Beam applies 2.0 "points" per second to the enemy
2. After 0.5s: accumulated = 1.0 → **1 stack**
3. After 1.5s: accumulated = 3.0 → **2 stacks**
4. After 3.5s: accumulated = 7.0 → **3 stacks**
5. After 7.5s: accumulated = 15.0 → **4 stacks**

### Checking Status

```gdscript
# Check if enemy has a status
if enemy.has_status(enemy.StatusEffect.WEAKENED):
    print("Enemy is weakened!")

# Get stack count
var poison_stacks = enemy.get_status_stacks(enemy.StatusEffect.POISONED)
print("Poison stacks: ", poison_stacks)
```

## Beam Color to Status Effect Mapping

The beams have different damage profiles and status effects:

| Beam | Direct Damage | Status Effect | Role |
|------|--------------|---------------|------|
| 🔴 **Red** | 100% | None | Pure DPS |
| 🟠 **Orange** | 30% | 🔥 Burned | DOT hybrid |
| 🟡 **Yellow** | 100% | None | Pure DPS |
| 🟢 **Green** | 0% | ☠️ Poisoned | Pure DOT |
| 🔵 **Cyan** | 0% | 💔 Weakened | Pure support |
| 🔷 **Blue** | 0% | ❄️ Frozen | Pure CC |
| 🟣 **Purple** | 100% | None | Pure DPS |

### Strategic Synergies

**Combo 1: Weakened + DPS**
- 🔵 Cyan beam applies Weakened stacks (0% direct damage)
- Switch to 🔴 Red/🟡 Yellow for 100% DPS × (1.0 + 0.1 per weaken stack)
- Result: 140% damage with 4 weaken stacks!

**Combo 2: Freeze + Poison**
- 🔷 Blue beam slows enemy (0% direct damage)
- 🟢 Green beam applies poison (0% direct damage)
- Enemy moves slowly while taking constant DOT

**Combo 3: Burn Hybrid**
- 🟠 Orange does modest direct damage (30%)
- Plus burn DOT that decays over time
- Good for spreading damage across multiple enemies

## Status Effect Math Examples

**Note:** Stacks now scale linearly with effects since the logarithmic scaling happens during accumulation!

### Frozen Enemy (3 stacks)
```
Base slow: 15% per stack
Total slow: 3 * 0.15 = 0.45 (45% slow)
Speed multiplier: 1.0 - 0.45 = 0.55 (55% speed)

Time to reach 3 stacks: ~3.5 seconds of continuous beam exposure
```

### Weakened Enemy (4 stacks)
```
Base multiplier: 10% per stack
Total multiplier: 4 * 0.10 = 0.40
Damage multiplier: 1.0 + 0.40 = 1.40 (140% damage taken)

Time to reach 4 stacks: ~7.5 seconds of continuous beam exposure
```

### Burned Enemy (2 stacks)
```
Base damage: 4.0 per second per stack
Total damage: 2 * 4.0 = 8.0 damage per second (continuous)
Decays as accumulated value drops below thresholds

Time to reach 2 stacks: ~1.5 seconds of continuous beam exposure
```

### Poisoned Enemy (2 stacks)
```
Base damage: 1.5 per second per stack
Total damage: 2 * 1.5 = 3.0 damage per second (continuous)
Does NOT decay - lasts full duration

Time to reach 2 stacks: ~1.5 seconds of continuous beam exposure
```

### Stack Accumulation Timeline
```
Time    | Accumulated | Stacks
--------|-------------|-------
0.5s    | 1.0         | 1
1.5s    | 3.0         | 2
3.5s    | 7.0         | 3
7.5s    | 15.0        | 4
15.5s   | 31.0        | 5
```

Each stack takes exponentially longer to reach!

### Burn Decay Example
```
Enemy is exposed to Orange beam for 7.5 seconds (15.0 accumulated, 4 stacks)
Then beam stops:

Time  | Accumulated | Stacks | DPS (continuous)
------|-------------|--------|------------------
0.0s  | 15.0        | 4      | 16.0/sec
1.0s  | 13.5        | 3      | 12.0/sec (dropped below 15.0 threshold)
2.3s  | 10.5        | 3      | 12.0/sec
3.1s  | 8.5         | 3      | 12.0/sec
4.5s  | 6.5         | 2      | 8.0/sec  (dropped below 7.0 threshold)
7.0s  | 4.0         | 2      | 8.0/sec
9.5s  | 2.5         | 1      | 4.0/sec  (dropped below 3.0 threshold)
15s   | 0.8         | 0      | 0.0/sec  (dropped below 1.0 threshold)
```

Burn naturally fades away as accumulated value decays! Damage is applied smoothly every frame.

### Status Effect Decay Summary

All status effects except **Poison** decay over time when not being actively applied:

| Effect | Decay Rate | Notes |
|--------|-----------|-------|
| 🔥 Burn | 10%/sec | Damage and speed boost decay together |
| ☠️ Poison | No decay | Constant until duration expires |
| ❄️ Frozen | 15%/sec | Faster decay - enemies thaw out quickly |
| 💔 Weakened | 10%/sec | Same decay rate as burn |

**Tactical Implications:**
- **Burn & Weaken**: Maintain pressure to keep stacks high
- **Freeze**: Requires constant exposure; stops quickly when beam moves away
- **Poison**: Fire and forget; full duration guaranteed

## Configuration Constants

Adjust in `basicEnemy.gd`:

```gdscript
# Burn
BURN_DAMAGE_PER_STACK: float = 4.0  # Damage per second per stack
BURN_DECAY_RATE: float = 0.9  # 10% decay per second
BURN_SPEED_BOOST: float = 0.5
BURN_DURATION: float = 5.0

# Poison
POISON_DAMAGE_PER_STACK: float = 1.5  # Damage per second per stack
POISON_DURATION: float = 8.0

# Freeze
FREEZE_SLOW_PER_STACK: float = 0.15
FREEZE_DURATION: float = 3.0
FREEZE_DECAY_RATE: float = 0.85  # 15% decay per second

# Weaken
WEAKEN_MULTIPLIER_PER_STACK: float = 0.1
WEAKEN_DURATION: float = 6.0
WEAKEN_DECAY_RATE: float = 0.9  # 10% decay per second
```
