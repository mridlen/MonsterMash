###############################################################################
# Unwad.cr V2 — Monster Mash WAD Processor
# A complete refactor of V1 with bug fixes and structural improvements.
#
# CHANGELOG from V1:
#  [BUGFIX]  doomednum_info[8102] was duplicated; 8103 now correct
#  [BUGFIX]  FileUtils.rm_rf("./Processing/*") replaced with proper glob+delete
#  [BUGFIX]  #include regex now uses Crystal's $~ match data, not Ruby's $1
#  [BUGFIX]  File re-read after per-line processing no longer discards work
#  [BUGFIX]  Actor line parsing for 6/7 word lines had wrong field indices
#  [BUGFIX]  flag_boolean == false (comparison) → flag_boolean = false (assign)
#  [BUGFIX]  actor_counter increment was in wrong scope during renames
#  [BUGFIX]  Doomednum insertion now goes BEFORE '{' or comment, not after
#  [BUGFIX]  Removed 400+ lines of dead code after exit(0)
#  [BUGFIX]  Recursive PCRE regex replaced with iterative brace-matching
#  [BUGFIX]  Sprite prefix increment_prefix now only increments to new prefix
#            for wads that actually conflict (not just re-using same prefix)
#  [REFACTOR] 600+ lines of elsif flag/property chains → hash-based dispatch
#  [REFACTOR] Extracted reusable helper methods
#  [REFACTOR] Added configurable logging (LOG_LEVEL)
#  [FEATURE]  Added -v/-vv/-vvv CLI flags for runtime log verbosity control
#  [REFACTOR] Proper error handling with begin/rescue blocks
#  [REFACTOR] Consistent code style and comments
###############################################################################

puts "=== Unwad V2 — Monster Mash WAD Processor ==="

require "file"
require "file_utils"
require "regex"
require "digest/sha256"
require "compress/zip"

###############################################################################
# REQUIRES — MonsterMash modules
###############################################################################

require "./requires/classes.cr"
require "./requires/helpers.cr"             # Config, logging, utility functions
require "./requires/pk3_extract.cr"         # PK3/ZIP extraction
require "./requires/extraction.cr"          # Source/IWAD extraction loops
require "./requires/actor_parsing.cr"       # Actor property/flag dispatch + main parse loop
require "./requires/actor_renaming.cr"      # Actor name conflict resolution
require "./requires/actor_classification.cr" # Monster/weapon/ammo/pickup evaluation
require "./requires/weapon_damage_calc.cr"  # Weapon damage & rate from Fire state
require "./requires/lua_gen.cr"             # Lua module generation for Obsidian
require "./requires/tutorial.cr"            # First-run tutorial walkthrough
require "./requires/doomednum_assign.cr"    # Reserved doomednum data & assignment
require "./requires/sprite_conflicts.cr"    # Sprite prefix conflict resolution
require "./requires/sound_conflicts.cr"     # Sound lump conflict resolution
require "./requires/pk3_merge.cr"           # Final PK3 merge pipeline

###############################################################################
# CLI HELP
###############################################################################

if ARGV.includes?("-h") || ARGV.includes?("--help")
  puts ""
  puts "Usage: unwad [OPTIONS]"
  puts ""
  puts "Monster Mash WAD Processor — extracts, parses, deduplicates, and merges"
  puts "Doom mod WADs/PK3s into a single combined PK3 with an Obsidian Lua module."
  puts ""
  puts "Options:"
  puts "  -h, --help          Show this help message and exit"
  puts "  --tutorial          Run the first-run tutorial walkthrough"
  puts "  --clean-only        Clean up temporary dirs (Processing, IWADs_Extracted,"
  puts "                      PK3_Build) and exit — leaves Completed/ intact"
  puts "  --no-cleanup        Skip post-run cleanup (keep temporary dirs for"
  puts "                      troubleshooting; use --clean-only to clean up later)"
  puts "  -v                  Verbosity: warnings"
  puts "  -vv                 Verbosity: info"
  puts "  -vvv                Verbosity: debug"
  puts ""
  puts "Directories:"
  puts "  Source/              Place your mod WADs/PK3s here (input)"
  puts "  IWADs/              Place your IWAD files here (e.g. doom2.wad)"
  puts "  Completed/          Output PK3 and reports are written here"
  puts "  Processing/         Temporary — extracted mod data (cleared each run)"
  puts "  IWADs_Extracted/    Temporary — extracted IWAD data (cleared each run)"
  puts "  PK3_Build/          Temporary — PK3 assembly staging (cleared each run)"
  puts ""
  exit 0
end

###############################################################################
# PLATFORM-SPECIFIC TOOL SELECTION
###############################################################################

jeutoolexe = ""
{% if flag?(:linux) %}
  jeutoolexe = "jeutool-linux"
{% elsif flag?(:darwin) %}
  jeutoolexe = "jeutool-macos"
{% elsif flag?(:win32) %}
  jeutoolexe = "jeutool.exe"
{% end %}
log(2, "Jeutool assigned: #{jeutoolexe}")

###############################################################################
# DATA STRUCTURES
###############################################################################

doomednum_info = build_reserved_doomednums() # requires/doomednum_assign.cr

###############################################################################
# CREATE DIRECTORIES
###############################################################################

[PROCESSING_DIR, SOURCE_DIR, COMPLETED_DIR, IWADS_DIR, IWADS_EXTRACTED_DIR, PK3_BUILD_DIR].each do |dir|
  Dir.mkdir_p(dir)
  log(3, "Ensured directory: #{dir}")
end

###############################################################################
# TUTORIAL / FIRST-RUN CHECK
# Run the walkthrough if --tutorial was passed, or if Source/ or IWADs/ is
# empty (indicating the user hasn't set things up yet).
###############################################################################

source_empty = Dir.children(SOURCE_DIR).empty?
iwads_empty  = Dir.children(IWADS_DIR).reject { |f| f == ".gitkeep" }.empty?

if ARGV.includes?("--tutorial") || source_empty || iwads_empty
  run_tutorial # requires/tutorial.cr
  exit 0
end

###############################################################################
# CLI FLAGS — Cleanup behavior
###############################################################################

flag_no_cleanup = ARGV.includes?("--no-cleanup")
flag_clean_only = ARGV.includes?("--clean-only")

# --clean-only: clear temporary dirs (not Completed) and exit immediately
if flag_clean_only
  log(2, "Clean-only: clearing Processing, IWADs_Extracted, and PK3_Build...")
  puts "Removing files from Processing directory..."
  clear_directory(PROCESSING_DIR)      # requires/helpers.cr
  puts "Removing files from IWADs_Extracted directory..."
  clear_directory(IWADS_EXTRACTED_DIR)  # requires/helpers.cr
  puts "Removing files from PK3_Build directory..."
  clear_directory(PK3_BUILD_DIR)        # requires/helpers.cr
  puts "Cleanup complete (--clean-only). Exiting."
  exit 0
end

###############################################################################
# PRE-RUN CLEANUP
###############################################################################

log(2, "Cleaning up Processing, Completed, IWADs_Extracted, and PK3_Build...")
clear_directory(PROCESSING_DIR)      # requires/helpers.cr
clear_directory(COMPLETED_DIR)       # requires/helpers.cr
clear_directory(IWADS_EXTRACTED_DIR)  # requires/helpers.cr
clear_directory(PK3_BUILD_DIR)        # requires/helpers.cr
log(2, "Cleanup completed.")

###############################################################################
# WAD / PK3 EXTRACTION
###############################################################################

extract_source_mods(jeutoolexe) # requires/extraction.cr
extract_iwads(jeutoolexe)       # requires/extraction.cr

###############################################################################
# PARSE DECORATE/ZSCRIPT ACTORS
###############################################################################

# Build list of files to process — both DECORATE and ZSCRIPT
processing_files = Dir.glob("#{PROCESSING_DIR}/*/defs/DECORATE.raw").map { |p| normalize_path(p) }
zscript_files = Dir.glob("#{PROCESSING_DIR}/*/defs/ZSCRIPT.raw").map { |p| normalize_path(p) }
processing_files += zscript_files
processing_files = processing_files.uniq
built_in_actors = Dir.glob("./Built_In_Actors/*/*.txt").map { |p| normalize_path(p) }

no_touchy = Hash(String, Bool).new
processing_files.each { |fp| no_touchy[fp] = false }
built_in_actors.each { |fp| no_touchy[fp] = true }

full_dir_list = built_in_actors + processing_files

parse_result = parse_all_actors(full_dir_list, no_touchy) # requires/actor_parsing.cr
actordb = parse_result.actordb

###############################################################################
# ACTOR RENAMING & DEDUPLICATION
###############################################################################

log(2, "=== Removing Identical Actors === (DISABLED)")
actor_counter = 0

actor_counter = rename_builtin_conflicts(actordb, actor_counter) # requires/actor_renaming.cr
actor_counter = rename_duplicate_actors(actordb, actor_counter)   # requires/actor_renaming.cr
refresh_actordb(actordb)                                          # requires/actor_renaming.cr

# Rebuild name index after renames
actors_by_name = actordb.group_by(&.name)

###############################################################################
# ACTOR CLASSIFICATION — Monster/Weapon/Ammo/Pickup evaluation
###############################################################################

evaluate_monster_status(actordb, actors_by_name)                                        # requires/actor_classification.cr
weapon_actor_set = evaluate_weapon_status(actordb, actors_by_name)                      # requires/actor_classification.cr
ammo_actor_set = evaluate_ammo_status(actordb, actors_by_name)                          # requires/actor_classification.cr
pickup_actor_set = evaluate_pickup_status(actordb, actors_by_name, weapon_actor_set, ammo_actor_set) # requires/actor_classification.cr
detect_zscript_classes(actordb, actors_by_name, weapon_actor_set, ammo_actor_set, pickup_actor_set)  # requires/actor_classification.cr

###############################################################################
# POST-PROCESSING PIPELINE
###############################################################################

doomednum_counter = wipe_and_reassign_doomednums(actordb, weapon_actor_set, ammo_actor_set, pickup_actor_set, doomednum_info) # requires/doomednum_assign.cr

resolve_sprite_conflicts(actordb) # requires/sprite_conflicts.cr

resolve_sound_conflicts(actordb) # requires/sound_conflicts.cr

build_merged_pk3(actordb, weapon_actor_set) # requires/pk3_merge.cr

generate_lua_module(actordb, weapon_actor_set, ammo_actor_set, pickup_actor_set) # requires/lua_gen.cr

###############################################################################
# POST-RUN CLEANUP
###############################################################################

unless flag_no_cleanup
  log(2, "Post-run cleanup: clearing Processing, IWADs_Extracted, and PK3_Build...")
  clear_directory(PROCESSING_DIR)      # requires/helpers.cr
  clear_directory(IWADS_EXTRACTED_DIR)  # requires/helpers.cr
  clear_directory(PK3_BUILD_DIR)        # requires/helpers.cr
  log(2, "Post-run cleanup completed.")
else
  log(2, "Post-run cleanup skipped (--no-cleanup).")
end
