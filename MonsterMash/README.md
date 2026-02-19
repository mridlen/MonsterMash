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

2. **Making Changes**: If you modify WAD files or settings:
   - Disable the addon in Obsidian
   - Restart Obsidian
   - Re-enable the addon
   - Restart Obsidian again

   The restart ensures all changes are properly loaded.