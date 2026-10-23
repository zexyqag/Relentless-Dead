# Relentless Dead

**The dead don't stay down.**

A Project Zomboid Build 42 mod: killed zombies can get back up where they fell, hours later. Choose how many rise, when and how often, and keep a corpse down for good by burning it, finishing it off or, if you like, killing it with a blow to the head.

- **Steam Workshop:** [Relentless Dead](https://steamcommunity.com/sharedfiles/filedetails/?id=3824839394)
- **Issues:** [the issue tracker](../../issues)
- **Workshop ID:** `3824839394`
- **Mod ID:** `RelentlessDead`
- **Game:** Build 42.20.2 or later, single player and multiplayer

## Contents

- [What it does](#what-it-does)
- [Marking](#marking)
- [Getting up](#getting-up)
- [Keeping a corpse down](#keeping-a-corpse-down)
- [Head kills](#head-kills)
- [Kill counts and Rises per body](#kill-counts-and-rises-per-body)
- [Options](#options)
- [Status](#status)
- [Multiplayer and performance](#multiplayer-and-performance)
- [Compatibility](#compatibility)
- [Known limitations](#known-limitations)
- [Not yet verified in game](#not-yet-verified-in-game)
- [Reporting problems](#reporting-problems)
- [For mod authors](#for-mod-authors)

## What it does

When a zombie dies, a roll decides whether its corpse gets back up. A corpse marked to rise comes due a few hours later and gets up where it lies, in the outfit it died in, as a corpse playing dead does: it stays one of the game's zombies, not a new kind of creature.

**It works as soon as it is enabled, with no setup.** By default half of the zombies killed are marked, at any hour, and get up 1 to 2 in-game hours after their death, with a groan a few seconds before. A zombie that rose can rise again each time it is killed.

Another mod can take over the share and decide when corpses get up, through the [API](#for-mod-authors): a day and night mod can make only the night's kills rise, and only in the dark. While it does, the **Rise chance** option rests.

## Marking

When a zombie dies, the share in effect decides: **Rise chance** (`RiseChance`, 50 by default), or the share of a mod that drives rising. It is rolled for each zombie. It stays down instead when any of these hold:

| It stays down when | Set by |
|---|---|
| It is a bandit of [Bandits NPC](https://steamcommunity.com/sharedfiles/filedetails/?id=3268487204) | Always |
| It is an NPC of [Project A-Life](https://steamcommunity.com/sharedfiles/filedetails/?id=3803984183) | Always: A-Life turns infected NPCs itself |
| Its head is off ([Zombie Dismemberment](https://steamcommunity.com/sharedfiles/filedetails/?id=3811483602)) | Always |
| Both its arms are off and a leg is lost ([Zombie Dismemberment](#compatibility)) | Always: it could only lie there |
| Another mod keeps it down | That mod, through `addVeto` |
| It was a player | `RisePlayers` (off by default) |
| It died of fire: burning, on a square with a fire, or by a hit from a weapon that starts fires | `FireStaysDown` (on by default) |
| A blow to its head killed it: a shot or a melee hit the game puts in the head, the knife stab through the jaw, or a hit to its head on the floor | `HeadKillsStayDown` (off by default), see [Head kills](#head-kills) |
| It has already risen as often as allowed | `MaxRises` (no limit by default) |
| The share is 0, or its roll misses | `RiseChance`, or the driving mod |

## Getting up

- A marked corpse comes due at a random time between `RiseDelayMin` and `RiseDelayMax` in-game hours after its death (1 to 2 by default).
- Corpses are checked every 10 in-game minutes. With the mod's own options a due corpse gets up at the next check; a mod that drives rising can keep due corpses waiting, for example until night, and they get up at the first check after it lets them.
- **The groan:** with `RiseWarning` on (the default), a corpse a check lets get up groans first: every player near it hears a zombie's voice from the corpse. It gets up `RiseWarningMinutes` in-game minutes later (2 by default, which is 5 seconds at the default day length of one hour), wherever it lies then. Nothing tells which corpses will rise before their groan, and every groan is followed by its rise: once a corpse has groaned, it gets up even if the mod that drives rising says to wait meanwhile. A corpse kept down in the meantime (finished off or burned) stays down. One that isn't there when its time comes, being dragged or in an area no longer loaded, waits for a check and groans again before it gets up. With `RiseWarning` off, for hardcore games, corpses get up at the check without a sound.
- It rises where it lies, in the outfit it died in, and stands up within seconds. A corpse that has turned into a skeleton rises as one.
- A corpse in an area no player has loaded waits until one does.
- At most `RisesPerScan` corpses rise, or groan, in one check on the whole server. A check searches around for at most five times that many corpses that aren't where they died, and the rest wait for the next check.
- A dragged corpse is followed to where it is put down. A corpse that isn't found three checks in a row (burned, buried, removed or carried off) is dropped.

## Keeping a corpse down

| Way | Detail |
|---|---|
| **Burn it** | Burning a corpse with petrol and a lighter keeps it down as soon as the burn is done, even where the server lets no fire start (no fire allowed, water, a safehouse without fire) and in the seconds before the fire takes it. With `FireStaysDown` on, a zombie that dies of fire stays down too: one that dies burning, on a square with a fire, or by a hit from a weapon that starts fires (an incendiary bomb's blast, which can kill before the fire takes, or the burn damage some mods deal as hits with a molotov). |
| **Finish off** | Right-click zombie corpses: **Finish off** for the nearest one not yet finished off, as the game's own corpse options pick one, or **Finish off N corpses** when several lie on its tile. You walk up to it and work for `FinishOffSeconds` (3 by default), and it never rises again. Each corpse can be finished off once, by anyone: every player's game then leaves it out of the menu. It is offered on every corpse not yet finished off, so the menu doesn't show which ones would rise; only Project A-Life's NPC corpses, which never rise here, are left out. The server takes it only from a player within 3 tiles. With [Zombie Dismemberment](#compatibility) and its decapitation on, Finish off takes the head off. |
| **Head kills** | With `HeadKillsStayDown` on, a zombie killed by a blow to its head stays down: see [Head kills](#head-kills). It is a separate switch from Finish off. |
| Bury it, or carry it away | A buried corpse is gone. One carried off as an item is no longer found, and is dropped after three checks. |
| Safehouses | With `RiseInSafehouses` off (the default), a corpse inside a claimed safehouse stays down. |
| Age | A corpse whose zombie died more than `RiseMaxAgeHours` ago (168 by default) stays down. A check drops it, and dragging it later doesn't bring it back unless the option has been raised or set to 0 since. |
| The waiting limit | Above `RiserLimit` marked corpses (5000 by default), the oldest stays down, even if it is dragged later. |
| Stairs | A corpse on stairs can't play dead, so it stays down. So does every corpse while `ZombieLore.DisableFakeDead` is 3 (never); the log warns once. |

With `FinishOff` off and `HeadKillsStayDown` off (its default), only burning, burying or carrying a corpse away keeps it down.

## Head kills

With `HeadKillsStayDown` on (off by default), a zombie stays down when the blow that killed it struck its head, as far as the game tells:

| Blow | Counts when | Who decides |
|---|---|---|
| A firearm shot | The game puts it in the head: a shot to the head is the hit reaction it gives the zombie. With the aiming reticle on the zombie, that is the body part under it; otherwise a critical shot from in front or behind goes to the head. | The server, from the hit the shooter's game sends it or from that game's report of the kill; in single player, the game |
| A melee hit | The game lands it on the head. It picks the spot of each melee hit itself, the same pick that draws the wound: the head one hit in 7, and a third of critical hits besides. | The server's own pick; in single player, the game's |
| The knife stab through the jaw | Always: the close-range knife kill. | The server, from the attack the attacker's game sends it or from that game's report of the kill |
| A melee hit to the head of a zombie on the floor | The zombie dies within 5 seconds of the hit. | The attacker's game, the only one that knows where such a hit lands: it reports the hit, and the server takes the report only from a player within 3 tiles |

- Only the blow that kills counts: a zombie shot in the head that dies of a later hit elsewhere, or of fire, can rise.
- In multiplayer the attacker's game also reports a shot in the head or the knife stab through the jaw that killed its copy of the zombie, for mods that settle where a bullet lands on the shooter's game alone, such as [Viewpoint True Ballistics](https://steamcommunity.com/sharedfiles/filedetails/?id=3812864848). The server takes the report only from the player who killed that zombie there, within 5 seconds of its death. Without such a mod, the server already knows these blows from the hit itself.
- Bombs and fire never count, whatever part of the body the game gave their hits, also when a mod deals burn damage as hits with a molotov.
- A shot at a zombie eating a body gives it the eating reaction, not a shot in the head: a head shot that kills it there doesn't count.
- In multiplayer each game picks the spot of a melee hit for itself, for the wound it draws, and the server's pick decides: the wound a player sees may not match it.
- A head kill's corpse lies as any other: it is still offered Finish off, so the menu tells nothing.
- A head that another mod only shows flying off, keeping nothing of it on the zombie, doesn't count by itself; the blow can still be a head kill.

## Kill counts and Rises per body

- Every rise means one more kill for every kill counter: the game's, and other mods' that count kills or give XP or traits for them. The rise share, `MaxRises` and Finish off limit how often one body can be killed.
- `MaxRises` (no limit by default) counts the rises of one body. Its corpse carries the count, and so does the zombie that rises from it.
- The game keeps nothing of a zombie it unloads: when it walks out of the loaded area, at every restart and at every load of a single player game. So the mod keeps the count of each risen zombie in the save meanwhile, with its outfit and where a check last saw it, and a zombie the game loads in that outfit within 20 tiles of there takes the count up again. The checks run every 10 in-game minutes, and a single player game also notes where its risen zombies stand when it saves.
- Only zombies marked when they die get up. No corpse climbs out of the ground.

## Options

Each option is `RelentlessDead.<Option>` in the sandbox settings, on the **Relentless Dead** page. Every one is read while the game runs, so a change applies at once.

| Option | In game | Default | Range | What it does |
|---|---|---|---|---|
| `RiseChance` | Rise chance | `50` | 0 to 100 | Percent of the zombies killed that are marked to rise, while no other mod drives rising. |
| `RiseDelayMin` | Rise after at least | `1.0` | 0.0 to 48.0 | In-game hours from death until a marked corpse may get up, at least. |
| `RiseDelayMax` | Rise after at most | `2.0` | 0.0 to 48.0 | The same, at most. Each corpse gets a random time in between. Below `RiseDelayMin`, the two are swapped and the log warns once. |
| `MaxRises` | Rises per body | `0` | 0 to 20 | Times one body can rise; 0 for no limit. The count lasts while the game has the risen zombie unloaded: see [Kill counts and Rises per body](#kill-counts-and-rises-per-body). |
| `RiseMaxAgeHours` | Oldest corpse that rises | `168` | 0 to 8760 | A marked corpse older than this many in-game hours stays down; 0 for no limit. |
| `RiseWarning` | Warning before rising | `true` | true or false | A corpse groans before it gets up, for every player near it. Off for hardcore games: corpses get up without a sound. |
| `RiseWarningMinutes` | Warning time | `2` | 1 to 10 | In-game minutes from the groan until the corpse gets up; 2 is 5 seconds at the default day length of one hour. |
| `FireStaysDown` | Burned zombies stay down | `true` | true or false | A zombie that dies of fire (burning, on a square with a fire, or by a hit from a weapon that starts fires) is never marked to rise. A burned corpse stays down either way. |
| `FinishOff` | Finish off | `true` | true or false | Offer Finish off on zombie corpses, once per corpse, which keeps them down. |
| `FinishOffSeconds` | Finish off time | `3` | 1 to 30 | How long Finish off takes, in seconds at normal game speed. |
| `HeadKillsStayDown` | Head kills keep zombies down | `false` | true or false | A zombie killed by a blow to its head stays down: see [Head kills](#head-kills). |
| `RiseInSafehouses` | Corpses rise in safehouses | `false` | true or false | Off: a corpse inside a claimed safehouse stays down. |
| `RisePlayers` | Players' zombies rise | `false` | true or false | A zombie that was a player can be marked to rise. |
| `RisesPerScan` | Rises per check | `10` | 1 to 100 | Most corpses that rise, or groan, per check (every 10 in-game minutes) on the whole server. |
| `RiserLimit` | Most corpses waiting | `5000` | 100 to 50000 | Most marked corpses kept waiting; above it the oldest stays down. Also the most risen zombies whose count is kept; above it, the one not seen the longest starts over. |
| `Verbose` | Verbose log | `false` | true or false | Write each death with its roll, each rise, every corpse kept down and every Finish off to the log. |

An option with a value the game shouldn't hold is replaced by its default, and the log warns. Warnings and errors are always logged, prefixed `[RelentlessDead]`.

## Status

Right-click the world: **Relentless Dead status** is there in single player, and in multiplayer for players whose role has the sandbox options permission (admins). The server refuses anyone else. It shows how many corpses wait to rise and the rise and wake in effect, and writes the full report to the log of the admin's game (`Zomboid/console.txt`), and on a server to the server's log too:

- the mod version;
- the rise and wake in effect and who sets them (the mod's own options, or the driving mod and its label), the corpses registered and due, the risen zombies whose count it keeps, and the last check;
- this session's counts: marked, kept down, risen, finished off, gone, too old, over the limit;
- the drivers, vetoes and before-rise functions other mods gave;
- whether Zombie Dismemberment is loaded and whether Finish off takes heads off.

## Multiplayer and performance

| Where | What runs |
|---|---|
| The server (or the single player game) | Marking at each death, and whether a blow to the head killed it. The checks every 10 in-game minutes, the groans and the corpses getting up, the corpses waiting and the risen zombies' counts, kept in the save. Finish off, floor head-hit reports and burns, which it checks and keeps down. |
| Every player's game | The groans of the corpses near its player, which the server sends it. The Finish off menu and action, its own player's floor head-hit reports, and the corpses other players finished off, which it leaves out of the menu (and takes the heads off with Zombie Dismemberment). |

| Option | Cost |
|---|---|
| `RisesPerScan` (10) | Corpses that rise per check, every 10 in-game minutes; each check searches for at most five times this many moved corpses. |
| `RiserLimit` (5000) | Marked corpses kept waiting, and risen zombies counted, in the save. While any risen zombie is counted, each check looks over the loaded zombies once to follow them. |
| `Verbose` (off) | Every death, rise and keep-down written to the log. |

## Compatibility

From the mods' code where it is public. None of these was tested together with Relentless Dead in game yet.

- **Zombie Dismemberment:** a zombie whose head it took off never rises, nor does one with both arms off and a leg lost, which it keeps on the floor. With its decapitation on (its own `Enabled` and `EnableDecapitation` options), Finish off takes the head off as it does, which removes hats, glasses and masks from the corpse, on the server and on every player's game that has the corpse loaded. Its author has not yet tested its multiplayer in a live session.
- **Mods that raise corpses through the game's own revival timer:** every way this mod keeps a corpse down (Finish off, burning, head kills, the safehouse and other checks, `keepDown`) also cancels a revival timer the game holds for a zombie's corpse, whoever set it. A corpse this mod never marked can still rise through such a mod, by its rules.
- **Viewpoint True Ballistics:** from its docs, its rounds hit through the game's own hit on the shooter's game, with the body part they struck, so a shot in the head that kills is a head kill. In multiplayer the shooter's game reports it (see [Head kills](#head-kills)). With its Hit locations option off, the game picks the part, as for any shot.
- **[Viewpoint Advanced Throwables](https://steamcommunity.com/sharedfiles/filedetails/?id=3813194971):** its molotov and incendiary fires burn zombies on the server with hits from the molotov: a zombie they kill died of fire, never of a blow to the head.
- **Bandits:** they never rise.
- **Project A-Life:** its NPCs never rise here, whichever mod's death handler runs first, and Finish off leaves their corpses alone. A-Life turns infected NPCs itself, with its own Put down.
- **Day and night mods:** a mod can drive rising through the API. [Crepuscular](https://steamcommunity.com/sharedfiles/filedetails/?id=3820511464) does: its `rise=` and `wake=` set the share and when corpses get up, by day, night and event.
- **Special-zombie mods:** their monsters rise as any corpse does, in the same outfit, unless a veto keeps them down; what they can do after that is up to their own mod.
- **The game's corpse removal** (`HoursForCorpseRemoval`) removes corpses whatever their mark. Players' corpses and the game's turning of infected players are left alone.
- **Kill counters and XP mods:** each rise is another kill.

## Known limitations

- **Rise counts while unloaded** follow a risen zombie's outfit and where a check last saw it: one that the game moves more than 20 tiles from there while it is unloaded comes back with its count started over, and another zombie in the very same outfit and look that the game loads there first takes the count.
- **The groan** is a zombie's voice played at the corpse; the corpse itself doesn't move. The game draws a lying corpse in the pose it died in and has no way to animate it.
- **Corpses on stairs**, and every corpse while `ZombieLore.DisableFakeDead` is 3, can't rise.
- **Corpses carried as an item** count as gone after three checks: put down again later, they stay down.
- **A corpse finished off** on a server only shows as finished off on a player's game that has its area loaded then, or loads it later.

## Not yet verified in game

- That risers stand up at once, their animation, corpses loaded from saved areas, and the order of floor head-hit reports.
- Head kills: that a shot aimed at the head, a melee hit the game lands on the head and the knife stab through the jaw keep a zombie down, in single player and on a server.
- The groan: that the zombie voice played at a corpse sounds as a groan, and that on a server the players near the corpse hear it and those far off don't.
- Rise counts: that a risen zombie that walked out of the loaded area, and one after a restart, comes back with its count.
- Fire: that a zombie killed on a burning square, or by Viewpoint Advanced Throwables' molotov fire, stays down.
- Viewpoint True Ballistics: that a kill by a shot in the head stays down, in single player and on a server.
- Project A-Life: that its NPCs stay down with A-Life before and after Relentless Dead in the mod list.
- Finish off on a server: that a player who loads the area later sees the corpse as finished off.
- Burning: that a burn the server refuses keeps the corpse down, and that a due corpse doesn't stand up in the fire.
- Zombie Dismemberment: Finish off's decapitation on a server and on each player's game, and looting such a corpse in multiplayer.

## Reporting problems

Open an issue in the [issue tracker](../../issues) with:

1. single player or server, and the game version;
2. your Relentless Dead options (the `RelentlessDead` table of `SandboxVars.lua`);
3. the Status report and the `[RelentlessDead]` lines from the log (`Zomboid/console.txt`, or the server's log), with **Verbose log** on if you can;
4. your other mods, especially those that drive rising, raise or dismember zombies;
5. what you expected and what happened.

## For mod authors

`RelentlessDead.API` is a global on every game; `require "RelentlessDead/API"` loads it whichever mod loads first, and creates `Events.OnRisingRose`. Its `VERSION` is 1. Rising runs on the server and in single player, so what you give it there takes effect; `keepDown` and `status` refuse elsewhere.

| Function | Returns |
|---|---|
| `drive(name, phase)` | `true`, or `false` and why. Takes over the share and when corpses get up. |
| `addVeto(name, fn)` | `true`, or `false` and why. Keeps zombies down at their death. |
| `addBeforeRise(name, fn)` | `true`, or `false` and why. Runs on a corpse just before it rises. |
| `keepDown(body, why)` | Whether the corpse was due to rise, or `false` and why. Keeps a corpse down for good. |
| `status()` | The Status lines, or `false` and why. |

**drive(name, phase):**

- `phase` is `{ rise = 0 to 100, wake = true or false, label = text or nil }`: `rise` is the percent of the zombies killed that are marked, and while `wake` is false due corpses wait. `label` shows in the Status, for example the phase's name.
- `phase` can also be a function that returns such a table, or `nil` to drive nothing just then. It is called at each death and each check, so the phase is never late.
- `nil` instead of a phase stops driving. While a driver gives a phase, `RiseChance` rests. With several drivers, the first one given that gives a phase decides, and the log warns once.
- The delays, `MaxRises` and every other option still apply.

**addVeto(name, fn):** `fn(zombie)` runs at each death, before the roll, and returns why the zombie stays down (a text, or `true`), or `nil`. It runs after the built-in rules (Bandits, A-Life NPCs, heads off, no arms and a leg off). One that throws keeps nothing down, with a warning. `nil` instead of `fn` removes it; the same name again replaces it.

**addBeforeRise(name, fn):** `fn(body)` runs on the corpse just before it rises, playing dead and with its rise counted; what it changes in the corpse's modData rises with the zombie. It can't stop the rise. One that throws doesn't stop it either, with a warning.

**keepDown(body, why):** keeps the zombie corpse `body` down for good: it is never marked to rise again, and a revival timer the game holds for it, whoever set it, is cancelled. A player's corpse keeps the game's timer, with which the game turns infected players. `why` goes to the log.

**OnRisingRose(zombie, rises):** an event that fires on the server and in single player after each rise: `zombie` is the zombie that just got up, already in the world, and `rises` how often this body has risen, counted across the times the game unloaded it (see [Kill counts and Rises per body](#kill-counts-and-rises-per-body)).

```lua
-- media/lua/server/MyMod/RisingSupport.lua
if isClient() or not getActivatedMods():contains("\\RelentlessDead") then return end
local Rising = require "RelentlessDead/API"

-- Only the night's kills rise, and only at night.
Rising.drive("mymod", function()
    if MyMod.isNight() then
        return { rise = 50, wake = true, label = "night" }
    end
    return { rise = 0, wake = false, label = "day" }
end)

-- My monsters stay down.
Rising.addVeto("mymod", function(zombie)
    if MyMod.isMonster(zombie) then
        return "a monster"
    end
end)

Events.OnRisingRose.Add(function(zombie, rises)
    MyMod.makeTougher(zombie, rises)
end)
```

Build 42 lists mod ids with a leading backslash, hence `"\\RelentlessDead"`. The marks the mod keeps in a corpse's modData are its own and may change; use the API.

To contribute to Relentless Dead, see [CONTRIBUTING.md](CONTRIBUTING.md).
