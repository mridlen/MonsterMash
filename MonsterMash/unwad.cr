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
#  [REFACTOR] Proper error handling with begin/rescue blocks
#  [REFACTOR] Consistent code style and comments
###############################################################################

puts "=== Unwad V2 — Monster Mash WAD Processor ==="

require "file"
require "file_utils"
require "regex"
require "digest/sha256"
require "compress/zip"

# Other Code Specific To MonsterMash
require "./requires/classes.cr"
require "./requires/helpers.cr"
require "./requires/pk3_extract.cr"
require "./requires/actor_parsing.cr"
require "./requires/lua_gen.cr"
require "./requires/tutorial.cr"
require "./requires/doomednum_assign.cr"
require "./requires/sprite_conflicts.cr"
require "./requires/sound_conflicts.cr"
require "./requires/pk3_merge.cr"

###############################################################################
# CONFIGURATION
###############################################################################

# Log levels: 0 = errors only, 1 = warnings, 2 = info, 3 = debug/verbose
LOG_LEVEL = 2

LOG_FILE = File.open("unwad.log", "w")
LOG_FILE.puts "=== Unwad V4 Log Started: #{Time.local} ==="
LOG_FILE.flush

def log(level : Int32, msg : String)
  return if level > LOG_LEVEL
  prefix = case level
           when 0 then "[ERROR]"
           when 1 then "[WARN] "
           when 2 then "[INFO] "
           else        "[DEBUG]"
           end
  line = "#{prefix} #{msg}"
  puts line
  LOG_FILE.puts line
  LOG_FILE.flush
end

at_exit do
  LOG_FILE.puts "=== Log Ended: #{Time.local} ==="
  LOG_FILE.close
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

actordb = Array(Actor).new
duped_names_db = Array(DupedActorName).new
duped_graphics_db = Array(DupedGraphics).new
duped_doomednum_db = Array(DupedDoomednums).new

doomednum_info = build_reserved_doomednums() # requires/doomednum_assign.cr

###############################################################################
# CREATE DIRECTORIES
###############################################################################

["./Processing", "./Source", "./Completed", "./IWADs", "./IWADs_Extracted", PK3_BUILD_DIR].each do |dir|
  Dir.mkdir_p(dir)
  log(3, "Ensured directory: #{dir}")
end

###############################################################################
# TUTORIAL / FIRST-RUN CHECK
# Run the walkthrough if --tutorial was passed, or if Source/ or IWADs/ is
# empty (indicating the user hasn't set things up yet).
###############################################################################

source_empty = Dir.children("./Source").empty?
iwads_empty  = Dir.children("./IWADs").reject { |f| f == ".gitkeep" }.empty?

if ARGV.includes?("--tutorial") || source_empty || iwads_empty
  run_tutorial
  exit 0
end

###############################################################################
# PRE-RUN CLEANUP
# [BUGFIX] V1 used FileUtils.rm_rf("./Processing/*") which doesn't glob.
#          Now using proper directory clearing.
###############################################################################

log(2, "Cleaning up Processing, Completed, and IWADs_Extracted...")
clear_directory("./Processing")
clear_directory("./Completed")
clear_directory("./IWADs_Extracted")
log(2, "Cleanup completed.")

###############################################################################
# WAD / PK3 EXTRACTION
# WAD files are extracted with jeutool; PK3/ZIP files use Crystal's built-in
# ZIP reader with directory structure normalization.
###############################################################################

log(2, "Extraction process starting...")

wad_extensions = Set{".wad"}
pk3_extensions = Set{".pk3", ".zip", ".pk7", ".ipk3", ".ipk7"}

# ── Source mods ──────────────────────────────────────────────────────────────
source_files = Dir.children("./Source").select { |f| File.file?("./Source/#{f}") }
total_source = source_files.size

source_files.each_with_index do |file_name, file_index|
  file_path = "./Source/#{file_name}"

  ext = File.extname(file_name).downcase
  base = File.basename(file_name, File.extname(file_name))

  # Progress bar
  print_progress_bar(file_index, total_source, "Extracting #{base}")

  if wad_extensions.includes?(ext)
    puts ""  # Newline before jeutool output
    log(3, "Extracting WAD: #{file_path}")
    system "./#{jeutoolexe} extract \"#{file_path}\" \"./Processing/#{base}\" -r"

  elsif pk3_extensions.includes?(ext)
    dest = normalize_path("./Processing/#{base}")
    log(3, "Extracting PK3: #{file_path}")
    extract_pk3(file_path, dest)

  else
    log(1, "Skipping unknown file type in Source/: #{file_name} (#{ext})")
  end
end
puts "" # Clear progress bar

# ── IWADs ────────────────────────────────────────────────────────────────────
Dir.each_child("./IWADs") do |file_name|
  file_path = "./IWADs/#{file_name}"
  next unless File.file?(file_path)

  ext = File.extname(file_name).downcase
  base = File.basename(file_name, File.extname(file_name))

  if wad_extensions.includes?(ext)
    log(2, "Extracting IWAD WAD: #{file_path}")
    system "./#{jeutoolexe} extract \"#{file_path}\" \"./IWADs_Extracted/#{base}\" -r"

  elsif pk3_extensions.includes?(ext)
    dest = normalize_path("./IWADs_Extracted/#{base}")
    log(2, "Extracting IWAD PK3: #{file_path}")
    extract_pk3(file_path, dest)

  else
    log(1, "Skipping unknown file type in IWADs/: #{file_name} (#{ext})")
  end
end

log(2, "Extraction complete.")

###############################################################################
# (Extraction now writes directly to Processing/ and IWADs_Extracted/)
###############################################################################

###############################################################################
# POST-EXTRACTION PROCESSING — Parse DECORATE actors
###############################################################################

log(2, "Starting DECORATE/ZSCRIPT processing...")

# Build list of files to process — both DECORATE and ZSCRIPT
processing_files = Dir.glob("./Processing/*/defs/DECORATE.raw").map { |p| normalize_path(p) }
zscript_files = Dir.glob("./Processing/*/defs/ZSCRIPT.raw").map { |p| normalize_path(p) }
# Add ZSCRIPT files that don't have a corresponding DECORATE
# (if both exist, DECORATE is primary and ZSCRIPT will be handled separately)
processing_files += zscript_files
processing_files = processing_files.uniq
built_in_actors = Dir.glob("./Built_In_Actors/*/*.txt").map { |p| normalize_path(p) }

no_touchy = Hash(String, Bool).new
processing_files.each { |fp| no_touchy[fp] = false }
built_in_actors.each { |fp| no_touchy[fp] = true }

full_dir_list = built_in_actors + processing_files

missing_property_names = Hash(String, Array(String)).new
missing_actor_flags = Hash(String, Array(String)).new

###############################################################################
# DATA-DRIVEN FLAG & PROPERTY DISPATCH
# [REFACTOR] Replaces 600+ lines of elsif chains with hash lookups.
###############################################################################

# Build a set of all known flag names. We use a proc to set the flag on the actor.
# This replaces the massive if/elsif chain for boolean flags.
KNOWN_FLAGS = Set(String).new

# We'll populate KNOWN_FLAGS from the Actor class at runtime after creating a
# default actor. For now, we define a helper that uses Crystal's property setter.


###############################################################################
# MAIN PARSING LOOP
###############################################################################

full_dir_list.each do |file_path|
  is_built_in = (no_touchy[file_path] == true)

  # Determine wad folder name and source file
  path_parts = file_path.split("/")
  if is_built_in
    wad_folder_name = path_parts[2]? || "unknown"
    decorate_source_file = path_parts[3]? || "unknown"
  else
    wad_folder_name = path_parts[2]? || "unknown"
    decorate_source_file = path_parts[4]? || "unknown"
  end

  log(3, "Processing: #{wad_folder_name} (#{file_path})")

  unless is_built_in
    # [BUGFIX] V1 had include file handling that used Ruby's $1 syntax.
    # Now we properly resolve includes and add them to the processing queue.
    input_file = safe_read(file_path)
    input_file.each_line do |line|
      if line.strip =~ /^#include/i
        if md = line.match(/"([^"]+)"/i)
          include_name = md[1].upcase
          new_path = File.join(File.dirname(file_path), "#{include_name}.raw")
          unless full_dir_list.includes?(new_path)
            full_dir_list << new_path
            no_touchy[new_path] = false
          end
        end
      end
    end
  end

  # Read and clean the file
  input_text = safe_read(file_path)
  next if input_text.empty?

  # Strip leading whitespace per line
  input_text = input_text.gsub(/^\s*/, "")

  # Remove // comments
  input_text = input_text.gsub(%r{//[^\n]*}, "")

  # Remove /* ... */ block comments (non-greedy)
  input_text = input_text.gsub(/\/\*[\s\S]*?\*\//m, "")

  # Put braces on their own lines
  input_text = input_text.gsub('{', "\n{\n")
  input_text = input_text.gsub('}', "\n}\n")

  # Clean up: strip each line, remove blank lines
  input_text = input_text.split("\n").map(&.strip).reject(&.empty?).join("\n")

  # Split on actor definitions
  input_text = input_text.gsub(/^actor\s+/im, "SPECIALDELIMITER__actor ")
  actors = input_text.split("SPECIALDELIMITER__")
  actors.reject!(&.strip.empty?)

  actors.each_with_index do |actor_text, actor_index|
    # Extract states before processing
    states_text = extract_states_text(actor_text)
    states = parse_states(states_text)
    actor_no_states = remove_states_block(actor_text)

    # Get case-sensitive version
    lines_with_case = actor_no_states.lines.map(&.strip).reject(&.empty?)
    next if lines_with_case.empty?
    first_line_with_case = lines_with_case.first
    name_with_case = first_line_with_case.split[1]?
    next unless name_with_case

    # Lowercase version for parsing
    lines = actor_no_states.lines.map { |l| l.strip.downcase }.reject(&.empty?)
    next if lines.empty?

    first_line = lines.first
    words = first_line.split

    # Remove "native" keyword from actor line if present
    native = false
    native_idx = words.index("native")
    if native_idx
      native = true
      words = words[0...native_idx]
    end

    num_words = words.size
    log(3, "Actor: \"#{words[1]?}\" from #{file_path}")

    # Create new actor
    new_actor = Actor.new("#{words[1]?}", actor_index)
    new_actor.name_with_case = name_with_case
    new_actor.source_wad_folder = wad_folder_name
    new_actor.source_file = decorate_source_file
    new_actor.file_path = file_path
    new_actor.native = native
    new_actor.states = states
    new_actor.actor_text = actor_no_states
    new_actor.full_actor_text = actor_text
    new_actor.built_in = is_built_in

    # Parse actor line: actor name [: parent] [replaces target] [doomednum]
    # Possible forms:
    #   actor name                                    (2 words)
    #   actor name doomednum                          (3 words)
    #   actor name : parent                           (4 words)
    #   actor name replaces target                    (4 words)
    #   actor name : parent doomednum                 (5 words)
    #   actor name replaces target doomednum          (5 words)
    #   actor name : parent replaces target           (6 words)
    #   actor name : parent replaces target doomednum (7 words)
    #
    # [BUGFIX] V1 had wrong field indices for 6/7 word forms:
    #   V1 used words[4] for inherits and words[6] for replaces (wrong)
    #   Correct: words[3] for inherits, words[5] for replaces

    case num_words
    when 3
      new_actor.doomednum = words[2].to_i? || -1
    when 4
      if words[2] == ":"
        new_actor.inherits = words[3]
      elsif words[2] == "replaces"
        new_actor.replaces = words[3]
      else
        log(1, "Unexpected word '#{words[2]}' in actor line: #{first_line}")
      end
    when 5
      if words[2] == ":"
        new_actor.inherits = words[3]
        new_actor.doomednum = words[4].to_i? || -1
      elsif words[2] == "replaces"
        new_actor.replaces = words[3]
        new_actor.doomednum = words[4].to_i? || -1
      end
    when 6
      # actor name : parent replaces target
      new_actor.inherits = words[3] if words[2] == ":"
      new_actor.replaces = words[5] if words[4] == "replaces"
    when 7
      # actor name : parent replaces target doomednum
      new_actor.inherits = words[3] if words[2] == ":"
      new_actor.replaces = words[5] if words[4] == "replaces"
      new_actor.doomednum = words[6].to_i? || -1
    end

    # Parse each property/flag line
    lines.each_with_index do |line, index|
      next if index.zero? # skip actor definition line

      property_name = line.split[0]?.to_s.downcase
      next if property_name.empty?

      # Track applied properties/flags
      if property_name =~ /^[\+\-]/
        line.split.each { |flag| new_actor.flags_applied << flag }
      elsif !%w[{ } action const var #include].includes?(property_name)
        new_actor.properties_applied << property_name
      end

      # Handle special keywords
      if property_name == "action" || property_name == "const"
        log(3, "  - #{property_name}: #{line}")
        next
      end

      # Handle variable declarations
      if property_name == "var"
        var_type = line.split[1]?.to_s
        var_name = line.split[2]?.to_s
        new_actor.user_vars[var_name] = var_type
        next
      end

      # Handle "monster" keyword (which also enables ISMONSTER flag and more)
      if property_name =~ /^monster/
        new_actor.monster = true
        # Handle flags concatenated after "monster" (e.g., "monster+boss")
        remaining = line.lchop("monster").lstrip
        if !remaining.empty?
          # Process remaining flags by re-normalizing
          remaining = remaining.gsub(/\+\s*/, " +").gsub(/\-\s*/, " -").lstrip
          remaining.split.each do |flag|
            # [BUGFIX] V1 used == instead of = for flag_boolean = false
            flag_val = (flag[0] == '+')
            fname = flag.lchop
            unless set_actor_flag(new_actor, fname, flag_val)
              log(3, "  Unrecognized flag after monster: #{fname}")
            end
          end
        end
        next
      end

      # Handle boolean flags (+FLAG / -FLAG)
      if property_name =~ /^[\+\-]/
        # Normalize spacing: "+FLAG -FLAG2" etc.
        normalized = line.gsub(/\+\s*/, " +").gsub(/\-\s*/, " -").lstrip
        normalized.split.each do |flag|
          # [BUGFIX] V1: `flag_boolean == false` was comparison, not assignment
          flag_val = (flag[0] == '+')
          fname = flag.lchop.downcase

          unless set_actor_flag(new_actor, fname, flag_val)
            # Track missing flags
            missing_actor_flags[fname] ||= Array(String).new
            missing_actor_flags[fname] << new_actor.source_wad_folder
            missing_actor_flags[fname].uniq!
          end
        end
        next
      end

      # Handle "+ismonster" as a property name (special case)
      if property_name == "+ismonster"
        new_actor.ismonster = true
        next
      end

      # Skip structural tokens
      next if property_name == "{" || property_name == "}" || property_name == "#include"

      # Try setting as a known property
      unless set_actor_property(new_actor, property_name, line)
        # Track missing properties
        missing_property_names[property_name] ||= Array(String).new
        missing_property_names[property_name] << new_actor.source_wad_folder
      end
    end

    actordb << new_actor
  end
end

log(2, "Parsing complete. Total actors loaded: #{actordb.size}")

# Report missing properties/flags
if LOG_LEVEL >= 2
  unless missing_property_names.empty?
    log(2, "=== Missing Properties ===")
    missing_property_names.each { |k, v| log(2, "  #{k}: #{v.uniq.join(", ")}") }
  end
  unless missing_actor_flags.empty?
    log(2, "=== Missing Flags ===")
    missing_actor_flags.each { |k, v| log(2, "  #{k}: #{v.uniq.join(", ")}") }
  end
end

###############################################################################
# REMOVING IDENTICAL ACTORS — DISABLED
# The removal logic was deleting actors that other actors in the same WAD
# depend on (e.g., removing "Bubble" broke "BubbleShort" which inherits it).
# GZDoom handles true duplicates gracefully. Keeping all actors is safer.
###############################################################################

log(2, "=== Removing Identical Actors === (DISABLED)")

actor_counter = 0

###############################################################################
# RENAMING DUPLICATE ACTOR NAMES
###############################################################################

log(2, "=== Renaming Duplicate Actor Names ===")

# Build name index
actors_by_name = actordb.group_by(&.name)

# Remove built-in actors from name groups (don't rename them)
actors_by_name.each_key do |key|
  actors_by_name[key].reject! { |a| a.file_path.split("/")[1]? == "Built_In_Actors" }
end

# Perform renames for any names with count > 1
# [BUGFIX] V1 had actor_counter increment in wrong scope
actors_by_name.each do |key, actors|
  next unless actors.size > 1
  log(2, "Duplicate actor name: #{key} (#{actors.size} copies)")

  actors.each_with_index do |actor, idx|
    next if idx == 0 # Keep the first as primary

    wad_folder = actor.file_path.split("/")[0..-2].join("/") + "/"
    renamed_actor = "#{actor.name_with_case}_MM#{actor_counter}"

    log(3, "  Renaming #{actor.name_with_case} → #{renamed_actor} in #{wad_folder}")

    Dir.children(wad_folder).each do |file|
      file_path_rename = wad_folder + file
      next if File.directory?(file_path_rename)
      file_text = File.read(file_path_rename)
      escaped = Regex.escape(actor.name_with_case)

      # Only rename in contexts where the name is used as a class/actor reference.
      # IMPORTANT: Never rename sprite prefix references in state frame lines.
      # Sprite frames look like: "  SPRT A 1 Action" (prefix + space + frame letter + space/digit)
      # We use targeted patterns that require specific keywords before the name.
      #
      # 1. Actor definition line: "actor Name" at line start (DECORATE definitions).
      #    Excludes ZScript variable declarations like "actor nuke = ..." where
      #    "actor" is used as a type name. Variable declarations have "=" after
      #    the name, while definitions have ":", "{", a number, or "replaces".
      file_text = file_text.gsub(/^(\s*actor\s+)#{escaped}(?=[\s:{])(?![ \t]*=)/mi) { "#{$1}#{renamed_actor}" }
      # 2. Class definition line: "class Name" at line start
      file_text = file_text.gsub(/^(\s*class\s+)#{escaped}(?=[\s:{])/mi) { "#{$1}#{renamed_actor}" }
      # 3. Inheritance reference: ": Name" or ": Name,"
      #    Use [ \t]* instead of \s* to prevent matching across lines
      #    (e.g., "Ready:\n\t\tMINE" where the colon is a state label, not inheritance)
      file_text = file_text.gsub(/(:[ \t]*)#{escaped}(?=[\s,{])/mi) { "#{$1}#{renamed_actor}" }
      # 4. Replaces keyword: "replaces Name"
      file_text = file_text.gsub(/(replaces\s+)#{escaped}(?=[\s{])/mi) { "#{$1}#{renamed_actor}" }
      # 5. Quoted class name references: "Name" (in A_FireProjectile, A_SpawnItemEx, etc.)
      file_text = file_text.gsub(/"#{escaped}"/i, "\"#{renamed_actor}\"")
      # 6. ZScript 'is' type check: is 'Name'
      file_text = file_text.gsub(/'#{escaped}'/i, "'#{renamed_actor}'")

      File.write(file_path_rename, file_text)
    end

    # [BUGFIX] Update actordb entry to match the new name in files.
    # Without this, the refresh step can't find the old name in files and
    # removes the actor, causing doomednum assignment to fail (bugs: machinegun,
    # polymorph, pulserifle).
    actor.name = renamed_actor.downcase
    actor.name_with_case = renamed_actor

    actor_counter += 1
  end
end

###############################################################################
# REFRESH ACTORDB — Remove actors that no longer exist in files
###############################################################################

log(2, "=== Refreshing Actor Database ===")

actordb.reject! do |actor|
  next false if actor.native == true

  regex = /^\s*actor\s+#{Regex.escape(actor.name)}/mi
  all_files = [actor.file_path]

  # Check includes
  file_text = safe_read(actor.file_path)
  file_text.each_line do |line|
    if line =~ /^#include/i
      if md = line.match(/"([^"]+)"/)
        include_path = actor.file_path.split("/")[0..-2].join("/") + "/" + md[1].upcase + ".raw"
        all_files << include_path
      end
    end
  end

  found = all_files.any? { |f| safe_read(f) =~ regex }
  unless found
    log(3, "Removing missing actor: #{actor.name} from #{actor.file_path}")
  end
  !found
end

# Rebuild name index
actors_by_name = actordb.group_by(&.name)

###############################################################################
# EVALUATE MONSTER STATUS VIA INHERITANCE
###############################################################################

log(2, "=== Evaluating Monster Status ===")

actordb.each do |actor|
  next if actor.built_in == true

  is_monster = (actor.monster == true || actor.ismonster == true)

  unless is_monster
    # Walk the inheritance chain
    inheritance = [actor.name]
    inherits_name = actor.inherits

    while inherits_name != "UNDEFINED"
      inherited_actors = actors_by_name[inherits_name]?
      break unless inherited_actors

      # Find the non-built-in version if multiple exist
      target = inherited_actors.find { |a| !a.built_in } || inherited_actors.first?
      break unless target

      inheritance << target.name
      inherits_name = target.inherits
    end

    # Walk reverse order checking monster status
    inheritance.reverse!
    inheritance.each do |inherited_name|
      check_actors = actors_by_name[inherited_name]?
      next unless check_actors

      check_actors.each do |ac|
        if ac.skip_super == true
          is_monster = false
        end
        if ac.monster == true || ac.ismonster == true
          is_monster = true
        else
          ac.flags_applied.each do |flag|
            if flag == "-ismonster"
              is_monster = false
            elsif flag == "+ismonster"
              is_monster = true
            end
          end
        end
      end
    end
  end

  if is_monster
    actor.ismonster = true
    log(3, "Monster confirmed: #{actor.name_with_case}")
  end
end

# Stats
monster_count = actordb.count { |a| a.ismonster || a.monster }
built_in_count = actordb.count { |a| (a.ismonster || a.monster) && a.built_in }
log(2, "Total actors: #{actordb.size}, Monsters: #{monster_count} (Built-in: #{built_in_count})")

###############################################################################
# EVALUATE WEAPON STATUS VIA INHERITANCE
###############################################################################

log(2, "=== Evaluating Weapon Status ===")

# Known base weapon classes (lowercase) — actors inheriting from these are weapons
WEAPON_BASE_CLASSES = Set{
  "weapon", "doomweapon", "hereticweapon", "hexenweapon", "strifeweapon",
  "fist", "chainsaw", "pistol", "shotgun", "supershotgun", "chaingun",
  "rocketlauncher", "plasmarifle", "bfg9000",
}

weapon_actor_set = Set(String).new

actordb.each do |actor|
  next if actor.built_in == true

  is_weapon = false

  # Check 1: Does it have weapon-specific properties applied?
  has_weapon_props = actor.weapon.ammotype != "UNDEFINED" ||
                     actor.weapon.slotnumber != -1 ||
                     actor.weapon.ammouse != -1 ||
                     actor.weapon.ammogive != -1

  # Check 2: Walk the inheritance chain to see if it inherits from Weapon
  if has_weapon_props || actor.inherits != "UNDEFINED"
    inheritance_chain = [actor.name.downcase]
    inherits_name = actor.inherits

    while inherits_name != "UNDEFINED"
      lc_name = inherits_name.downcase
      if WEAPON_BASE_CLASSES.includes?(lc_name)
        is_weapon = true
        break
      end

      inherited_actors = actors_by_name[lc_name]?
      break unless inherited_actors

      target = inherited_actors.find { |a| !a.built_in } || inherited_actors.first?
      break unless target
      break if inheritance_chain.includes?(target.name.downcase) # cycle guard

      inheritance_chain << target.name.downcase
      inherits_name = target.inherits
    end
  end

  # Check 3: Has weapon properties even without recognized inheritance
  if !is_weapon && has_weapon_props
    is_weapon = true
  end

  # Exclusions
  if is_weapon
    # Skip WeaponPiece actors (they are parts of combo weapons, not standalone)
    if actor.weaponpiece.weapon != "UNDEFINED"
      is_weapon = false
    end
    # Skip powered-up variants (Heretic Tome of Power upgrades)
    if actor.weapon.powered_up
      is_weapon = false
    end
    # Skip cheat weapons
    if actor.weapon.cheatnotweapon
      is_weapon = false
    end
    # Skip if no Fire state (can't actually shoot)
    unless actor.states.has_key?("fire") || actor.states.has_key?("altfire")
      is_weapon = false
    end
  end

  if is_weapon
    weapon_actor_set.add(actor.name.downcase)
    log(3, "Weapon confirmed: #{actor.name_with_case}")
  end
end

weapon_count = weapon_actor_set.size
log(2, "Weapons found: #{weapon_count}")

###############################################################################
# ZSCRIPT CLASS DETECTION — Standalone pass for monster/weapon classification.
# The main parser only handles DECORATE 'actor' definitions. ZScript uses
# 'class Name : Parent' syntax which is not parsed into actordb. This pass
# reads ZScript files directly and classifies classes by walking inheritance.
###############################################################################

log(2, "=== ZScript Class Detection ===")

# Known monster base classes (lowercase) — classes inheriting from these are monsters.
# Includes built-in actor names that have MONSTER flag.
MONSTER_BASE_CLASSES = Set(String).new
actordb.each do |actor|
  if actor.built_in && (actor.ismonster || actor.monster)
    MONSTER_BASE_CLASSES.add(actor.name.downcase)
  end
end
# Add common base classes that may not be in built-in actors
{"doomimspecies", "doomimp"}.each { |n| MONSTER_BASE_CLASSES.add(n) }

# Collect all ZScript files in Processing/
zscript_raw_files = Dir.glob("./Processing/*/defs/ZSCRIPT.raw").map { |p| normalize_path(p) }

# Data structure: class_name_lc => {name_with_case, parent_lc, file_path, has_monster_flag, has_fire_state}
zscript_class_info = Hash(String, NamedTuple(
  name_with_case: String,
  parent_lc: String,
  file_path: String,
  has_monster_flag: Bool,
  has_fire_state: Bool,
)).new

zscript_raw_files.each do |file_path|
  content = safe_read(file_path)
  next if content.empty?

  lines = content.lines
  i = 0
  while i < lines.size
    line = lines[i]
    # Match: class ClassName : ParentName
    if md = line.match(/^\s*class\s+(\w+)\s*:\s*(\w+)/i)
      class_name = md[1]
      parent_name = md[2]

      # Scan the class body for MONSTER flag and Fire state
      has_monster_flag = false
      has_fire_state = false
      brace_depth = 0
      j = i
      started = false
      while j < lines.size
        brace_depth += lines[j].count('{') - lines[j].count('}')
        started = true if lines[j].includes?("{")
        if started
          stripped = lines[j].strip.downcase
          if stripped == "monster;" || stripped == "+ismonster" || stripped =~ /^\+ismonster\s*;/
            has_monster_flag = true
          end
          if stripped =~ /^\s*fire\s*:/
            has_fire_state = true
          end
          break if brace_depth <= 0 && started
        end
        j += 1
      end

      zscript_class_info[class_name.downcase] = {
        name_with_case: class_name,
        parent_lc:      parent_name.downcase,
        file_path:      file_path,
        has_monster_flag: has_monster_flag,
        has_fire_state:   has_fire_state,
      }
    end
    i += 1
  end
end

log(2, "  ZScript classes found: #{zscript_class_info.size}")

# Classify each ZScript class as monster, weapon, or neither
zscript_monsters = Hash(String, NamedTuple(name_with_case: String, file_path: String)).new
zscript_weapons  = Hash(String, NamedTuple(name_with_case: String, file_path: String)).new

zscript_class_info.each do |class_lc, info|
  # Walk inheritance chain
  is_monster = info[:has_monster_flag]
  is_weapon = false
  chain_name = info[:parent_lc]
  visited = Set{class_lc}

  while true
    break if visited.includes?(chain_name)  # cycle guard
    visited.add(chain_name)

    if MONSTER_BASE_CLASSES.includes?(chain_name)
      is_monster = true
      break
    end
    if WEAPON_BASE_CLASSES.includes?(chain_name)
      is_weapon = true
      break
    end

    # Check if parent is another ZScript class we know about
    parent_info = zscript_class_info[chain_name]?
    if parent_info
      is_monster = true if parent_info[:has_monster_flag]
      chain_name = parent_info[:parent_lc]
    else
      # Check if parent is a known monster from actordb (built-in DECORATE actors)
      db_actors = actors_by_name[chain_name]?
      if db_actors
        db_actor = db_actors.first
        if db_actor.ismonster || db_actor.monster
          is_monster = true
        end
      end
      break
    end
  end

  if is_monster || is_weapon
    # Check if this actor already exists in actordb (from DECORATE parsing)
    existing = actors_by_name[class_lc]?
    if existing
      # Actor exists in both DECORATE and ZScript — mark as "both"
      existing.each { |a| a.script_type = "both" }
      log(3, "  ZScript #{is_monster ? "monster" : "weapon"} (both): #{info[:name_with_case]}")
    else
      # Create a new Actor entry for this ZScript class
      # Determine wad folder from file path: ./Processing/WadName/defs/ZSCRIPT.raw
      path_parts = info[:file_path].split("/")
      wad_folder = path_parts[2]? || "unknown"

      new_actor = Actor.new(class_lc, actordb.size)
      new_actor.name_with_case = info[:name_with_case]
      new_actor.file_path = info[:file_path]
      new_actor.source_wad_folder = wad_folder
      new_actor.source_file = "ZSCRIPT.raw"
      new_actor.script_type = "zscript"
      new_actor.inherits = info[:parent_lc]
      new_actor.built_in = false

      if is_monster
        new_actor.ismonster = true
        new_actor.monster = info[:has_monster_flag]
      end
      # Weapon status is tracked via weapon_actor_set (populated below)

      actordb << new_actor
      actors_by_name[class_lc] ||= [] of Actor
      actors_by_name[class_lc] << new_actor

      if is_weapon
        weapon_actor_set.add(class_lc)
      end

      log(3, "  ZScript #{is_monster ? "monster" : "weapon"}: #{info[:name_with_case]} (#{info[:file_path]})")
    end
  end
end

zs_monster_count = actordb.count { |a| !a.built_in && a.script_type != "decorate" && (a.ismonster || a.monster) }
zs_weapon_count = actordb.count { |a| !a.built_in && a.script_type != "decorate" && weapon_actor_set.includes?(a.name.downcase) }
log(2, "  ZScript monsters: #{zs_monster_count}, weapons: #{zs_weapon_count}")

doomednum_counter = wipe_and_reassign_doomednums(actordb, weapon_actor_set, doomednum_info) # requires/doomednum_assign.cr

resolve_sprite_conflicts(actordb) # requires/sprite_conflicts.cr

resolve_sound_conflicts(actordb) # requires/sound_conflicts.cr

build_merged_pk3(actordb, weapon_actor_set) # requires/pk3_merge.cr

generate_lua_module(actordb, weapon_actor_set) # requires/lua_gen.cr
