# MonsterMash

## What this does

MonsterMash is a mod for Obsidian (Doom level generator) that that lives in the addons folder.

You put your source wad files in Obsidian/addons/MonsterMash/MonsterMash/Source/

Then you run the executable ```crystal unwad.cr``` and wait seconds, minutes, hours (depending on your system)...

It will resolve a variety of conflicts: doomednum (aka "editor number"), actor name, sprite name

Maps are deleted (from the output... your input files are not modified)

The wads are then bundled back up and dropped in Completed

If there are bugs in your code, or missing sprites, those will remain and break things.

It will identify monster actors and assign doomednums to them

It will output a lua file that interfaces with Obsidian and lets you use those monsters in generated levels

## Will this work with ______ (other mod)?

Short answer: No.

Long answer: The purpose of this mod is to allow you to fully customize your monster/weapon loadout. Most of the time mods are made as randomizers and/or replacers. This takes a completely different approach of generating levels with the monsters you supply, in the amounts that you prefer.

If you want to do it anyway: try it and see if it works. If it does, great! If not, fix it yourself. :)

## Known Issues

- Dropbox may cause issues if you install this to Obsidian living in Dropbox
- Only DECORATE code is resolved at the present time, so if your monster uses ZSCRIPT, too bad.
- Only Monster actors are resloved, Weapons/Ammo is not handled yet

## Usage

Download code and put in Obsidian/addons/MonsterMash/MonsterMash/(this code) (I need to fix this directory structure)

Tested on v7.x or higher Obsidian and new "unstable" v21. Both seem to work ok.

## Prerequisites

Install Crystal:

- Windows: install WSL and Crystal WSL

- Linux: install Crystal

Install OpenSSL Development:

- Linux (Fedora):
```sudo dnf install openssl-devel```

## Run it

I'll be building executable binaries for each OS once the bugs get resolved but for now:

```crystal unwad.cr```
