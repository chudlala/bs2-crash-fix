# BLACK SOULS II Crash Fix

An unofficial fix for the random crashes in **BLACK SOULS II** (RPG Maker VX Ace, Steam), where `Game.exe` closes with no error message after a while, most often right as a battle starts. It's the crash people usually blame on a "memory leak", and it often seems to "infect" a save until you load an older one.

- No game files are redistributed. The fix is one small script that the installer adds to your own copy of the game.
- Your saves are not edited, and saves made with the fix still load without it.
- Fully reversible: `uninstall.bat` restores `Game.rgss3a` byte for byte.

> **Status:** v1.0.1 (experimental). Tested on the Steam version 1.4 (`ver.txt` = `1.4`): the game starts with the fix, and an in-game self-test loaded a late-game save and repeatedly tore down map graphics, including Fallen Leaves and Heat Haze maps, with no errors. Confirmation from full play sessions is still being collected. If it still crashes for you, please open an issue (see the end of this page).
>
> **v1.0.0 didn't work** ("Failed to load script" at startup). If you installed it, just install v1.0.1; it cleans up v1.0.0 automatically.

## Install (about 30 seconds)

1. Close the game. Download **`BS2CrashFix-v1.0.1.zip`** from the [Releases page](https://github.com/chudlala/bs2-crash-fix/releases).
2. Extract it anywhere (your Downloads folder is fine).
3. Double-click **`install.bat`**, then play from Steam as usual.

The installer finds the game through Steam by itself. If it can't, it asks you to paste the game folder path (Steam: right-click the game → **Manage** → **Browse local files**).

- **"Windows protected your PC"?** Click **More info** → **Run anyway**. That's Windows' standard warning for downloaded `.bat` files.
- **"Access is denied"?** Right-click `install.bat` → **Run as administrator**.

**Uninstall:** double-click `uninstall.bat`.

**After a game update** or **Verify integrity of game files**, Steam restores `Game.rgss3a`, which removes the fix. Just run `install.bat` again.

<details>
<summary>What the installer changes</summary>

The engine only loads its script list from inside `Game.rgss3a`, so that's where the fix goes. The installer reads the game's script list (`Data\Scripts.rvdata2`) out of your archive, inserts the fix script right before `Main`, appends the result to the **end** of `Game.rgss3a`, and points that one entry in the archive's file table at it. Nothing else in the archive moves or changes.

It writes `Game.rgss3a.bs2fix` next to the archive, recording the original values. `uninstall.bat` uses it to put the entry back and trim the appended data, which gives back the original `Game.rgss3a` byte for byte. Steam's **Verify integrity of game files** also restores it.

It takes a second or two and needs no extra disk space beyond about 430 KB.
</details>

## What's actually wrong

### 1. The crash: sprites disposed after their viewport (use-after-free)

Every time a battle starts or you change maps, the game tears down the map's graphics (`Spriteset_Map#dispose`). That method frees the map's viewports (the layers sprites are drawn on) at the very end. Several visual-effect scripts hook in *after* that and only then dispose their own sprites, which still point at the viewport that was just freed:

| Script (in-game name) | What | Viewport | When |
|---|---|---|---|
| シグナルディスプレイ (Signal Display) | 3 sprites/planes; each `dispose` frees its own viewport **before** calling `super` | own | every map |
| リッチ木漏れ日 (Rich Sunshine) | 3 sprites | `@viewport2` | every map |
| リッチフォグ (Rich Fog) | 3 planes | `@viewport2` | every map |
| 燻りの森２ (Fallen Leaves) | leaf sprites | `@viewport3` | when active |
| 燻りの森 (Heat Haze) | haze sprite + a temporary tilemap with the same mistake | `@viewport1` | maps 47, 126, 127, 128, 133, 311 |

That's 9 or more accesses to freed memory on every battle start. Most of the time the freed memory is still intact and nothing happens. When something else has already reused it, the engine follows a garbage pointer and crashes.

Evidence from Windows crash dumps (`%LOCALAPPDATA%\CrashDumps\Game.exe.*.dmp`):

- Every crash is the same: `0xC0000005` (access violation) at `RGSS301.dll+0x111a1c`, with an identical call stack each time.
- The faulting instruction walks a linked list (`mov ecx,[edx]`) through a dangling pointer. In one dump, the "pointer" is the ASCII text `tCur`, meaning the freed memory had already been reused for a string.
- **It is not out of memory.** At crash time the process was using only about 225–315 MB of private memory, with 680–820 MB of address space in use (limit: 2 GB). Large-address-aware patches and RAM tweaks don't help.

### 2. Why it gets worse later: New Game+ bloats your save

The New Game+ reset (Common Event 201 周回プレイ準備 and the ending map) runs:

```ruby
adv_self_switches("all", "all", "all", false)
```

That command comes from a small community script ("セルフスイッチ操作ぷらす"). Its "all" option doesn't clear the self-switch table. It loads every map and **writes a `false` entry for every event × A/B/C/D**: 12,379 events × 4 = **49,516 entries**, which are saved and kept forever.

| Save | Playtime | Self-switch data | Objects in save |
|---|---|---|---|
| before first ending | 7:11 | 13 KB (848 entries) | 8,516 |
| right after | 7:52 | **594 KB (49,516 entries)** | 59,208 |
| later | 9:50 | 594 KB (49,516 entries) | 61,377 |

Those entries do nothing. The game only ever asks "is this switch exactly `true`?", so a stored `false` and a missing entry are identical. But they leave about 100,000 extra objects in memory for the rest of that save line, which makes the heap bigger and busier. That makes it more likely the freed memory from bug #1 gets reused, which is when it crashes. In the crash dumps above, sessions around the first ending lasted 54–170 minutes before crashing; later sessions crashed after 16–28 minutes.

This explains the usual community advice. "Load a save from before it started" works because those saves are from before the first ending and don't have the bloat. It wears off as soon as you reach the ending again.

## What the fix does

The installer adds [`src/patch.rb`](src/patch.rb) to the game's own script list, right before `Main`, so the game loads it like any of its other scripts. The patch:

1. **Disposes the effect sprites before the viewports are freed.** It hooks `Spriteset_Map#dispose_viewports` and fixes the dispose order in Signal Display and Heat Haze. The original dispose calls still run afterwards; disposing an already-disposed sprite does nothing in RGSS3.
2. **Stores "off" self-switches as "absent".** Setting a self-switch to anything other than `true` deletes the entry instead of storing `false`, and dead entries are pruned when a save loads. New Game+ still resets everything exactly as before. All 289 "on" switches in a typical late save are kept.

### FAQ

**Does it change gameplay or New Game+?** No. Every switch reads the same as before. Every place the game reads or writes self-switches (event page conditions, the Conditional Branch and Control Self Switch event commands, the NG+ script, save/load) only checks for `true`.

**Will it break my saves?** No. Save files on disk aren't touched. Saves made with the fix just leave out the dead entries, so they're smaller. They load fine in the unpatched game.

**Translations / mod loader?** This is built and checked only on the plain Steam game launched from `Game.exe`. Untested with the mod loader, fan translations, or other script mods.

## Building from source

```bash
python build.py
```

That writes `dist/BS2CrashFix.patch` (`src/patch.rb` as one script-list entry), `dist/install.bat` and `dist/uninstall.bat` (from `src/installer.ps1`), and the release zip in `release/`. The output contains only the code in `src/`, never any game code; the game's scripts are only ever read from the player's own `Game.rgss3a`, on their machine.

## Reporting problems

Please open an issue with:

- what happened (crash, error popup with its text, or something odd in-game),
- your game version (`ver.txt` in the game folder),
- if it crashed, the newest `Game.exe.*.dmp` from `%LOCALAPPDATA%\CrashDumps`, if you're comfortable sharing it.

## Credits & disclaimer

Not affiliated with the developers or publisher of BLACK SOULS II. All game content belongs to its owners; this repository contains none of it. The scripts patched here are the game's bundled community scripts, credited to their original authors in the game's script headers.

Fix code: MIT License, see [LICENSE](LICENSE).
