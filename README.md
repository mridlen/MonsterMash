# MonsterMash

A powerful tool for **Doom (1993)** designed to merge multiple Monster/Pickup/Weapon WAD files into a single PK3 file while automatically resolving conflicts.

## Overview

MonsterMash is designed to work as a plugin for **Obsidian** (level generator) and streamlines the process of combining complex monster and weapon mods. Instead of manually merging incompatible WAD files, MonsterMash intelligently resolves conflicts and generates a unified PK3 package ready for use.

### Key Features

- **Automatic Conflict Resolution**: Resolves DoomeNum conflicts (editor numbers), actor names, and sprite names
- **Monster Classification**: Automatically identifies monster actors and assigns unique DoomedNums
- **Weapon Classification**: Identifies weapon actors, assigns DoomedNums, and slot numbers
- **Pickup Classification**: Identifies pickup and nice item actors (a nice item is a powerful health or armor pickup), assigns DoomedNums, and slot numbers
- **Obsidian Integration**: Generates a Lua file for seamless integration with Obsidian's level generation
- **Non-Destructive**: Source WAD files remain unmodified during processing
- **Organized Output**: Bundles everything into a clean PK3 file in the Completed folder

## Compatibility

### Will this work with other mods?

**Short answer**: Not typically.

**Long answer**: MonsterMash is designed for a different use case than most Doom mods. While most mods function as randomizers or replacers, MonsterMash takes a unique approach. It allows you to fully customize your monster and weapon loadout for procedural level generation. If you want to experiment with other mods, you're welcome to try, but compatibility is not guaranteed.

## Known Issues

- **Dropbox Compatibility**: If you install MonsterMash with Obsidian living in Dropbox, you may encounter issues. While attempts have been made to mitigate these problems, compatibility is not fully guaranteed.

## Installation

1. **Download** the latest release zip from [GitHub Releases](https://github.com/mridlen/MonsterMash/releases) and extract it into your Obsidian addons directory:
   ```
   Obsidian/addons/MonsterMash/MonsterMash/
   ```

2. **Launch the GUI**: Double-click `MonsterMash.bat` in the `MonsterMash/MonsterMash/` folder. On first run, a setup dialog will guide you through placing your files.

3. **Add Your Content**: Use the "Open Source Folder" and "Open IWADs Folder" buttons to place your WAD/PK3 mod files and IWAD files in the correct locations.

4. **Process**: Click "Run Unwad" to merge and resolve conflicts. Output will stream in real-time in the output window, and results will be generated in the `Completed/` folder.

You can also run `unwad.exe` directly from the command line if you prefer (see Command Line Options below).

## Usage in Obsidian

1. **Enable the Addon**:
   ```
   Addons → [x] MonsterMash
   ```

2. **Making Changes**: If you modify WAD files:
   - Run MonsterMash again (via the GUI or command line) and wait for it to complete
   - Disable the Monster Mash addon in Obsidian
   - Restart Obsidian
   - Re-enable the Monster Mash addon
   - Restart Obsidian again

   The restart ensures all changes are properly loaded.

## Included Mods

   I have included two mods that are useful for using this mod:
   - target-spy - this is useful to get names of monsters for troubleshooting purposes
   - big_backpack - because some monsters will require you to use a lot of ammo

   They should both be considered optional, although target-spy is needed if you want to file a bug report. If you want to get the weapon names, I recommend using the following
   UZDoom setting:

   HUD Options -> Display Nametags -> Weapons

## Command Line Options

```
unwad.exe [OPTIONS]
```

### General

| Flag | Description |
|------|-------------|
| `-h`, `--help` | Show help message and exit |
| `--tutorial` | Run the first-run tutorial walkthrough |

### Cleanup

| Flag | Description |
|------|-------------|
| `--clean-only` | Clean up temporary directories (Processing, IWADs_Extracted, PK3_Build) and exit. Leaves Completed/ intact. |
| `--no-cleanup` | Skip post-run cleanup, keeping temporary directories for troubleshooting. Use `--clean-only` to clean up later. |

### Slider Defaults

These flags set the default slider values in the generated Obsidian Lua module. Values must be between 0 and 20, in increments of 0.02. Both `--flag=N` and `--flag N` syntax are supported.

| Flag | Default | Description |
|------|---------|-------------|
| `--weapon-default=N` | 0 | Default weapon slider value |
| `--monster-default=N` | 1 | Default monster slider value |
| `--ally-default=N` | 1 | Default ally slider value |
| `--ammo-default=N` | 10 | Default ammo slider value |
| `--nice-item-default=N` | 0.3 | Default nice item slider value |
| `--pickup-default=N` | 0.3 | Default pickup slider value |

### Verbosity

| Flag | Description |
|------|-------------|
| `-v` | Warnings |
| `-vv` | Warnings + info |
| `-vvv` | Warnings + info + debug |

All log output is also written to `unwad.log` in the MonsterMash directory.

## Standalone Usage

You can use MonsterMash as a wad/pk3 file merger only. I've set it up to tag the necessary properties to show up in Ultimate Doom Builder (UDB). Keep in mind this is targeted at ZDoom DECORATE/ZSCRIPT monsters/weapons/pickups only. Monsters/weapons/pickups from games other than Doom II are not currently supported.

## MonsterMash Directives

You can add special comment directives inside DECORATE or ZSCRIPT actor definitions to control how MonsterMash handles specific actors.

```
//#MonsterMash Disable
//#MonsterMash SliderZero
//#MonsterMash LiquidSpawn

//For example:
//DECORATE
actor BLAH 12345
{
   //#MonsterMash Disable
}

//ZSCRIPT
class BLAH
{
   Default
   {
      //#MonsterMash SliderZero
      <code...>
   }
   <code...>
}
```

These are special commands sent to MonsterMash.

### Disable

Disables the actor in question. It will still remain in the code, but it will not be assigned a doomednum. (Note: If you want to completely disable a wad or pk3, you should just remove it from your Source directory.)

### SliderZero

The slider will be defaulted to "off" in MonsterMash. Useful for disabling weapons you don't want all the time. For example, there are tons of melee weapons that are fairly weak. Or certain weapons are extremely dangerous like the Nuclear Missile. Certain monsters are extremely annoying or extremely dangerous. These are all good candidates for SliderZero.

### LiquidSpawn

Marks a monster as liquid-only, meaning Obsidian will only place it in sectors containing liquid (water, lava, nukage, etc.). This is useful for aquatic or swimming monsters that don't make sense on dry land. There is no way to detect this programmatically from the actor definition, so it must be tagged manually.

## JeuTool

I have used JeuTool to extract wads. However, it didn't handle duplicate lumps, so I had to modify the source code. Since it is GPL, I have included the full source of the modified jeutool (it isn't very big).

Related note: PK3 files are just zip files under another name, so they don't require any special tools to extract.