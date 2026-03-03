# MonsterMash

A powerful tool for **Doom (1993)** designed to merge multiple Monster and Weapon WAD files into a single PK3 file while automatically resolving conflicts.

## Overview

MonsterMash is designed to work as a plugin for **Obsidian** (level generator) and streamlines the process of combining complex monster and weapon mods. Instead of manually merging incompatible WAD files, MonsterMash intelligently resolves conflicts and generates a unified PK3 package ready for use.

### Key Features

- **Automatic Conflict Resolution**: Resolves DoomeNum conflicts (editor numbers), actor names, and sprite names
- **Monster Classification**: Automatically identifies monster actors and assigns unique DoomeNums
- **Weapon Classification**: Identifies weapon actors, assigns DoomeNums, and slot numbers
- **Obsidian Integration**: Generates a Lua file for seamless integration with Obsidian's level generation
- **Non-Destructive**: Source WAD files remain unmodified during processing
- **Organized Output**: Bundles everything into a clean PK3 file in the Completed folder

## Compatibility

### Will this work with other mods?

**Short answer**: Not typically.

**Long answer**: MonsterMash is designed for a different use case than most Doom mods. While most mods function as randomizers or replacers, MonsterMash takes a unique approach—it allows you to fully customize your monster and weapon loadout for procedural level generation. If you want to experiment with other mods, you're welcome to try, but compatibility is not guaranteed.

## Known Issues

- **Dropbox Compatibility**: If you install MonsterMash with Obsidian living in Dropbox, you may encounter issues. While attempts have been made to mitigate these problems, compatibility is not fully guaranteed.

## Installation

1. **Download** the MonsterMash code and place the folder in your Obsidian addons directory:
   ```
   Obsidian/addons/MonsterMash/MonsterMash/
   ```

2. **Initial Setup**: Navigate to the MonsterMash directory and run:
   ```bash
   cd MonsterMash
   unwad.exe
   ```
   This creates the base folder structure on the first run.

3. **Add Your Content**: Copy your WAD and PK3 files into the `Source/` folder.

4. **Process**: Run `unwad.exe` again to merge and resolve conflicts. Output files will be generated in the `Completed/` folder.

## Usage in Obsidian

1. **Enable the Addon**:
   ```
   Addons → [x] MonsterMash
   ```

2. **Making Changes**: If you modify WAD files:
   - Re-run the unwad.exe and wait for it to complete
   - Disable the addon in Obsidian
   - Restart Obsidian
   - Re-enable the addon
   - Restart Obsidian again

   The restart ensures all changes are properly loaded.

## Included Mods

   I have included two mods that are useful for using this mod:
   - target-spy - this is useful to get names of monsters for troubleshooting purposes
   - big_backpack - because some monsters will require you to use a lot of ammo

   They should both be considered optional, although target-spy is needed if you want to file a bug report. If you want to get the weapon names, I recommend using the following
   UZDoom setting:

   HUD Options -> Display Nametags -> Weapons

## Standalone Usage

You can use MonsterMash as a wad/pk3 file merger only. I've set it up to tag the necessary properties to show up in Ultimate Doom Builder (UDB). Keep in mind this is targeted at ZDoom DECORATE/ZSCRIPT monsters/weapons/pickups only. Monsters/weapons/pickups from games other than Doom II are not currently supported.

## Problem Actors

There are directives you can provide in a DECORATE or ZSCRIPT file

```
//#MonsterMash Disable
//#MonsterMash SliderZero

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
