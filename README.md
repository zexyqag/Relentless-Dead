# Relentless Dead

**The dead don't stay down.**

A Project Zomboid Build 42 mod: killed zombies can get back up where they fell, hours later. Choose how many rise, when and how often, and keep a corpse down for good by burning it or finishing it off.

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
- [Kill counts and Rises per body](#kill-counts-and-rises-per-body)
- [Options](#options)
- [Status](#status)
- [Multiplayer and performance](#multiplayer-and-performance)
- [For modders](#for-modders)
- [Compatibility](#compatibility)
- [Known limitations](#known-limitations)
- [Not yet verified in game](#not-yet-verified-in-game)
- [Reporting problems](#reporting-problems)
- [Publishing](#publishing)

## What it does

When a zombie dies, a roll decides whether its corpse gets back up. A corpse marked to rise comes due a few hours later and gets up where it lies, in the outfit it died in, as a corpse playing dead does: it stays one of the game's zombies, not a new kind of creature.

**It works as soon as it is enabled, with no setup.** By default half of the zombies killed are marked, at any hour, and get up 1 to 2 in-game hours after their death. Each body rises once.

Another mod can take over the share and decide when corpses get up, through the [API](#for-modders): a day and night mod can make only the night's kills rise, and only in the dark. While it does, the **Rise chance** option rests.

## Marking

When a zombie dies, the share in effect decides: **Rise chance** (`RiseChance`, 50 by default), or the share of a mod that drives rising. It is rolled for each zombie. It stays down instead when any of these hold:

| It stays down when | Set by |
|---|---|
| It is a Bandit | Always |
| Its head is off ([Zombie Dismemberment](#compatibility)) | Always |
| Both its arms are off and a leg is lost ([Zombie Dismemberment](#compatibility)) | Always: it could only lie there |
| Another mod keeps it down | That mod, through `addVeto` |
| It was a player | `RisePlayers` (off by default) |
| It died while burning | `FireStaysDown` (on by default) |
| It died within 5 seconds of a melee hit to its head while it lay on the floor | `HeadHitsStayDown` (experimental, off by default) |
| It has already risen as often as allowed | `MaxRises` (1 by default) |
| The share is 0, or its roll misses | `RiseChance`, or the driving mod |

## Getting up

- A marked corpse comes due at a random time between `RiseDelayMin` and `RiseDelayMax` in-game hours after its death (1 to 2 by default).
- Corpses are checked every 10 in-game minutes. With the mod's own options a due corpse gets up at the next check; a mod that drives rising can keep due corpses waiting, for example until night, and they get up at the first check after it lets them.
- It rises where it lies, in the outfit it died in, and stands up within seconds. A corpse that has turned into a skeleton rises as one.
- A corpse in an area no player has loaded waits until one does.
- At most `RisesPerScan` corpses rise in one check on the whole server. A check searches around for at most five times that many corpses that aren't where they died, and the rest wait for the next check.
- A dragged corpse is followed to where it is put down. A corpse that isn't found three checks in a row (burned, buried, removed or carried off) is dropped.

## Keeping a corpse down

| Way | Detail |
|---|---|
| **Burn it** | Burning a corpse with petrol and a lighter keeps it down as soon as the burn is done, even where the server lets no fire start (no fire allowed, water, a safehouse without fire) and in the seconds before the fire takes it. A zombie that dies burning stays down too, with `FireStaysDown` on. |
| **Finish off** | Right-click zombie corpses: **Finish off** for the nearest one not yet finished off, as the game's own corpse options pick one, or **Finish off N corpses** when several lie on its tile. You walk up to it and work for `FinishOffSeconds` (3 by default), and it never rises again. Each corpse can be finished off once, by anyone: every player's game then leaves it out of the menu. It is offered on every corpse not yet finished off, so the menu doesn't show which ones would rise. The server takes it only from a player within 3 tiles. With [Zombie Dismemberment](#compatibility) and its decapitation on, Finish off takes the head off. |
| **Floor head hits** | With `HeadHitsStayDown` on, a zombie that dies within 5 seconds of a melee hit to its head while it lay on the floor stays down. It is a separate switch from Finish off. |
| Bury it, or carry it away | A buried corpse is gone. One carried off as an item is no longer found, and is dropped after three checks. |
| Safehouses | With `RiseInSafehouses` off (the default), a corpse inside a claimed safehouse stays down. |
| Age | A corpse whose zombie died more than `RiseMaxAgeHours` ago (168 by default) stays down. A check drops it, and dragging it later doesn't bring it back unless the option has been raised or set to 0 since. |
| The waiting limit | Above `RiserLimit` marked corpses (5000 by default), the oldest stays down, even if it is dragged later. |
| Stairs | A corpse on stairs can't play dead, so it stays down. So does every corpse while `ZombieLore.DisableFakeDead` is 3 (never); the log warns once. |

With `FinishOff` off and `HeadHitsStayDown` off (its default), only burning, burying or carrying a corpse away keeps it down.

## Kill counts and Rises per body

- Every rise means one more kill for every kill counter: the game's, and other mods' that count kills or give XP or traits for them. The rise share, `MaxRises` and Finish off limit how often one body can be killed.
- A risen zombie keeps its count of rises only until the game unloads it: when it walks out of the loaded area, at every restart and at every load of a single player game it is an ordinary zombie again, and its count starts over.
- Only zombies marked when they die get up. No corpse climbs out of the ground.

## Options

Each option is `RelentlessDead.<Option>` in the sandbox settings, on the **Relentless Dead** page. Every one is read while the game runs, so a change applies at once.

| Option | In game | Default | Range | What it does |
|---|---|---|---|---|
| `RiseChance` | Rise chance | `50` | 0 to 100 | Percent of the zombies killed that are marked to rise, while no other mod drives rising. |
| `RiseDelayMin` | Rise after at least | `1.0` | 0.0 to 48.0 | In-game hours from death until a marked corpse may get up, at least. |
| `RiseDelayMax` | Rise after at most | `2.0` | 0.0 to 48.0 | The same, at most. Each corpse gets a random time in between. Below `RiseDelayMin`, the two are swapped and the log warns once. |
| `MaxRises` | Rises per body | `1` | 0 to 20 | Times one body can rise; 0 for no limit. The count starts over when the risen zombie unloads. |
| `RiseMaxAgeHours` | Oldest corpse that rises | `168` | 0 to 8760 | A marked corpse older than this many in-game hours stays down; 0 for no limit. |
| `FireStaysDown` | Burned zombies stay down | `true` | true or false | A zombie that dies burning is never marked to rise. A burned corpse stays down either way. |
| `FinishOff` | Finish off | `true` | true or false | Offer Finish off on zombie corpses, once per corpse, which keeps them down. |
| `FinishOffSeconds` | Finish off time | `3` | 1 to 30 | How long Finish off takes, in seconds at normal game speed. |
| `HeadHitsStayDown` | Floor head hits keep zombies down | `false` | true or false | Experimental: a zombie killed within 5 seconds of a melee hit to its head while on the floor stays down. Only the attacker's own game knows where a hit landed, so it reports the hit, and the server takes the report only from a player within 3 tiles. Standing head hits and firearms don't count. |
| `RiseInSafehouses` | Corpses rise in safehouses | `false` | true or false | Off: a corpse inside a claimed safehouse stays down. |
| `RisePlayers` | Players' zombies rise | `false` | true or false | A zombie that was a player can be marked to rise. |
| `RisesPerScan` | Rises per check | `10` | 1 to 100 | Most corpses that rise per check (every 10 in-game minutes) on the whole server. |
| `RiserLimit` | Most corpses waiting | `5000` | 100 to 50000 | Most marked corpses kept waiting; above it the oldest stays down. |
| `Verbose` | Verbose log | `false` | true or false | Write each death with its roll, each rise, every corpse kept down and every Finish off to the log. |

An option with a value the game shouldn't hold is replaced by its default, and the log warns. Warnings and errors are always logged, prefixed `[RelentlessDead]`.

## Status

Right-click the world: **Relentless Dead status** is there in single player, and in multiplayer for players whose role has the sandbox options permission (admins). The server refuses anyone else. It shows how many corpses wait to rise and the rise and wake in effect, and writes the full report to the log of the admin's game (`Zomboid/console.txt`), and on a server to the server's log too:

- the mod version;
- the rise and wake in effect and who sets them (the mod's own options, or the driving mod and its label), the corpses registered and due, and the last check;
- this session's counts: marked, kept down, risen, finished off, gone, too old, over the limit;
- the drivers, vetoes and before-rise functions other mods gave;
- whether Zombie Dismemberment is loaded and whether Finish off takes heads off;
- a warning when Undying Zombies is loaded too.

## Multiplayer and performance

| Where | What runs |
|---|---|
| The server (or the single player game) | Marking at each death, the checks every 10 in-game minutes and the corpses waiting, kept in the save. Finish off, head-hit reports and burns, which it checks and keeps down. |
| Every player's game | The Finish off menu and action, its own player's head-hit reports, and the corpses other players finished off, which it leaves out of the menu (and takes the heads off with Zombie Dismemberment). |

| Option | Cost |
|---|---|
| `RisesPerScan` (10) | Corpses that rise per check, every 10 in-game minutes; each check searches for at most five times this many moved corpses. |
| `RiserLimit` (5000) | Marked corpses kept waiting in the save. |
| `Verbose` (off) | Every death, rise and keep-down written to the log. |

## For modders

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

**addVeto(name, fn):** `fn(zombie)` runs at each death, before the roll, and returns why the zombie stays down (a text, or `true`), or `nil`. It runs after the built-in rules (Bandits, heads off, no arms and a leg off). One that throws keeps nothing down, with a warning. `nil` instead of `fn` removes it; the same name again replaces it.

**addBeforeRise(name, fn):** `fn(body)` runs on the corpse just before it rises, playing dead and with its rise counted; what it changes in the corpse's modData rises with the zombie. It can't stop the rise. One that throws doesn't stop it either, with a warning.

**keepDown(body, why):** keeps the zombie corpse `body` down for good: it is never marked to rise again, and a revival timer the game holds for it (as Undying Zombies sets) is cancelled. A player's corpse keeps the game's timer, with which the game turns infected players. `why` goes to the log.

**OnRisingRose(zombie, rises):** an event that fires on the server and in single player after each rise: `zombie` is the zombie that just got up, already in the world, and `rises` how often this body has risen.

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

## Compatibility

From the mods' code where it is public. None of these was tested together with Relentless Dead in game yet.

- **Zombie Dismemberment:** a zombie whose head it took off never rises, nor does one with both arms off and a leg lost, which it keeps on the floor. With its decapitation on (its own `Enabled` and `EnableDecapitation` options), Finish off takes the head off as it does, which removes hats, glasses and masks from the corpse, on the server and on every player's game that has the corpse loaded. Its author has not yet tested its multiplayer in a live session.
- **Undying Zombies:** it raises corpses through the game's own revival timer, whatever this mod's rules say. Every way this mod keeps a corpse down (Finish off, burning, head hits, the safehouse and other checks, `keepDown`) also cancels that timer, but a corpse this mod never marked can still rise through Undying Zombies. Use just one of the two: the log and the Status warn when both are loaded.
- **Bandits:** they never rise.
- **Day and night mods:** a mod can drive rising through the API. Crepuscular does: its `rise=` and `wake=` set the share and when corpses get up, by day, night and event.
- **Special-zombie mods:** their monsters rise as any corpse does, in the same outfit, unless a veto keeps them down; what they can do after that is up to their own mod.
- **The game's corpse removal** (`HoursForCorpseRemoval`) removes corpses whatever their mark. Players' corpses and the game's turning of infected players are left alone.
- **Kill counters and XP mods:** each rise is another kill.

## Known limitations

- **Counts reset on unload:** a risen zombie that unloads (out of the loaded area, a restart, a single player load) is an ordinary zombie again, and `MaxRises` counts from 0 for it.
- **Corpses on stairs**, and every corpse while `ZombieLore.DisableFakeDead` is 3, can't rise.
- **Corpses carried as an item** count as gone after three checks: put down again later, they stay down.
- **A corpse finished off** on a server only shows as finished off on a player's game that has its area loaded then, or loads it later.

## Not yet verified in game

- That risers stand up at once, their animation, corpses loaded from saved areas, and the order of head-hit reports.
- Finish off on a server: that a player who loads the area later sees the corpse as finished off.
- Burning: that a burn the server refuses keeps the corpse down, and that a due corpse doesn't stand up in the fire.
- Zombie Dismemberment: Finish off's decapitation on a server and on each player's game, and looting such a corpse in multiplayer.
- Undying Zombies alongside: that Finish off and burning cancel its timers.

## Reporting problems

Open an issue in the [issue tracker](../../issues) with:

1. single player or server, and the game version;
2. your Relentless Dead options (the `RelentlessDead` table of `SandboxVars.lua`);
3. the Status report and the `[RelentlessDead]` lines from the log (`Zomboid/console.txt`, or the server's log), with **Verbose log** on if you can;
4. your other mods, especially those that drive rising, raise or dismember zombies;
5. what you expected and what happened.

## Publishing

Run the **Publish** workflow (Actions, Publish, Run workflow), optionally with notes for the top of the change log. It starts from the latest version: the highest `vX.Y.Z` release, or while there is none, the highest `vX.Y.Z` tag. Then:

- **A release** when a commit since then is releasable (below) and something under `Contents/` changed. It is tagged `vX.Y.Z`, its notes are the change log (your notes, then the breaking changes, features and fixes from the commit messages), and `Contents/` and `preview.png` are uploaded to the Workshop item in `workshop.txt`'s `id=`, with the change log as the Steam change note.
- **Only the Workshop page** is updated when the title, description or visibility in `workshop.txt`, or `preview.png`, changed.
- **Nothing** otherwise.

| Commit message | From 0.1.0 | From 1.4.2 |
|---|---|---|
| `fix: ...` | 0.1.1 | 1.4.3 |
| `feat: ...` | 0.2.0 | 1.5.0 |
| `feat!: ...` (any type with `!`), or a `BREAKING CHANGE:` footer | 0.2.0 | 2.0.0 |
| any other type (`docs:`, `chore:`, ...) or message | no release | no release |

A scope is fine (`fix(burning): ...`), and the highest of the commits counts. While MAJOR is 0, a breaking change raises MINOR, as a feature does. A `Release-As: X.Y.Z` footer sets the version instead; it must be higher than the latest. That is how 1.0.0 is made.

**The first release:** while there is no `vX.Y.Z` release or tag, the version comes from a `Release-As: X.Y.Z` footer in a commit message, such as `Release-As: 0.1.0`; without one, Publish stops and says to add one.

The version is set by Publish: `mod.info` has no `modversion=` line in the repository, and Publish writes it into the uploaded copy. When the upload fails, the release stays a pre-release, and the next run uploads it again before it publishes anything newer.

Setup: the `steam` environment holds the secrets `STEAM_USERNAME` and `STEAM_CONFIG_VDF` (steamcmd's `config/config.vdf` after a login with Steam Guard). The item is created by uploading it once from the game, which writes its `id=` into `workshop.txt`.
