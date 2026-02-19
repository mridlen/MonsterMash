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

###############################################################################
# RESERVED DOOMEDNUMS
###############################################################################

doomednum_info = Hash(Int32, Tuple(Int32, Int32)).new

# Obsidian reserved sector/linedef things
[992, 995, 996, 997, 987].each { |id| doomednum_info[id] = {-1, -1} }

# Reserved Thing IDs (items)
[8166, 8151].each { |id| doomednum_info[id] = {-1, -1} }

# Regular Monsters (radius categories)
# [BUGFIX] V1 had 8102 duplicated where 8103 was intended
[8102, 8103, 8104, 8106, 8108].each { |id| doomednum_info[id] = {-1, -1} }

# Flying Monsters
[8112, 8113, 8114, 8116, 8118].each { |id| doomednum_info[id] = {-1, -1} }

# Caged Monsters
[8122, 8123, 8124, 8126, 8128].each { |id| doomednum_info[id] = {-1, -1} }

# Closet / Trap Monsters
[8132, 8133, 8134, 8136, 8138].each { |id| doomednum_info[id] = {-1, -1} }

# Lights (14992-14999)
(14992..14999).each { |id| doomednum_info[id] = {-1, -1} }

# Custom decorations
[27000, 27001, 27002].each { |id| doomednum_info[id] = {-1, -1} }

# Reserved Linedefs
doomednum_info[888] = {-1, -1}

# Fauna Module
[30100, 30000].each { |id| doomednum_info[id] = {-1, -1} }

# Frozsoul's Ambient Sounds ranges
[20000..20025, 22000..22025, 24000..24025, 26000..26025, 28000..28025, 30000..30025].each do |range|
  range.each { |id| doomednum_info[id] = {-1, -1} }
end

log(2, "Reserved Doomednums loaded: #{doomednum_info.size} entries")

###############################################################################
# CREATE DIRECTORIES
###############################################################################

["./Processing", "./Source", "./Completed", "./IWADs", "./IWADs_Extracted", PK3_BUILD_DIR].each do |dir|
  Dir.mkdir_p(dir)
  log(3, "Ensured directory: #{dir}")
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
  pct = ((file_index + 1) * 100 / total_source)
  bar_width = 40
  filled = (pct * bar_width / 100).to_i
  bar = "#" * filled + "-" * (bar_width - filled)
  print "\r  [#{bar}] #{pct}% (#{file_index + 1}/#{total_source}) Extracting #{base.ljust(25)}"
  STDOUT.flush

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
# WIPE ALL DOOMEDNUMS AND REASSIGN TO MONSTERS
###############################################################################

log(2, "=== Wiping and Reassigning Doomednums ===")

# Step 1: Remove all doomednums from non-built-in actors in files
actordb.each do |actor|
  next if actor.built_in || actor.doomednum == -1

  file_text = safe_read(actor.file_path)
  lines = file_text.lines

  in_block_comment = false
  lines.each_with_index do |line, line_index|
    # [BUGFIX] Track /* ... */ block comments so actor definitions inside
    # them are not processed (lazerrifle bug — has a second actor def
    # inside a block comment that was getting its doomednum wiped).
    if line.includes?("/*")
      in_block_comment = true
    end
    if in_block_comment
      in_block_comment = false if line.includes?("*/")
      next
    end
    next unless line =~ /^\s*actor\s+/i
    # Skip ZScript field declarations like "actor dummy;" inside class bodies
    next if line.strip.rstrip(';').strip != line.strip

    words = line.split
    delete_idx = -1
    replace_with_comment = nil.as(String?)
    words.each_with_index do |word, word_index|
      break if word == "{" || word =~ /^\//
      # [BUGFIX] Handle tokens like "31378//add your own..." where a number
      # is glued to a // comment with no space. Split on "//" and check if
      # the left part is a valid integer (phantasm, phantasm2 bug).
      if word.includes?("//")
        parts = word.split("//", 2)
        if parts[0].to_i? != nil
          delete_idx = word_index
          # Preserve the comment portion so it's not lost
          replace_with_comment = "//" + parts[1]
        end
      elsif word.to_i? != nil
        delete_idx = word_index
      end
    end

    if delete_idx != -1
      if replace_with_comment
        # Replace the glued token with just the comment part
        words[delete_idx] = replace_with_comment.not_nil!
      else
        words.delete_at(delete_idx)
      end
      lines[line_index] = words.join(" ")
    end
  end

  File.write(actor.file_path, lines.join("\n"))
end

# Step 2: Assign fresh doomednums to all monsters
# [BUGFIX] V1 inserted doomednum AFTER the '{' or comment. Now inserts BEFORE.
doomednum_counter = 15000

actordb.each_with_index do |actor, actor_index|
  if !actor.built_in && (actor.ismonster || actor.monster)
    file_text = safe_read(actor.file_path)
    lines = file_text.lines

    in_block_comment = false
    lines.each_with_index do |line, line_index|
      # [BUGFIX] Skip lines inside /* ... */ block comments (lazerrifle bug)
      if line.includes?("/*")
        in_block_comment = true
      end
      if in_block_comment
        in_block_comment = false if line.includes?("*/")
        next
      end
      next unless line =~ /^\s*actor\s+/i
      # Skip ZScript field declarations like "actor dummy;" inside class bodies
      next if line.strip.rstrip(';').strip != line.strip

      words = line.lstrip.split
      next if words[1]?.try(&.downcase) != actor.name_with_case.downcase

      # Find where to insert: BEFORE the '{' or any comment
      insert_idx = words.size  # default: append at end
      words.each_with_index do |word, word_index|
        if word == "{" || word =~ /^\//
          insert_idx = word_index
          break
        end
      end

      # Find next available doomednum
      while doomednum_info.has_key?(doomednum_counter)
        doomednum_counter += 1
      end

      words.insert(insert_idx, doomednum_counter.to_s)
      doomednum_info[doomednum_counter] = {-1, -1}
      actordb[actor_index].doomednum = doomednum_counter

      lines[line_index] = words.join(" ")
      log(3, "Assigned doomednum #{doomednum_counter} to #{actor.name_with_case}")
    end

    File.write(actor.file_path, lines.join("\n"))
  elsif !actor.built_in && weapon_actor_set.includes?(actor.name.downcase)
    # Weapons get doomednums in the next pass
  else
    # Non-monster, non-weapon: clear doomednum
    actordb[actor_index].doomednum = -1
  end
end

# Step 3: Assign fresh doomednums to all weapons (continues from monster counter)
actordb.each_with_index do |actor, actor_index|
  next if actor.built_in
  next unless weapon_actor_set.includes?(actor.name.downcase)

  file_text = safe_read(actor.file_path)
  lines = file_text.lines

  in_block_comment = false
  lines.each_with_index do |line, line_index|
    # [BUGFIX] Skip lines inside /* ... */ block comments (lazerrifle bug)
    if line.includes?("/*")
      in_block_comment = true
    end
    if in_block_comment
      in_block_comment = false if line.includes?("*/")
      next
    end
    next unless line =~ /^\s*actor\s+/i
    # Skip ZScript field declarations like "actor dummy;" inside class bodies
    next if line.strip.rstrip(';').strip != line.strip

    words = line.lstrip.split
    next if words[1]?.try(&.downcase) != actor.name_with_case.downcase

    # Strip any existing doomednum from the line first
    # (weapons from mods may already have one baked into their DECORATE)
    # [BUGFIX] Also handle tokens like "31378//comment" where number is glued
    # to an inline comment (phantasm/phantasm2 bug).
    cleaned_words = [] of String
    words.each do |word|
      if word.includes?("//") && word !~ /^\//
        parts = word.split("//", 2)
        if parts[0].to_i? != nil
          # Number glued to comment — keep only the comment part
          cleaned_words << "//" + parts[1]
          next
        end
      end
      next if word != "{" && word !~ /^\// && word.to_i? != nil && word != words[0] && word != words[1]
      cleaned_words << word
    end
    words = cleaned_words

    # Find where to insert: BEFORE the '{' or any comment
    insert_idx = words.size
    words.each_with_index do |word, word_index|
      if word == "{" || word =~ /^\//
        insert_idx = word_index
        break
      end
    end

    # Find next available doomednum
    while doomednum_info.has_key?(doomednum_counter)
      doomednum_counter += 1
    end

    words.insert(insert_idx, doomednum_counter.to_s)
    doomednum_info[doomednum_counter] = {-1, -1}
    actordb[actor_index].doomednum = doomednum_counter

    lines[line_index] = words.join(" ")
    log(3, "Assigned weapon doomednum #{doomednum_counter} to #{actor.name_with_case}")
  end

  File.write(actor.file_path, lines.join("\n"))
end

log(2, "Doomednum assignment complete. Counter ended at: #{doomednum_counter}")

###############################################################################
# NOTE: Duplicate sprite removal was disabled because it runs before prefix
# conflict resolution and can delete sprites from a WAD's set, leaving
# incomplete rotation sets (e.g., SRG2E1-E8 reduced to just SRG2E2).
# The PK3 merge's "keeping existing" conflict logic handles true duplicates
# at copy time, which is safer since it operates on the final merged output.
###############################################################################

###############################################################################
# RESOLVE SPRITE PREFIX CONFLICTS
###############################################################################

log(2, "=== Resolving Sprite Prefix Conflicts ===")

# [FEATURE] Track all sprite prefix renames for a summary log at the end.
# Each entry: {wad_name, original_prefix, new_prefix, sprite_count, decorate_files_updated}
sprite_rename_log = Array(Tuple(String, String, String, Int32, Int32)).new

sprite_prefix = Hash(String, Array(Tuple(String, String))).new

sprite_files = (Dir.glob("./Processing/*/sprites/*") + Dir.glob("./Processing/*/sprites/**/*") + Dir.glob("./IWADs_Extracted/*/sprites/*") + Dir.glob("./IWADs_Extracted/*/sprites/**/*")).map { |p| normalize_path(p) }
sprite_files.each do |path|
  next if File.directory?(path)
  key = path.split("/").last.split(".").first[0..3].upcase
  sha = Digest::SHA256.new.file(path).hexfinal
  sprite_prefix[key] ||= Array(Tuple(String, String)).new
  sprite_prefix[key] << {path, sha}
end

def increment_prefix(original : String, existing : Hash(String, Array(Tuple(String, String)))) : String
  candidate = original.succ
  while existing.has_key?(candidate)
    candidate = candidate.succ
    if candidate =~ /^[0-9]/ || candidate.size > 4
      log(0, "Fatal: prefix '#{candidate}' invalid (starts with digit or >4 chars)")
      exit(1)
    end
  end
  candidate
end

sprite_prefix.each do |key, prefix_entries|
  # Check if multiple WADs use this prefix
  wad_names = prefix_entries.map { |p| p[0].split("/")[2] }.uniq
  next if wad_names.size <= 1

  # Never rename engine-reserved sprite prefixes
  reserved_prefixes = Set{"TNT1", "NULL", "----", "UNKN"}
  if reserved_prefixes.includes?(key)
    log(2, "Sprite prefix conflict: #{key} used by #{wad_names.join(", ")} — SKIPPED (engine-reserved)")
    next
  end

  log(2, "Sprite prefix conflict: #{key} used by #{wad_names.join(", ")}")

  # Count how many sprites each WAD contributes for this prefix
  wad_sprite_counts = Hash(String, Int32).new(0)
  prefix_entries.each do |p|
    wad_sprite_counts[p[0].split("/")[2]] += 1
  end

  wads_with_prefix = Hash(String, String).new

  # Prioritize: IWAD first, then WAD with most sprites for this prefix
  iwad_entry = prefix_entries.find { |p| p[0].split("/")[1] == "IWADs_Extracted" }
  if iwad_entry
    wads_with_prefix[iwad_entry[0].split("/")[2]] = key
  else
    # WAD with the most sprites for this prefix keeps the original name
    best_wad = wad_sprite_counts.max_by { |_, count| count }[0]
    wads_with_prefix[best_wad] = key
    log(2, "  Keeping prefix #{key} for #{best_wad} (#{wad_sprite_counts[best_wad]} sprites)")
  end

  prefix_counter = increment_prefix(key, sprite_prefix)

  # Assign new prefixes to conflicting wads
  prefix_entries.each do |pfix|
    wad_name = pfix[0].split("/")[2]
    unless wads_with_prefix.has_key?(wad_name)
      wads_with_prefix[wad_name] = prefix_counter
      sprite_prefix[prefix_counter] = Array(Tuple(String, String)).new
      sprite_prefix[prefix_counter] << pfix
      log(2, "  Renaming #{key} → #{prefix_counter} for #{wad_name} (#{wad_sprite_counts[wad_name]} sprites)")
      prefix_counter = increment_prefix(prefix_counter, sprite_prefix)
    end
  end

  # Rename sprite files and update DECORATE/ZSCRIPT references
  wads_with_prefix.each do |wad_name, new_prefix|
    next if new_prefix == key # Skip the WAD that keeps the original prefix

    list_of_sprites = Dir.glob("./Processing/#{wad_name}/sprites/#{key}*").map { |p| normalize_path(p) }
    renamed_sprite_count = 0
    list_of_sprites.each do |sprite|
      dir = File.dirname(sprite)
      old_name = File.basename(sprite)
      new_name = old_name.sub(/^#{key}/i, new_prefix)
      new_path = normalize_path(File.join(dir, new_name))
      log(3, "Renaming sprite: #{old_name} → #{new_name}")
      File.rename(sprite, new_path)
      renamed_sprite_count += 1
    end

    # Update DECORATE and ZSCRIPT references
    # Collect all script files for this WAD (DECORATE + ZSCRIPT + their includes)
    script_files = Array(String).new
    dec_main = "./Processing/#{wad_name}/defs/DECORATE.raw"
    zsc_main = "./Processing/#{wad_name}/defs/ZSCRIPT.raw"
    script_files += collect_decorate_files(dec_main) if File.exists?(dec_main)
    script_files += collect_decorate_files(zsc_main) if File.exists?(zsc_main)
    script_files.uniq!

    decorate_updates = 0
    script_files.each do |script_file|
      next unless File.exists?(script_file)
      text = File.read(script_file)
      # Replace ALL occurrences of the prefix in sprite reference contexts:
      # - State frame lines: "  SRG2 E 5 A_Chase"
      # - Could appear multiple times on a line or in goto targets
      # Use word-boundary-aware replacement to avoid partial matches
      # Replace sprite prefix references in state frame definitions.
      # Sprite refs in DECORATE/ZSCRIPT are always: PREFIX FRAMES DURATION [ACTION]
      # where PREFIX is exactly 4 chars, FRAMES is one or more letters A-Z, DURATION is a number.
      # Single frame: "PROJ A 5 A_Chase"
      # Multi-frame:  "SPRF BCD 1 bright"  (frames B, C, D all with duration 1)
      # We must NOT match inside words like "Projectile" or property names.
      # The pattern requires: start-of-line/whitespace, then PREFIX, then space(s),
      # then one or more frame letters followed by a space or digit.
      new_text = text.gsub(/(^|[ \t])#{key}([ \t]+[A-Z]+[ \t\d])/mi) do
        "#{$1}#{new_prefix}#{$2}"
      end
      if new_text != text
        File.write(script_file, new_text)
        decorate_updates += 1
        log(3, "  Updated sprite references in #{script_file}: #{key} → #{new_prefix}")
      end
    end

    # Track this rename for the summary log
    sprite_rename_log << {wad_name, key, new_prefix, renamed_sprite_count, decorate_updates}
  end
end

# ── Sprite Rename Summary Log ────────────────────────────────────────────────
# Writes a searchable table so you can trace any sprite prefix backward:
#   - Search for a new prefix (e.g., "GRNE") to find what it was renamed from
#   - Search for an original prefix (e.g., "GRND") to find all renames
#   - Search for a WAD name to find all its sprite renames
if sprite_rename_log.size > 0
  log(2, "")
  log(2, "=== Sprite Rename Summary (#{sprite_rename_log.size} renames) ===")
  log(2, "  #{"WAD".ljust(35)} #{"Original".ljust(8)} #{"New".ljust(8)} #{"Files".rjust(5)}  #{"DECORATE".rjust(8)}")
  log(2, "  #{"-" * 35} #{"-" * 8} #{"-" * 8} #{"-" * 5}  #{"-" * 8}")
  sprite_rename_log.sort_by { |entry| {entry[1], entry[0]} }.each do |wad_name, old_prefix, new_prefix, file_count, dec_count|
    log(2, "  #{wad_name.ljust(35)} #{old_prefix.ljust(8)} #{new_prefix.ljust(8)} #{file_count.to_s.rjust(5)}  #{dec_count.to_s.rjust(8)}")
  end
  log(2, "")
else
  log(2, "No sprite prefix renames were needed.")
end

# ── Full Sprite Prefix Inventory ─────────────────────────────────────────────
# Logs ALL sprite prefixes per WAD (post-rename), so any prefix can be traced
# back to its source WAD. Scans the Processing/ sprite files which reflect
# the final state after any prefix renames.
log(2, "")
log(2, "=== Sprite Prefix Inventory (per WAD, post-rename) ===")

wad_prefix_inventory = Hash(String, Hash(String, Int32)).new
sprite_inventory_files = Dir.glob("./Processing/*/sprites/**/*").map { |p| normalize_path(p) }
sprite_inventory_files.each do |path|
  next if File.directory?(path)
  wad = path.split("/")[2]
  prefix = File.basename(path).split(".").first[0..3].upcase
  wad_prefix_inventory[wad] ||= Hash(String, Int32).new(0)
  wad_prefix_inventory[wad][prefix] += 1
end

# Also build a reverse index: prefix → list of WADs (for searching by prefix)
prefix_to_wads = Hash(String, Array(String)).new
wad_prefix_inventory.each do |wad, prefixes|
  prefixes.each_key do |prefix|
    prefix_to_wads[prefix] ||= Array(String).new
    prefix_to_wads[prefix] << wad unless prefix_to_wads[prefix].includes?(wad)
  end
end

wad_prefix_inventory.keys.sort.each do |wad|
  prefixes = wad_prefix_inventory[wad]
  prefix_list = prefixes.keys.sort.map { |p| "#{p}(#{prefixes[p]})" }.join(", ")
  log(2, "  #{wad.ljust(35)} #{prefix_list}")
end

log(2, "")
log(2, "  Total: #{wad_prefix_inventory.size} WADs, #{prefix_to_wads.size} unique prefixes")
log(2, "")

###############################################################################
# RESOLVE SOUND LUMP CONFLICTS
###############################################################################
#
# Sound files (e.g., DSPOSIT1.raw) can exist in multiple WADs with different
# audio content. Unlike sprites (which use 4-char prefixes), sound lumps are
# referenced by their full lump name in SNDINFO. When two WADs ship the same
# sound filename with different content, we must:
#   1. Detect the conflict (same filename, different SHA256)
#   2. Rename the conflicting WAD's sound file (append WAD-specific suffix)
#   3. Rewrite that WAD's SNDINFO to reference the new filename
#
# IWAD sounds always keep their original names — they're the engine baseline.
# Among mod WADs, the first one processed keeps the original name.
###############################################################################

log(2, "=== Resolving Sound Lump Conflicts ===")

# Build inventory: sound_lump_name (uppercase, no ext) → [{path, wad_name, is_iwad}]
sound_inventory = Hash(String, Array(NamedTuple(path: String, wad_name: String, is_iwad: Bool))).new

# Scan IWAD sounds first
iwad_sound_files = Dir.glob("./IWADs_Extracted/*/sounds/*").map { |p| normalize_path(p) }
iwad_sound_files.each do |path|
  next if File.directory?(path)
  lump = File.basename(path, File.extname(path)).upcase
  wad_name = path.split("/")[2]
  sound_inventory[lump] ||= Array(NamedTuple(path: String, wad_name: String, is_iwad: Bool)).new
  sound_inventory[lump] << {path: path, wad_name: wad_name, is_iwad: true}
end

# Scan mod sounds (both sounds/ and music/ — jeutool often miscategorizes
# sound effects as "music" for WADs without proper S_START/S_END markers)
mod_sound_files = (Dir.glob("./Processing/*/sounds/*") + Dir.glob("./Processing/*/music/*")).map { |p| normalize_path(p) }
mod_sound_files.each do |path|
  next if File.directory?(path)
  lump = File.basename(path, File.extname(path)).upcase
  wad_name = path.split("/")[2]
  sound_inventory[lump] ||= Array(NamedTuple(path: String, wad_name: String, is_iwad: Bool)).new
  sound_inventory[lump] << {path: path, wad_name: wad_name, is_iwad: false}
end

log(2, "  Sound inventory: #{sound_inventory.size} unique lump names across #{iwad_sound_files.size + mod_sound_files.size} files")

# Track renames: wad_name → {old_lump_upper → new_lump_upper}
sound_renames = Hash(String, Hash(String, String)).new
sound_conflicts_total = 0
sound_renames_total = 0

# For generating unique renamed lump names, track all known lump names
all_sound_lumps = Set(String).new(sound_inventory.keys)

sound_inventory.each do |lump, entries|
  # Only care about lumps that appear in multiple WADs
  wad_names = entries.map { |e| e[:wad_name] }.uniq
  next if wad_names.size <= 1

  # Group by content (SHA256) to find true conflicts (not just duplicates)
  by_hash = Hash(String, Array(NamedTuple(path: String, wad_name: String, is_iwad: Bool))).new
  entries.each do |entry|
    # Use file size as quick pre-check
    sha = Digest::SHA256.new.file(entry[:path]).hexfinal
    by_hash[sha] ||= Array(NamedTuple(path: String, wad_name: String, is_iwad: Bool)).new
    by_hash[sha] << entry
  end

  # If all files have the same hash, they're identical — no conflict
  next if by_hash.size <= 1

  sound_conflicts_total += 1
  log(2, "  Sound conflict: #{lump} — #{wad_names.join(", ")} (#{by_hash.size} distinct versions)")

  # Decide who keeps the original name:
  #   1. IWAD always keeps original
  #   2. Otherwise, WAD with most sound files keeps original (arbitrary but stable)
  keeper_wad : String? = nil

  # Check if any IWAD has this lump
  iwad_entry = entries.find { |e| e[:is_iwad] }
  if iwad_entry
    keeper_wad = iwad_entry[:wad_name]
    log(2, "    IWAD '#{keeper_wad}' keeps original #{lump}")
  else
    # First mod WAD in the list keeps the original name (stable, deterministic)
    keeper_wad = entries.find { |e| !e[:is_iwad] }.try &.[:wad_name]
    keeper_wad ||= entries.first[:wad_name]
    log(2, "    '#{keeper_wad}' keeps original #{lump} (first mod WAD)")
  end

  # Rename conflicting WADs' sound files
  entries.each do |entry|
    next if entry[:wad_name] == keeper_wad
    next if entry[:is_iwad] # Never rename IWAD sounds

    # Check if this WAD has a SNDINFO — without one, renaming is pointless
    # because the WAD relies on lump replacement (engine maps DS* names directly).
    wad_has_sndinfo = [
      "./Processing/#{entry[:wad_name]}/defs/SNDINFO.raw",
      "./Processing/#{entry[:wad_name]}/defs/sndinfo.raw",
      "./Processing/#{entry[:wad_name]}/defs/SNDINFO.txt",
      "./Processing/#{entry[:wad_name]}/defs/sndinfo.txt",
      "./Processing/#{entry[:wad_name]}/defs/SNDINFO.lmp",
    ].any? { |p| File.exists?(normalize_path(p)) }

    # Note: WADs without SNDINFO will still be renamed. A synthetic SNDINFO
    # and DECORATE rewrite will be generated after this loop.
    unless wad_has_sndinfo
      log(2, "    #{entry[:wad_name]} has no SNDINFO — will generate synthetic mapping for #{lump}")
    end

    # Generate a unique new lump name.
    # Strategy: append a short WAD-derived suffix to keep it recognizable.
    # GZDoom lump names are typically 8 chars max for WAD compatibility,
    # but PK3 supports longer names. We'll use: LUMP_WADABBREV
    # First try a short abbreviation from the WAD name (first 4 alphanum chars)
    wad_abbrev = entry[:wad_name].gsub(/[^a-zA-Z0-9]/, "")[0..3].upcase
    candidate = "#{lump}_#{wad_abbrev}"

    # Ensure uniqueness
    suffix_counter = 0
    while all_sound_lumps.includes?(candidate)
      suffix_counter += 1
      candidate = "#{lump}_#{wad_abbrev}#{suffix_counter}"
    end
    all_sound_lumps << candidate

    # Record the rename
    sound_renames[entry[:wad_name]] ||= Hash(String, String).new
    sound_renames[entry[:wad_name]][lump] = candidate

    # Rename the actual file on disk
    old_path = entry[:path]
    ext = File.extname(old_path)
    new_path = normalize_path(File.join(File.dirname(old_path), "#{candidate}#{ext}"))
    log(2, "    Renaming: #{File.basename(old_path)} → #{File.basename(new_path)} (#{entry[:wad_name]})")
    File.rename(old_path, new_path)
    sound_renames_total += 1
  end
end

# Now rewrite SNDINFO files for WADs that had renames
sound_sndinfo_rewrites = 0
sound_renames.each do |wad_name, renames|
  next if renames.empty?

  # Find SNDINFO file(s) for this WAD
  sndinfo_candidates = [
    "./Processing/#{wad_name}/defs/SNDINFO.raw",
    "./Processing/#{wad_name}/defs/sndinfo.raw",
    "./Processing/#{wad_name}/defs/SNDINFO.txt",
    "./Processing/#{wad_name}/defs/sndinfo.txt",
    "./Processing/#{wad_name}/defs/SNDINFO.lmp",
  ].map { |p| normalize_path(p) }

  sndinfo_files = sndinfo_candidates.select { |p| File.exists?(p) }

  if sndinfo_files.empty?
    # No SNDINFO — this WAD will be handled by the synthetic SNDINFO generator below
    log(2, "  #{wad_name}: no SNDINFO found — deferring to synthetic generation")
    next
  end

  sndinfo_files.each do |sndinfo_path|
    text = safe_read(sndinfo_path)
    next if text.empty?

    new_text = text
    renames_applied = 0

    renames.each do |old_lump, new_lump|
      # SNDINFO has two contexts where lump names appear:
      #
      # 1. Sound definition lines:  logical_name LUMPNAME
      #    The lump is the SECOND token. We match it by requiring at least one
      #    non-whitespace token before it on the same line.
      #
      # 2. $random block contents:  $random logical { LUMP1 LUMP2 }
      #    Lumps appear inside braces.
      #
      # We handle both by replacing any case-insensitive whole-word match of
      # the old lump name that is preceded by whitespace, { or " (never at
      # the very start of a line, which is the logical name position).
      escaped = Regex.escape(old_lump)
      replaced = new_text.gsub(/([ \t{"])#{escaped}([ \t}\r\n".]|$)/mi) do |_match|
        "#{$1}#{new_lump.downcase}#{$2}"
      end
      if replaced != new_text
        renames_applied += 1
        log(3, "    SNDINFO #{File.basename(sndinfo_path)}: #{old_lump} → #{new_lump} in #{wad_name}")
        new_text = replaced
      end
    end

    if new_text != text
      File.write(sndinfo_path, new_text)
      sound_sndinfo_rewrites += 1
      log(2, "  Rewrote SNDINFO for #{wad_name}: #{renames_applied} lump reference(s) updated")
    else
      log(1, "  WARNING: SNDINFO for #{wad_name} had no matching lump references to update")
      log(1, "    Expected renames:")
      renames.each { |old_name, new_name| log(1, "      #{old_name} → #{new_name}") }
    end
  end
end

###############################################################################
# SYNTHETIC SNDINFO + DECORATE REWRITE FOR NO-SNDINFO WADS
###############################################################################
#
# WADs without SNDINFO rely on lump replacement: they ship e.g. DSPOSIT1.raw
# to override the IWAD sound. Their actors use GZDoom's built-in logical names
# (like "grunt/sight") which resolve through default SNDINFO to those lumps.
#
# When we renamed their lump (DSPOSIT1 → DSPOSIT1_ZOMB), we must:
#   1. Create a synthetic SNDINFO mapping new logical names to the renamed lumps
#   2. Rewrite the actor's DECORATE sound properties to use the new logical names
#
# We use GZDoom's default lump→logical reverse mapping to find which actor
# properties need updating.
###############################################################################

log(2, "=== Generating Synthetic SNDINFO for Lump-Replacement WADs ===")

# GZDoom default SNDINFO: lump (uppercase) → [{logical_name, is_random_member}]
# This maps Doom II engine lumps to their default logical sound names.
# Only includes monster/world sounds likely to be overridden by monster mods.
# Source: zdoom.git wadsrc/static/filter/game-doomchex/sndinfo.txt
DEFAULT_LUMP_TO_LOGICAL = Hash(String, Array(String)).new

# Build the reverse map from the default SNDINFO forward mappings.
# Format: { "logical_name" => "lump_name" }
DEFAULT_SNDINFO = {
  # Zombieman (grunt)
  "grunt/sight1" => "dsposit1", "grunt/sight2" => "dsposit2",
  "grunt/sight3" => "dsposit3", "grunt/active" => "dsposact",
  "grunt/pain" => "dspopain", "grunt/death1" => "dspodth1",
  "grunt/death2" => "dspodth2", "grunt/death3" => "dspodth3",
  "grunt/attack" => "dspistol",
  # Shotgun Guy
  "shotguy/sight1" => "dsposit1", "shotguy/sight2" => "dsposit2",
  "shotguy/sight3" => "dsposit3", "shotguy/active" => "dsposact",
  "shotguy/pain" => "dspopain", "shotguy/death1" => "dspodth1",
  "shotguy/death2" => "dspodth2", "shotguy/death3" => "dspodth3",
  "shotguy/attack" => "dsshotgn",
  # Chaingunner
  "chainguy/sight1" => "dsposit1", "chainguy/sight2" => "dsposit2",
  "chainguy/sight3" => "dsposit3", "chainguy/active" => "dsposact",
  "chainguy/pain" => "dspopain", "chainguy/death1" => "dspodth1",
  "chainguy/death2" => "dspodth2", "chainguy/death3" => "dspodth3",
  "chainguy/attack" => "dsshotgn",
  # Imp
  "imp/sight1" => "dsbgsit1", "imp/sight2" => "dsbgsit2",
  "imp/active" => "dsbgact", "imp/pain" => "dspopain",
  "imp/melee" => "dsclaw", "imp/death1" => "dsbgdth1",
  "imp/death2" => "dsbgdth2", "imp/attack" => "dsfirsht",
  "imp/shotx" => "dsfirxpl",
  # Demon / Spectre
  "demon/sight" => "dssgtsit", "demon/active" => "dsdmact",
  "demon/pain" => "dsdmpain", "demon/melee" => "dssgtatk",
  "demon/death" => "dssgtdth",
  "spectre/sight" => "dssgtsit", "spectre/active" => "dsdmact",
  "spectre/pain" => "dsdmpain", "spectre/melee" => "dssgtatk",
  "spectre/death" => "dssgtdth",
  # Cacodemon
  "caco/sight" => "dscacsit", "caco/active" => "dsdmact",
  "caco/pain" => "dsdmpain", "caco/death" => "dscacdth",
  "caco/attack" => "dsfirsht", "caco/shotx" => "dsfirxpl",
  # Baron of Hell
  "baron/sight" => "dsbrssit", "baron/active" => "dsdmact",
  "baron/pain" => "dsdmpain", "baron/melee" => "dsclaw",
  "baron/death" => "dsbrsdth", "baron/attack" => "dsfirsht",
  "baron/shotx" => "dsfirxpl",
  # Hell Knight
  "knight/sight" => "dskntsit", "knight/active" => "dsdmact",
  "knight/pain" => "dsdmpain", "knight/death" => "dskntdth",
  # Lost Soul
  "skull/active" => "dsdmact", "skull/pain" => "dsdmpain",
  "skull/melee" => "dssklatk", "skull/death" => "dsfirxpl",
  # Spider Mastermind
  "spider/sight" => "dsspisit", "spider/active" => "dsdmact",
  "spider/pain" => "dsdmpain", "spider/attack" => "dsshotgn",
  "spider/death" => "dsspidth", "spider/walk" => "dsmetal",
  # Arachnotron
  "baby/sight" => "dsbspsit", "baby/active" => "dsbspact",
  "baby/pain" => "dsdmpain", "baby/death" => "dsbspdth",
  "baby/walk" => "dsbspwlk", "baby/attack" => "dsplasma",
  "baby/shotx" => "dsfirxpl",
  # Cyberdemon
  "cyber/sight" => "dscybsit", "cyber/active" => "dsdmact",
  "cyber/pain" => "dsdmpain", "cyber/death" => "dscybdth",
  "cyber/hoof" => "dshoof",
  # Pain Elemental
  "pain/sight" => "dspesit", "pain/active" => "dsdmact",
  "pain/pain" => "dspepain", "pain/death" => "dspedth",
  # Revenant
  "skeleton/sight" => "dsskesit", "skeleton/active" => "dsskeact",
  "skeleton/pain" => "dspopain", "skeleton/melee" => "dsskepch",
  "skeleton/swing" => "dsskeswg", "skeleton/death" => "dsskedth",
  "skeleton/attack" => "dsskeatk", "skeleton/tracex" => "dsbarexp",
  # Mancubus
  "fatso/sight" => "dsmansit", "fatso/active" => "dsposact",
  "fatso/pain" => "dsmnpain", "fatso/raiseguns" => "dsmanatk",
  "fatso/death" => "dsmandth", "fatso/attack" => "dsfirsht",
  "fatso/shotx" => "dsfirxpl",
  # Arch-vile
  "vile/sight" => "dsvilsit", "vile/active" => "dsvilact",
  "vile/pain" => "dsvipain", "vile/death" => "dsvildth",
  "vile/raise" => "dsslop", "vile/start" => "dsvilatk",
  "vile/stop" => "dsbarexp", "vile/firestrt" => "dsflamst",
  "vile/firecrkl" => "dsflame",
  # Wolf SS
  "wolfss/sight" => "dssssit", "wolfss/active" => "dsposact",
  "wolfss/pain" => "dspopain", "wolfss/death" => "dsssdth",
  "wolfss/attack" => "dsshotgn",
  # Commander Keen
  "keen/pain" => "dskeenpn", "keen/death" => "dskeendt",
  # Icon of Sin
  "brain/sight" => "dsbossit", "brain/pain" => "dsbospn",
  "brain/death" => "dsbosdth", "brain/spit" => "dsbospit",
  "brain/cube" => "dsboscub", "brain/cubeboom" => "dsfirxpl",
  # World / misc
  "world/barrelx" => "dsbarexp", "misc/gibbed" => "dsslop",
}

# GZDoom default $random groupings: parent_logical → [child_logicals]
DEFAULT_RANDOM_SOUNDS = {
  "grunt/sight"    => ["grunt/sight1", "grunt/sight2", "grunt/sight3"],
  "grunt/death"    => ["grunt/death1", "grunt/death2", "grunt/death3"],
  "shotguy/sight"  => ["shotguy/sight1", "shotguy/sight2", "shotguy/sight3"],
  "shotguy/death"  => ["shotguy/death1", "shotguy/death2", "shotguy/death3"],
  "chainguy/sight" => ["chainguy/sight1", "chainguy/sight2", "chainguy/sight3"],
  "chainguy/death" => ["chainguy/death1", "chainguy/death2", "chainguy/death3"],
  "imp/sight"      => ["imp/sight1", "imp/sight2"],
  "imp/death"      => ["imp/death1", "imp/death2"],
}

# Build reverse map: lump_name (uppercase) → [logical_names]
DEFAULT_SNDINFO.each do |logical, lump|
  key = lump.upcase
  DEFAULT_LUMP_TO_LOGICAL[key] ||= Array(String).new
  DEFAULT_LUMP_TO_LOGICAL[key] << logical
end

# Also build a reverse map for $random: child_logical → parent_logical
random_child_to_parent = Hash(String, String).new
DEFAULT_RANDOM_SOUNDS.each do |parent, children|
  children.each { |child| random_child_to_parent[child] = parent }
end

# Map of DECORATE sound property names to Actor field accessors
SOUND_PROPERTY_MAP = {
  "seesound"    => :see_sound,
  "deathsound"  => :death_sound,
  "painsound"   => :pain_sound,
  "activesound" => :active_sound,
  "attacksound"  => :attack_sound,
  "meleesound"  => :melee_sound,
}

synthetic_sndinfo_count = 0
synthetic_decorate_rewrites = 0

sound_renames.each do |wad_name, renames|
  next if renames.empty?

  # Check if this WAD already has a SNDINFO (already handled above)
  has_existing_sndinfo = [
    "./Processing/#{wad_name}/defs/SNDINFO.raw",
    "./Processing/#{wad_name}/defs/sndinfo.raw",
    "./Processing/#{wad_name}/defs/SNDINFO.txt",
    "./Processing/#{wad_name}/defs/sndinfo.txt",
    "./Processing/#{wad_name}/defs/SNDINFO.lmp",
  ].any? { |p| File.exists?(normalize_path(p)) }

  next if has_existing_sndinfo # Already handled by the SNDINFO rewrite above

  log(2, "  Generating synthetic SNDINFO for #{wad_name} (#{renames.size} renamed lumps)")

  # Find actors belonging to this WAD
  wad_actors = actordb.select { |a| a.source_wad_folder == wad_name && !a.built_in }
  if wad_actors.empty?
    log(1, "  WARNING: #{wad_name} has renamed sounds but no actors in actordb!")
    log(1, "    Renamed lumps without actor references:")
    renames.each { |old_name, new_name| log(1, "      #{old_name} → #{new_name}") }
    next
  end

  log(3, "    Found #{wad_actors.size} actor(s) in #{wad_name}")

  # WAD-specific prefix for logical names to avoid collisions
  wad_prefix = "mm_" + wad_name.gsub(/[^a-zA-Z0-9]/, "").downcase

  # Build the synthetic SNDINFO content and collect DECORATE rewrites
  sndinfo_lines = Array(String).new
  sndinfo_lines << "// Synthetic SNDINFO — auto-generated by Monster Mash"
  sndinfo_lines << "// WAD: #{wad_name}"
  sndinfo_lines << "// Redirects renamed sound lumps to new logical names"
  sndinfo_lines << ""

  # Track: actor_file_path → [{old_property_value, new_property_value}]
  decorate_rewrites = Hash(String, Array(Tuple(String, String))).new

  renames.each do |old_lump, new_lump|
    # Find which default logical names map to this lump
    logical_names = DEFAULT_LUMP_TO_LOGICAL[old_lump]?

    # Also check if the actor uses the lump name directly as a sound name
    # (some mods do: SeeSound "DSPOSIT1")
    direct_lump_ref = old_lump.downcase

    # Check each actor's sound properties
    wad_actors.each do |actor|
      SOUND_PROPERTY_MAP.each do |prop_name, field_sym|
        # Get the actor's sound property value
        prop_value = case field_sym
                     when :see_sound    then actor.see_sound
                     when :death_sound  then actor.death_sound
                     when :pain_sound   then actor.pain_sound
                     when :active_sound then actor.active_sound
                     when :attack_sound then actor.attack_sound
                     when :melee_sound  then actor.melee_sound
                     else "UNDEFINED"
                     end

        next if prop_value == "UNDEFINED" || prop_value.empty?

        # Strip quotes if present
        clean_value = prop_value.gsub('"', "").strip.downcase

        # Check if this property references our conflicting lump, either:
        #   a) Directly: SeeSound "DSPOSIT1"
        #   b) Via a logical name that resolves to the lump
        #   c) Via a $random parent whose children resolve to the lump

        matches_lump = false
        matched_logical : String? = nil
        is_random_parent = false

        # Case (a): Direct lump reference
        if clean_value == direct_lump_ref
          matches_lump = true
          log(3, "      Actor '#{actor.name_with_case}' #{prop_name} directly references #{old_lump}")
        end

        # Case (b): Logical name that maps to this lump
        if !matches_lump && logical_names
          logical_names.each do |ln|
            if clean_value == ln.downcase
              matches_lump = true
              matched_logical = ln
              log(3, "      Actor '#{actor.name_with_case}' #{prop_name} uses logical '#{ln}' → #{old_lump}")
              break
            end
          end
        end

        # Case (c): $random parent whose children include a logical that maps to this lump
        if !matches_lump && logical_names
          DEFAULT_RANDOM_SOUNDS.each do |parent, children|
            if clean_value == parent.downcase
              # Check if any child resolves to our lump
              if children.any? { |child| DEFAULT_SNDINFO[child]?.try(&.upcase) == old_lump }
                matches_lump = true
                is_random_parent = true
                matched_logical = parent
                log(3, "      Actor '#{actor.name_with_case}' #{prop_name} uses $random '#{parent}' containing #{old_lump}")
                break
              end
            end
          end
        end

        next unless matches_lump

        # Generate new logical name for SNDINFO
        new_logical = "#{wad_prefix}/#{prop_name}_#{actor.name.downcase.gsub(/[^a-z0-9]/, "")}"

        if is_random_parent && matched_logical
          # The actor uses a $random parent. We need to:
          # 1. Create new logical names for each child that maps to a renamed lump
          # 2. Create the direct mappings for renamed children
          # 3. Create a new $random with the new children
          children = DEFAULT_RANDOM_SOUNDS[matched_logical]
          new_children = Array(String).new

          children.each_with_index do |child, idx|
            child_lump = DEFAULT_SNDINFO[child]?.try(&.upcase)
            new_child_logical = "#{new_logical}#{idx + 1}"

            if child_lump && renames.has_key?(child_lump)
              # This child's lump was renamed — point to the new lump
              sndinfo_lines << "#{new_child_logical} #{renames[child_lump].downcase}"
              log(3, "      SNDINFO: #{new_child_logical} #{renames[child_lump].downcase}")
            elsif child_lump
              # This child's lump was NOT renamed — point to the original
              sndinfo_lines << "#{new_child_logical} #{child_lump.downcase}"
              log(3, "      SNDINFO: #{new_child_logical} #{child_lump.downcase}")
            end
            new_children << new_child_logical
          end

          # Create the $random
          sndinfo_lines << "$random #{new_logical} { #{new_children.join(" ")} }"
          log(3, "      SNDINFO: $random #{new_logical} { #{new_children.join(" ")} }")
        else
          # Simple direct mapping — just point new logical name to renamed lump
          sndinfo_lines << "#{new_logical} #{new_lump.downcase}"
          log(3, "      SNDINFO: #{new_logical} #{new_lump.downcase}")
        end

        # Record the DECORATE rewrite needed
        old_prop_raw = prop_value.gsub('"', "").strip
        decorate_rewrites[actor.file_path] ||= Array(Tuple(String, String)).new
        decorate_rewrites[actor.file_path] << {old_prop_raw, new_logical}

        sndinfo_lines << ""
      end
    end
  end

  # Write the synthetic SNDINFO if we generated any mappings
  if sndinfo_lines.size > 4  # More than just the header comments
    sndinfo_path = normalize_path("./Processing/#{wad_name}/defs/SNDINFO.raw")
    Dir.mkdir_p(File.dirname(sndinfo_path))
    File.write(sndinfo_path, sndinfo_lines.join("\n") + "\n")
    synthetic_sndinfo_count += 1
    log(2, "    Wrote synthetic SNDINFO: #{sndinfo_path} (#{sndinfo_lines.size - 4} mapping lines)")
  else
    log(1, "  WARNING: No sound property references found in #{wad_name} actors for renamed lumps")
    log(1, "    This WAD's renamed sounds may not be audible in-game.")
    renames.each { |old_name, new_name| log(1, "      #{old_name} → #{new_name}") }
  end

  # Apply DECORATE rewrites
  decorate_rewrites.each do |file_path, rewrites|
    next unless File.exists?(file_path)
    text = safe_read(file_path)
    next if text.empty?

    new_text = text
    rewrites_applied = 0

    rewrites.each do |old_value, new_value|
      # Replace the sound property value in DECORATE.
      # Sound properties look like: SeeSound "grunt/sight"
      # or: SeeSound "DSPOSIT1"
      # We match the property name + quoted value, case-insensitively.
      escaped_old = Regex.escape(old_value)
      replaced = new_text.gsub(/((?:SeeSound|DeathSound|PainSound|ActiveSound|AttackSound|MeleeSound)\s+)"#{escaped_old}"/mi) do
        "#{$1}\"#{new_value}\""
      end
      if replaced != new_text
        rewrites_applied += 1
        log(3, "      DECORATE #{File.basename(file_path)}: \"#{old_value}\" → \"#{new_value}\"")
        new_text = replaced
      end
    end

    if new_text != text
      File.write(file_path, new_text)
      synthetic_decorate_rewrites += 1
      log(2, "    Rewrote DECORATE #{File.basename(file_path)}: #{rewrites_applied} sound property change(s)")
    end
  end
end

log(2, "=== Sound Conflict Resolution Complete ===")
log(2, "  #{sound_conflicts_total} conflicts detected")
log(2, "  #{sound_renames_total} sound files renamed")
log(2, "  #{sound_sndinfo_rewrites} SNDINFO files rewritten (existing)")
log(2, "  #{synthetic_sndinfo_count} synthetic SNDINFO files generated")
log(2, "  #{synthetic_decorate_rewrites} DECORATE files rewritten for sound properties")

###############################################################################
# MERGE ALL PROCESSED CONTENT INTO A SINGLE PK3
###############################################################################
#
# Instead of rebuilding individual WADs, we merge everything into one PK3:
#   1. Resource dirs (sprites/, sounds/, etc.) → flat-merged into PK3 dirs
#   2. DECORATE files → per-WAD subdirs under decorate/, master DECORATE #includes
#   3. Text lumps (SNDINFO, GLDEFS, etc.) → concatenated with source attribution
#   4. Credits → merged with per-source labeling
#   5. Unknown items → copied with warnings for manual review
#
# The output is ./Completed/monster_mash.pk3
###############################################################################

log(2, "=== Building Merged PK3 ===")

# Clean and create PK3 staging directory
if Dir.exists?(PK3_BUILD_DIR)
  FileUtils.rm_rf(PK3_BUILD_DIR)
end
Dir.mkdir_p(PK3_BUILD_DIR)
Dir.mkdir_p(File.join(PK3_BUILD_DIR, "mm_actors"))

# Tracking structures
text_lumps = Hash(String, Array(Tuple(String, String))).new     # lump_name → [{wad, content}]
credits_parts = Array(Tuple(String, String)).new                # [{wad, credit_text}]
conflict_log = Array(String).new                                 # resource file conflicts
unknown_dirs = Hash(String, Array(String)).new                   # dirname → [wad_names]
unknown_files = Hash(String, Array(String)).new                  # filename → [wad_names]
wad_decorate_main = Array(Tuple(String, String)).new            # [{wad, pk3_relative_path}]
wad_zscript_main = Array(Tuple(String, String)).new             # [{wad, pk3_relative_path}]
stats_total_files = 0
stats_total_conflicts = 0
stats_wads_processed = 0

# Process each WAD in Processing (skip IWADs — those come from the IWAD at runtime)
wad_directories = Dir.glob("./Processing/*/").map { |p| normalize_path(p) }.sort
total_wads = wad_directories.size

wad_directories.each_with_index do |wad_dir, wad_index|
  wad_name = File.basename(wad_dir)
  stats_wads_processed += 1

  # Progress bar
  pct = ((wad_index + 1) * 100 / total_wads)
  bar_width = 40
  filled = (pct * bar_width / 100).to_i
  bar = "#" * filled + "-" * (bar_width - filled)
  print "\r  [#{bar}] #{pct}% (#{wad_index + 1}/#{total_wads}) #{wad_name.ljust(30)}"
  puts ""  # Newline so warnings/log output don't collide with progress bar
  STDOUT.flush

  log(3, "── PK3 merge: #{wad_name} ──")

  # Identify this WAD's DECORATE files (main + includes)
  decorate_main = normalize_path(File.join(wad_dir, "defs", "DECORATE.raw"))
  zscript_main = normalize_path(File.join(wad_dir, "defs", "ZSCRIPT.raw"))
  decorate_file_set = Set(String).new
  if File.exists?(decorate_main)
    collect_decorate_files(decorate_main).each { |f| decorate_file_set << normalize_path(f) }
  end
  # Also collect ZSCRIPT includes
  if File.exists?(zscript_main)
    collect_decorate_files(zscript_main).each { |f| decorate_file_set << normalize_path(f) }
  end

  Dir.each_child(wad_dir) do |entry|
    entry_path = normalize_path(File.join(wad_dir, entry))
    entry_lower = entry.downcase

    if File.directory?(entry_path)
      #-----------------------------------------------------------------
      # DIRECTORY ENTRIES
      #-----------------------------------------------------------------
      case entry_lower
      when "defs"
        # The defs/ directory may contain DECORATE/ZSCRIPT files + other text lumps.
        # Actor definition files go to mm_actors/WadName/; everything else is a text lump.
        dec_dest = normalize_path(File.join(PK3_BUILD_DIR, "mm_actors", wad_name))
        Dir.mkdir_p(dec_dest)
        has_main_decorate = false
        has_main_zscript = false

        Dir.each_child(entry_path) do |def_file|
          def_path = normalize_path(File.join(entry_path, def_file))
          next if File.directory?(def_path) # skip subdirs in defs/ for now

          canonical = lump_name(def_file)

          if decorate_file_set.includes?(def_path)
            # This is a DECORATE/ZSCRIPT file (main or included) — copy to mm_actors/WadName/
            dest_file = normalize_path(File.join(dec_dest, def_file))
            FileUtils.cp(def_path, dest_file)
            log(3, "  DECORATE: #{def_file} → mm_actors/#{wad_name}/#{def_file}")

            if canonical == "decorate"
              has_main_decorate = true
              pk3_path = "mm_actors/#{wad_name}/#{def_file}"
              wad_decorate_main << {wad_name, pk3_path}
            elsif canonical == "zscript"
              has_main_zscript = true
              pk3_path = "mm_actors/#{wad_name}/#{def_file}"
              wad_zscript_main << {wad_name, pk3_path}
            end

          elsif DECORATE_LUMP_NAMES.includes?(canonical)
            # DECORATE/ZSCRIPT file not caught by include scan — still copy it
            dest_file = normalize_path(File.join(dec_dest, def_file))
            FileUtils.cp(def_path, dest_file)
            log(3, "  DECORATE (extra): #{def_file} → mm_actors/#{wad_name}/#{def_file}")

            if canonical == "decorate" && !has_main_decorate
              has_main_decorate = true
              pk3_path = "mm_actors/#{wad_name}/#{def_file}"
              wad_decorate_main << {wad_name, pk3_path}
            elsif canonical == "zscript" && !has_main_zscript
              has_main_zscript = true
              pk3_path = "mm_actors/#{wad_name}/#{def_file}"
              wad_zscript_main << {wad_name, pk3_path}
            end

          elsif TEXT_LUMP_NAMES.includes?(canonical)
            # Non-DECORATE text lump found in defs/ directory
            content = safe_read(def_path)
            unless content.empty?
              text_lumps[canonical] ||= Array(Tuple(String, String)).new
              text_lumps[canonical] << {wad_name, content}
              log(3, "  Text lump (in defs/): #{canonical} from #{wad_name}")
            end

          elsif canonical == "credits" || canonical == "credit"
            content = safe_read(def_path)
            credits_parts << {wad_name, content} unless content.empty?
            log(3, "  Credits (in defs/): #{wad_name}")

          elsif SKIP_LUMP_NAMES.includes?(canonical)
            log(3, "  Skipping engine lump in defs/: #{def_file}")

          else
            # Unknown file in defs/ — might be an included file we missed,
            # or a lump type we haven't catalogued yet.
            # Copy it alongside the DECORATE files just in case.
            dest_file = normalize_path(File.join(dec_dest, def_file))
            FileUtils.cp(def_path, dest_file)
            unknown_files["defs/#{def_file}"] ||= Array(String).new
            unknown_files["defs/#{def_file}"] << wad_name
            log(1, "  Unknown file in defs/: #{def_file} (#{wad_name}) — copied to mm_actors/#{wad_name}/")
          end
        end

      when "maps"
        # Skip map data — maps are generated by Obsidian
        log(3, "  Skipping maps/ directory")

      when .in?(RESOURCE_DIRS)
        # Known resource directory — flat-merge contents.
        # Redirect music/ → sounds/: jeutool categorizes many sound effect lumps
        # as "music" when they're not between S_START/S_END markers in the WAD.
        # GZDoom requires SNDINFO-referenced sounds to be in /sounds/, not /music/.
        # Monster/weapon mods don't ship actual music tracks, so this is safe.
        merge_dir = (entry_lower == "music") ? "sounds" : entry_lower
        dest_dir = normalize_path(File.join(PK3_BUILD_DIR, merge_dir))
        is_sprites = (entry_lower == "sprites")
        is_sounds = (merge_dir == "sounds")

        copied, conflicts = copy_resource_files(entry_path, dest_dir, wad_name, conflict_log, is_sprites, is_sounds)
        stats_total_files += copied
        stats_total_conflicts += conflicts
        log(3, "  Resources: #{entry_lower}/ — #{copied} files copied, #{conflicts} conflicts")

      else
        # Check if this directory name conflicts with DECORATE/ZSCRIPT master files
        # (e.g., a PK3 mod with a "zscript/" directory containing included .zs files).
        # On Windows, "zscript" dir and "ZSCRIPT" file collide due to case-insensitivity.
        # Redirect these into mm_actors/WadName/ so the master file path stays clear.
        if DECORATE_LUMP_NAMES.includes?(entry_lower)
          dest_dir = normalize_path(File.join(PK3_BUILD_DIR, "mm_actors", wad_name, entry))
          copied, conflicts = copy_resource_files(entry_path, dest_dir, wad_name, conflict_log)
          stats_total_files += copied
          stats_total_conflicts += conflicts
          log(2, "  ZSCRIPT/DECORATE subdir: #{entry}/ in #{wad_name} — redirected to mm_actors/#{wad_name}/#{entry}/ (#{copied} files)")
        else
          # Unknown directory — copy preserving original case (PK3 is case-sensitive)
          unknown_dirs[entry] ||= Array(String).new
          unknown_dirs[entry] << wad_name
          dest_dir = normalize_path(File.join(PK3_BUILD_DIR, entry))
          copied, conflicts = copy_resource_files(entry_path, dest_dir, wad_name, conflict_log)
          stats_total_files += copied
          stats_total_conflicts += conflicts
          log(1, "  UNKNOWN DIRECTORY: #{entry}/ in #{wad_name} — copied #{copied} files to #{entry}/")
        end
      end

    else
      #-----------------------------------------------------------------
      # FILE ENTRIES (root-level files in the WAD extraction)
      #-----------------------------------------------------------------
      canonical = lump_name(entry)

      if canonical == "credits" || canonical == "credit"
        content = safe_read(entry_path)
        credits_parts << {wad_name, content} unless content.empty?
        log(3, "  Credits: #{wad_name}")

      elsif DECORATE_LUMP_NAMES.includes?(canonical)
        # Root-level DECORATE/ZSCRIPT file (outside defs/) — unusual but possible
        dec_dest = normalize_path(File.join(PK3_BUILD_DIR, "mm_actors", wad_name))
        Dir.mkdir_p(dec_dest)
        dest_file = normalize_path(File.join(dec_dest, entry))
        FileUtils.cp(entry_path, dest_file)
        pk3_path = "mm_actors/#{wad_name}/#{entry}"
        if canonical == "zscript"
          unless wad_zscript_main.any? { |t| t[0] == wad_name }
            wad_zscript_main << {wad_name, pk3_path}
          end
          log(2, "  Root ZSCRIPT: #{entry} → mm_actors/#{wad_name}/")
        else
          unless wad_decorate_main.any? { |t| t[0] == wad_name }
            wad_decorate_main << {wad_name, pk3_path}
          end
          log(2, "  Root DECORATE: #{entry} → mm_actors/#{wad_name}/")
        end

      elsif TEXT_LUMP_NAMES.includes?(canonical)
        content = safe_read(entry_path)
        unless content.empty?
          text_lumps[canonical] ||= Array(Tuple(String, String)).new
          text_lumps[canonical] << {wad_name, content}
          log(3, "  Text lump: #{canonical} from #{wad_name}")
        end

      elsif SKIP_LUMP_NAMES.includes?(canonical)
        log(3, "  Skipping engine lump: #{entry}")

      else
        # Unknown root file — copy to PK3 root, log for review
        dest_path = normalize_path(File.join(PK3_BUILD_DIR, entry))
        unless File.exists?(dest_path)
          FileUtils.cp(entry_path, dest_path)
        else
          # Already exists — check for conflict
          src_sha = Digest::SHA256.new.file(entry_path).hexfinal
          dest_sha = Digest::SHA256.new.file(dest_path).hexfinal
          if src_sha != dest_sha
            conflict_log << "ROOT CONFLICT: '#{entry}' — #{wad_name} differs from existing"
            log(1, "  ROOT CONFLICT: #{entry} from #{wad_name} (keeping existing)")
          end
        end
        unknown_files[entry] ||= Array(String).new
        unknown_files[entry] << wad_name
        log(1, "  UNKNOWN ROOT FILE: #{entry} in #{wad_name}")
      end
    end
  end
end

###############################################################################
# CREATE MASTER DECORATE FILE
###############################################################################

puts "" # Clear progress bar line
log(2, "Creating master DECORATE file...")
log(2, "  #{wad_decorate_main.size} WADs with DECORATE files")

master_decorate = String.build do |io|
  io << "// ============================================================\n"
  io << "// Monster Mash — Master DECORATE\n"
  io << "// Auto-generated by Unwad V2\n"
  io << "// Total sources: #{wad_decorate_main.size}\n"
  io << "// ============================================================\n\n"

  wad_decorate_main.sort_by { |t| t[0].downcase }.each do |wad_name, pk3_path|
    io << "// Source: #{wad_name}\n"
    io << "#include \"#{pk3_path}\"\n\n"
  end
end

File.write(normalize_path(File.join(PK3_BUILD_DIR, "DECORATE")), master_decorate)
log(2, "Master DECORATE written with #{wad_decorate_main.size} includes.")

###############################################################################
# CREATE MASTER ZSCRIPT FILE (if any ZSCRIPT mods exist)
###############################################################################

if wad_zscript_main.size > 0
  log(2, "Creating master ZSCRIPT file...")
  log(2, "  #{wad_zscript_main.size} WADs with ZSCRIPT files")

  master_zscript = String.build do |io|
    io << "version \"4.2.0\"\n\n"
    io << "// ============================================================\n"
    io << "// Monster Mash — Master ZSCRIPT\n"
    io << "// Auto-generated by Unwad V2\n"
    io << "// Total sources: #{wad_zscript_main.size}\n"
    io << "// ============================================================\n\n"

    wad_zscript_main.sort_by { |t| t[0].downcase }.each do |wad_name, pk3_path|
      io << "// Source: #{wad_name}\n"
      io << "#include \"#{pk3_path}\"\n\n"
    end
  end

  File.write(normalize_path(File.join(PK3_BUILD_DIR, "ZSCRIPT")), master_zscript)
  log(2, "Master ZSCRIPT written with #{wad_zscript_main.size} includes.")
end

# Update #include paths INSIDE each WAD's DECORATE files.
# GZDoom resolves #include relative to the PK3 root, not relative to the file.
# So "#include SOMEACTOR" inside decorate/WadName/DECORATE.raw needs to become
# "#include decorate/WadName/SOMEACTOR.raw"

log(2, "Updating #include paths in DECORATE/ZSCRIPT files for PK3 structure...")
# Combine both DECORATE and ZSCRIPT sources for include rewriting
# Recursively process all script files in a directory: strip version directives
# and rewrite #include paths for PK3 structure.
def process_script_dir(dir : String, wad_name : String, pk3_build_dir : String)
  Dir.each_child(dir) do |filename|
    file_path = normalize_path(File.join(dir, filename))

    if File.directory?(file_path)
      process_script_dir(file_path, wad_name, pk3_build_dir)
      next
    end

    content = File.read(file_path)
    original_content = content

    # Strip 'version "x.y.z"' from ZSCRIPT files — only the master ZSCRIPT
    # should have a version directive. Duplicate version in #include'd files
    # causes a parse error.
    # Use line-by-line replacement for robustness with \r\n line endings.
    content = content.lines.map { |line|
      if line.strip.downcase.starts_with?("version ")
        "// version directive moved to master ZSCRIPT"
      else
        line
      end
    }.join("\n")

    # Match #include "FILENAME" and update path
    content = content.gsub(/^(\s*#include\s+")([^"]+)(")/mi) do |match|
      prefix = $1
      inc_file = $2
      suffix = $3

      if inc_file.includes?("/") || inc_file.includes?("\\")
        normalized_inc = normalize_path(inc_file)

        # Strip all leading "../" since those just go up from mm_actors/WadName/
        stripped = normalized_inc.gsub(/^(\.\.\/)+/, "")
        candidate_from_root = normalize_path(File.join(pk3_build_dir, stripped))
        candidate_in_actors = normalize_path(File.join(pk3_build_dir, "mm_actors", wad_name, stripped))

        if File.exists?(candidate_in_actors)
          new_path = "mm_actors/#{wad_name}/#{stripped}"
          log(3, "  Rewriting pathed include: #{inc_file} → #{new_path}")
          "#{prefix}#{new_path}#{suffix}"
        elsif File.exists?(candidate_from_root)
          log(3, "  Rewriting pathed include (from root): #{inc_file} → #{stripped}")
          "#{prefix}#{stripped}#{suffix}"
        else
          log(1, "  Cannot resolve include path: #{inc_file} in #{wad_name} (tried #{candidate_in_actors} and #{candidate_from_root})")
          match
        end
      else
        new_path = "mm_actors/#{wad_name}/#{inc_file}"
        unless new_path =~ /\.\w+$/
          new_path += ".raw"
        end
        new_path = new_path.upcase.sub("MM_ACTORS/", "mm_actors/")
        log(3, "  Rewriting include: #{inc_file} → #{new_path}")
        "#{prefix}#{new_path}#{suffix}"
      end
    end

    if content != original_content
      File.write(file_path, content)
      log(3, "  Updated includes in: mm_actors/#{wad_name}/#{filename}")
    end
  end
end

all_actor_mains = wad_decorate_main + wad_zscript_main
all_actor_mains.each do |wad_name, pk3_path|
  dec_dir = normalize_path(File.join(PK3_BUILD_DIR, "mm_actors", wad_name))
  next unless Dir.exists?(dec_dir)

  process_script_dir(dec_dir, wad_name, PK3_BUILD_DIR)
end

###############################################################################
# WRITE CONCATENATED TEXT LUMPS
###############################################################################

log(2, "Writing concatenated text lumps...")
log(2, "  #{text_lumps.size} distinct lump types found")

keyconf_was_processed = false

text_lumps.each do |canonical_name, entries|
  merged = String.build do |io|
    io << "// ============================================================\n"
    io << "// #{canonical_name.upcase} — Monster Mash (merged)\n"
    io << "// Auto-generated by Unwad V2\n"
    io << "// Sources: #{entries.size} WAD(s)\n"
    io << "// ============================================================\n\n"

    entries.each do |wad_name, content|
      io << "// ── Begin: #{wad_name} " << ("─" * [1, 60 - wad_name.size].max) << "\n"
      io << content.strip
      io << "\n"
      io << "// ── End: #{wad_name} " << ("─" * [1, 62 - wad_name.size].max) << "\n\n"
    end
  end

  # Write with the canonical lump name (uppercase, no extension — GZDoom convention)
  output_name = canonical_name.upcase

  # Post-process GLDEFS: normalize light definition tags for compatibility.
  # Some mods use non-standard casing (e.g., "Pointlight" instead of "PointLight")
  # which newer GZDoom accepts but older forks like UZDoom reject.
  if canonical_name == "gldefs"
    gldefs_fixes = 0
    brace_fixes = 0
    # UZDoom (and older GZDoom forks) require all-lowercase light tags.
    # Newer GZDoom accepts mixed case, but we normalize to lowercase for compatibility.
    light_tags = {
      "pointlight"    => "pointlight",
      "spotlight"     => "spotlight",
      "pulselight"    => "pulselight",
      "flickerlight"  => "flickerlight",
      "flickerlight2" => "flickerlight2",
      "sectorlight"   => "sectorlight",
    }

    # --- Pass 1: Fix unbalanced braces per WAD section ---
    # Each WAD's GLDEFS was concatenated between "Begin:" and "End:" markers.
    # If a WAD has a missing closing brace, it corrupts all subsequent sections.
    # We scan each section and append missing closing braces.
    sections = merged.split(/^(\/\/ ── Begin: .+)$/m)
    rebuilt = String.build do |io|
      i = 0
      while i < sections.size
        section = sections[i]
        # Check if this is a "Begin:" marker
        if section =~ /^\/\/ ── Begin: (.+)/
          wad_section_name = $1.strip.gsub(/─+$/, "").rstrip
          # The actual content is in the next segment (up to next Begin: or end)
          content_part = (i + 1 < sections.size) ? sections[i + 1] : ""
          # Count braces in this section
          open_braces = content_part.count('{')
          close_braces = content_part.count('}')
          if open_braces > close_braces
            missing = open_braces - close_braces
            brace_fixes += missing
            log(1, "  GLDEFS: #{wad_section_name} has #{missing} missing closing brace(s) — auto-fixing")
            io << section
            io << content_part.rstrip
            io << "\n"
            missing.times { io << "}\n" }
            io << "\n"
          else
            io << section << content_part
          end
          i += 2
        else
          io << section
          i += 1
        end
      end
    end
    merged = rebuilt if brace_fixes > 0

    # --- Pass 2: Normalize light definition tags to lowercase ---
    lines = merged.lines
    lines.each_with_index do |line, i|
      stripped = line.strip
      first_word = stripped.split(/\s+/, 2).first?.try(&.downcase) || ""
      if light_tags.has_key?(first_word) && stripped.split(/\s+/, 2).first != light_tags[first_word]
        old_word = stripped.split(/\s+/, 2).first.not_nil!
        lines[i] = line.sub(old_word, light_tags[first_word])
        gldefs_fixes += 1
      end
    end
    if gldefs_fixes > 0 || brace_fixes > 0
      merged = lines.join("\n") if gldefs_fixes > 0
      log(2, "  GLDEFS: normalized #{gldefs_fixes} light tags, fixed #{brace_fixes} missing braces")
    end
  end

  # Post-process KEYCONF: sanitize for merged PK3 compatibility.
  # Individual weapon mods use KEYCONF for their standalone weapon setup, but
  # when merged, these commands conflict:
  #   - setslot: clears the entire slot, breaking all other weapons in that slot
  #   - clearplayerclasses / addplayerclass: replaces the default player class
  #   - weaponsection: creates isolated weapon sections (not needed for addslotdefault)
  # We convert all setslot commands to addslotdefault (which safely adds weapons
  # to slots without clearing them), and strip destructive player class commands.
  # Standard Doom weapons already have default slot assignments, so we skip them.
  if canonical_name == "keyconf"
    keyconf_was_processed = true
    keyconf_fixes = 0
    standard_weapons = Set{
      "fist", "chainsaw", "pistol", "shotgun", "supershotgun",
      "chaingun", "rocketlauncher", "plasmarifle", "bfg9000",
    }

    new_lines = [] of String
    merged.each_line do |line|
      stripped = line.strip.downcase

      # Strip clearplayerclasses / addplayerclass — destructive in merged context
      if stripped.starts_with?("clearplayerclasses") || stripped.starts_with?("addplayerclass")
        keyconf_fixes += 1
        next
      end

      # Strip weaponsection — not needed when using addslotdefault only
      if stripped.starts_with?("weaponsection")
        keyconf_fixes += 1
        next
      end

      # Convert setslot to addslotdefault
      if stripped =~ /^setslot\s+(\d+)\s+(.+)/i
        slot = $1
        weapons_str = $2
        weapons = weapons_str.split(/\s+/)
        weapons.each do |weapon|
          next if standard_weapons.includes?(weapon.downcase)
          new_lines << "addslotdefault #{slot} #{weapon}"
          keyconf_fixes += 1
        end
        next  # Skip original setslot line
      end

      new_lines << line
    end

    merged = new_lines.join("\n")
    log(2, "  KEYCONF: sanitized #{keyconf_fixes} directive(s) (setslot→addslotdefault, stripped player classes)")

    # [BUGFIX] Ensure ALL weapons have a slot assignment in KEYCONF.
    # Weapons that lack both a KEYCONF entry and Weapon.SlotNumber in their
    # DECORATE (like the Axe) will be invisible in-game — no key to select them.
    # Collect weapons already assigned in KEYCONF, then generate addslotdefault
    # entries for any weapons in weapon_actor_set that are missing.
    weapons_in_keyconf = Set(String).new
    merged.each_line do |line|
      stripped = line.strip.downcase
      if stripped =~ /^addslotdefault\s+\d+\s+(\S+)/i
        weapons_in_keyconf << $1.downcase
      end
    end

    slot_additions = [] of String
    actordb.each do |actor|
      next if actor.built_in
      next unless weapon_actor_set.includes?(actor.name.downcase)
      next if weapons_in_keyconf.includes?(actor.name.downcase)

      # Determine the slot to assign
      slot = actor.weapon.slotnumber
      if slot == -1
        # No explicit slot — infer from weapon characteristics
        if actor.weapon.meleeweapon || actor.weapon.noalert
          slot = 1  # Melee weapons → slot 1 (fist/chainsaw)
        elsif actor.weapon.bfg
          slot = 7  # BFG-class → slot 7
        elsif actor.weapon.ammouse > 5
          slot = 6  # High ammo use → slot 6 (plasma class)
        elsif actor.weapon.ammouse > 1
          slot = 4  # Moderate ammo use → slot 4 (chaingun class)
        else
          slot = 5  # Default fallback → slot 5 (rocket class)
        end
      end

      slot_additions << "addslotdefault #{slot} #{actor.name_with_case}"
      log(3, "  KEYCONF auto-slot: #{actor.name_with_case} → slot #{slot}")
    end

    if slot_additions.size > 0
      merged += "\n\n// Auto-generated slot assignments for weapons missing KEYCONF entries\n"
      merged += slot_additions.join("\n")
      merged += "\n"
      log(2, "  KEYCONF: auto-assigned #{slot_additions.size} weapon(s) to slots")
    end
  end

  # Post-process SNDINFO: prefix bare lump names with their PK3 path.
  # In a WAD, SNDINFO lump references are bare names (e.g., "GUNCOCK_SING").
  # In a PK3, GZDoom needs the path relative to the PK3 root
  # (e.g., "sounds/GUNCOCK_SING" or "sounds/DoublePumpGun/DBPGFIRE").
  # Build an index of all files in sounds/ and rewrite lump references.
  if canonical_name == "sndinfo"
    # Build lookup: lowercase lump name (no ext) → PK3-relative path
    sounds_dir = normalize_path(File.join(PK3_BUILD_DIR, "sounds"))
    sound_path_index = Hash(String, String).new

    if Dir.exists?(sounds_dir)
      # Recursively index all sound files
      dirs_to_scan = [{"sounds", sounds_dir}]
      while !dirs_to_scan.empty?
        pk3_prefix, fs_dir = dirs_to_scan.pop
        Dir.each_child(fs_dir) do |child|
          child_fs = normalize_path(File.join(fs_dir, child))
          child_pk3 = "#{pk3_prefix}/#{child}"
          if File.directory?(child_fs)
            dirs_to_scan << {child_pk3, child_fs}
          else
            # Index by the bare filename (no extension), case-insensitive
            bare = File.basename(child, File.extname(child)).downcase
            # Also index with extension stripped (for .raw, .ogg, .wav etc.)
            sound_path_index[bare] = child_pk3
            # Index the full filename too (with extension) in case SNDINFO uses it
            sound_path_index[child.downcase] = child_pk3
          end
        end
      end
    end

    sndinfo_fixes = 0
    new_lines = [] of String
    merged.each_line do |line|
      stripped = line.strip

      # Skip comments and blank lines
      if stripped.empty? || stripped.starts_with?("//") || stripped.starts_with?("#")
        new_lines << line
        next
      end

      # Skip directives ($random, $limit, $alias, $volume, etc.)
      # [BUGFIX] $random entries contain logical sound names (aliases), NOT
      # raw lump file references. They must NOT be prefixed with sounds/.
      # e.g., "$random weapons/HandCannon { 92FS 92FT 92FU }" — 92FS etc.
      # are logical names defined elsewhere in SNDINFO, not file paths.
      # Same applies to $alias, $limit, $volume — all reference logical names.
      if stripped.starts_with?("$")
        new_lines << line
        next
      end

      # Sound definition line: logical_name LUMPNAME [optional args]
      # The lump name is the second whitespace-delimited token.
      # We must replace only the second token, not the first — they can be identical
      # (e.g., "MG60FR MG60FR" where logical name = lump name).
      tokens = stripped.split(/\s+/, 3)
      if tokens.size >= 2
        lump_ref = tokens[1]
        lookup = lump_ref.downcase
        # Don't prefix if it already has a path separator (already prefixed)
        if !lump_ref.includes?("/") && sound_path_index.has_key?(lookup)
          new_lump = sound_path_index[lookup]
          # Rebuild the line: keep everything up to and including the first token
          # and its trailing whitespace, then replace the lump reference.
          # Find where the second token starts in the stripped line
          first_token_end = stripped.index(tokens[0]).not_nil! + tokens[0].size
          gap_match = stripped[first_token_end..]
          gap_size = gap_match.size - gap_match.lstrip.size
          second_token_start = first_token_end + gap_size
          # Find the same position in the original (possibly indented) line
          leading_ws = line.size - line.lstrip.size
          rebuilt = line[0, leading_ws] + tokens[0] + stripped[first_token_end, gap_size] + new_lump
          if tokens.size >= 3
            # Preserve anything after the lump ref (comments, etc.)
            after_lump = stripped[(second_token_start + lump_ref.size)..]
            rebuilt += after_lump
          end
          new_lines << rebuilt
          sndinfo_fixes += 1
        else
          new_lines << line
        end
      else
        new_lines << line
      end
    end

    merged = new_lines.join("\n")
    log(2, "  SNDINFO: prefixed #{sndinfo_fixes} lump reference(s) with PK3 paths")

    # --- Audit & Fix: detect and rename SNDINFO lines that override vanilla/IWAD logical sound names ---
    # When a mod's SNDINFO redefines e.g. "Grunt/Death" or "Demon/pain", it overrides
    # the vanilla sound for ALL monsters using that name, not just the mod's actors.
    # Fix: collect the exact logical names each WAD defines that collide with vanilla,
    # then rename only those specific names (plus any sub-entries used in their $random
    # blocks) to WAD-specific names in both SNDINFO and DECORATE.

    # Build set of all protected vanilla logical names (lowercase)
    protected_logicals = Set(String).new
    DEFAULT_SNDINFO.each_key { |k| protected_logicals << k.downcase }
    DEFAULT_RANDOM_SOUNDS.each_key { |k| protected_logicals << k.downcase }

    # Pass 1: Scan to find which WADs define which protected logical names,
    # AND collect ALL logical names each WAD defines (so we can rename
    # sub-entries like Grunt/Death4 that belong to a protected $random group).
    current_wad = "(unknown)"
    # wad → set of protected logical names this WAD defines
    wad_protected_names = Hash(String, Set(String)).new
    # wad → all logical names defined (for finding $random children)
    wad_all_names = Hash(String, Set(String)).new

    merged.each_line do |line|
      stripped = line.strip
      if stripped =~ /^\/\/ ── Begin: (.+?)[\s─]*$/
        current_wad = $1.strip
        next
      end
      next if stripped.empty? || stripped.starts_with?("//") || stripped.starts_with?("#")

      logical_name = ""
      if stripped =~ /^\$random\s+(\S+)/i
        logical_name = $1
      elsif !stripped.starts_with?("$")
        tokens = stripped.split(/\s+/, 3)
        logical_name = tokens[0] if tokens.size >= 2
      end

      next if logical_name.empty?
      wad_all_names[current_wad] ||= Set(String).new
      wad_all_names[current_wad] << logical_name

      next unless logical_name.includes?("/")
      if protected_logicals.includes?(logical_name.downcase)
        wad_protected_names[current_wad] ||= Set(String).new
        wad_protected_names[current_wad] << logical_name.downcase
      end
    end

    # Now expand: for each WAD with protected names, also collect any $random
    # children and related sub-entries that share the same prefix AND are
    # defined in the WAD's SNDINFO section (e.g., Grunt/Death4 is a child of
    # the protected $random Grunt/Death).
    # We do this by scanning $random blocks for protected parent names and
    # adding their children to the rename set.
    current_wad = "(unknown)"
    wad_random_children = Hash(String, Set(String)).new  # wad → extra names to rename

    merged.each_line do |line|
      stripped = line.strip
      if stripped =~ /^\/\/ ── Begin: (.+?)[\s─]*$/
        current_wad = $1.strip
        next
      end
      next unless wad_protected_names.has_key?(current_wad)
      next unless stripped =~ /^\$random\s+(\S+)\s*\{([^}]+)\}/i
      parent = $1.downcase
      children_str = $2
      # If the parent is protected, add all children to the rename set
      if wad_protected_names[current_wad].includes?(parent)
        wad_random_children[current_wad] ||= Set(String).new
        children_str.split(/\s+/).each do |child|
          next if child.empty?
          wad_random_children[current_wad] << child.downcase
        end
      end
    end

    # Merge children into the protected set
    wad_random_children.each do |wad_name, children|
      children.each { |c| wad_protected_names[wad_name] << c }
    end

    # Also add any names that share a prefix with a protected name AND are
    # defined in the same WAD. E.g., if Grunt/Death is protected and the WAD
    # also defines Grunt/Death4, Grunt/Active1, etc., those should be renamed too
    # because the WAD is creating its own sound scheme under that prefix.
    wad_protected_names.each do |wad_name, protected_set|
      # Get the prefixes of protected names
      protected_prefixes_for_wad = Set(String).new
      protected_set.each do |name|
        if name.includes?("/")
          protected_prefixes_for_wad << name.split("/").first
        end
      end

      # Add any other names from this WAD that share those prefixes
      if wad_all_names.has_key?(wad_name)
        wad_all_names[wad_name].each do |name|
          next unless name.includes?("/")
          prefix = name.split("/").first.downcase
          if protected_prefixes_for_wad.includes?(prefix)
            protected_set << name.downcase
          end
        end
      end
    end

    if wad_protected_names.empty?
      log(2, "  SNDINFO IWAD audit: no vanilla sound overrides detected")
    else
      # Build WAD-specific name replacements.
      # Generate a short unique prefix from the WAD name: "mm_" + first 4 alphanum chars
      wad_rename_map = Hash(String, Hash(String, String)).new  # wad → {old_logical → new_logical}
      wad_protected_names.each do |wad_name, names|
        abbrev = wad_name.downcase.gsub(/[^a-z0-9]/, "")[0, 4]
        abbrev = "mod" if abbrev.empty?
        wad_rename_map[wad_name] = Hash(String, String).new
        names.each do |old_name|
          # Replace the prefix: "grunt/death1" → "mm_grun_grunt/death1"
          if old_name.includes?("/")
            prefix = old_name.split("/", 2).first
            suffix = old_name.split("/", 2).last
            new_name = "mm_#{abbrev}_#{prefix}/#{suffix}"
          else
            new_name = "mm_#{abbrev}_#{old_name}"
          end
          wad_rename_map[wad_name][old_name] = new_name
        end
      end

      # Log what we're about to fix
      total_renames = wad_rename_map.values.sum(&.size)
      log(1, "  SNDINFO IWAD fix: renaming #{total_renames} logical name(s) in #{wad_rename_map.size} WAD(s):")
      wad_rename_map.each do |wad_name, renames|
        log(1, "    WAD: #{wad_name} (#{renames.size} name(s)):")
        renames.each { |old_n, new_n| log(1, "      #{old_n} → #{new_n}") }
      end

      # Pass 2: Rewrite the merged SNDINFO — rename logical names in affected WAD sections.
      current_wad = "(unknown)"
      current_renames = nil.as(Hash(String, String)?)
      sndinfo_rename_count = 0
      fixed_lines = [] of String

      merged.each_line do |line|
        stripped = line.strip

        # Track current WAD section
        if stripped =~ /^\/\/ ── Begin: (.+?)[\s─]*$/
          current_wad = $1.strip
          current_renames = wad_rename_map[current_wad]?
          fixed_lines << line
          next
        end
        if stripped =~ /^\/\/ ── End:/
          current_renames = nil
          fixed_lines << line
          next
        end

        # If this WAD has no overrides, pass through unchanged
        if current_renames.nil? || current_renames.not_nil!.empty?
          fixed_lines << line
          next
        end

        renames = current_renames.not_nil!

        # Skip comments and blank lines
        if stripped.empty? || stripped.starts_with?("//") || stripped.starts_with?("#")
          fixed_lines << line
          next
        end

        new_line = line
        if stripped.starts_with?("$")
          # Directive line — rename all logical name references
          # Sort renames by length descending to avoid partial matches
          sorted_renames = renames.to_a.sort_by { |old_n, _| -old_n.size }
          sorted_renames.each do |old_name, new_name|
            escaped = Regex.escape(old_name)
            # Match the logical name as a whole token (preceded by whitespace/{ and followed by whitespace/})
            new_line = new_line.gsub(/(?<=[\s{])#{escaped}(?=[\s}])/mi, new_name)
            # Also match right after $random/$limit/etc directive keyword
            new_line = new_line.gsub(/(\$\w+\s+)#{escaped}(?=\s)/mi) { "#{$1}#{new_name}" }
          end
        else
          # Sound definition line: logical_name LUMPNAME
          # Only the first token (the logical name) needs renaming
          tokens = stripped.split(/\s+/, 2)
          if tokens.size >= 2
            logical = tokens[0].downcase
            if renames.has_key?(logical)
              new_line = line.sub(/#{Regex.escape(tokens[0])}/i, renames[logical])
            end
          end
        end

        if new_line != line
          sndinfo_rename_count += 1
        end
        fixed_lines << new_line
      end

      merged = fixed_lines.join("\n")
      log(2, "  SNDINFO: renamed #{sndinfo_rename_count} logical name(s) to WAD-specific namespaces")

      # Pass 3: Update DECORATE files for affected WADs to use the new logical names.
      decorate_rename_count = 0
      wad_rename_map.each do |wad_name, renames|
        actor_dir = normalize_path(File.join(PK3_BUILD_DIR, "mm_actors", wad_name))
        next unless Dir.exists?(actor_dir)

        # Find all DECORATE/ZSCRIPT files in this WAD's actor directory
        script_files = Dir.glob(File.join(actor_dir, "**", "*")).select { |f|
          File.file?(f) && (f.downcase.ends_with?(".raw") || f.downcase.ends_with?(".zs") ||
                            f.downcase.ends_with?(".dec") || f.downcase.ends_with?(".txt"))
        }

        # Sort renames by length descending to avoid partial matches
        sorted_renames = renames.to_a.sort_by { |old_n, _| -old_n.size }

        script_files.each do |file_path|
          text = safe_read(file_path)
          next if text.empty?

          new_text = text
          sorted_renames.each do |old_name, new_name|
            # In DECORATE, sound names appear in quotes:
            #   SeeSound "Grunt/See"
            #   A_PlaySound("skull/melee", CHAN_WEAPON)
            # Match the exact logical name inside quotes, case-insensitive
            escaped = Regex.escape(old_name)
            new_text = new_text.gsub(/(["'])#{escaped}(["',\s)"])/mi) { "#{$1}#{new_name}#{$2}" }
            # Also match at end of quoted string: "Grunt/See"
            new_text = new_text.gsub(/(["'])#{escaped}(["'])/mi) { "#{$1}#{new_name}#{$2}" }
          end

          if new_text != text
            File.write(file_path, new_text)
            log(2, "    DECORATE fix: #{File.basename(file_path)} in #{wad_name}")
            decorate_rename_count += 1
          end
        end
      end
      log(2, "  DECORATE: updated #{decorate_rename_count} file(s) with renamed sound logical names")
    end
  end

  lump_output_path = normalize_path(File.join(PK3_BUILD_DIR, output_name))
  # On Windows, a resource directory with the same name (case-insensitive) may
  # already exist (e.g., "textures/" dir vs "TEXTURES" lump). Add .lmp extension
  # to avoid the collision — GZDoom reads text lumps by name regardless of extension.
  if Dir.exists?(lump_output_path)
    lump_output_path = lump_output_path + ".lmp"
    log(1, "  #{output_name}: directory conflict — writing as #{output_name}.lmp")
  end
  File.write(lump_output_path, merged)
  log(2, "  #{output_name}: #{entries.size} source(s) merged")
end

# [BUGFIX] If no WAD contributed a KEYCONF, generate one from scratch so all
# weapons get slot assignments. Without this, weapons from WADs that rely on
# Weapon.SlotNumber (or have no slot at all) will be unselectable in-game.
unless keyconf_was_processed
  slot_additions = [] of String
  actordb.each do |actor|
    next if actor.built_in
    next unless weapon_actor_set.includes?(actor.name.downcase)

    slot = actor.weapon.slotnumber
    if slot == -1
      if actor.weapon.meleeweapon || actor.weapon.noalert
        slot = 1
      elsif actor.weapon.bfg
        slot = 7
      elsif actor.weapon.ammouse > 5
        slot = 6
      elsif actor.weapon.ammouse > 1
        slot = 4
      else
        slot = 5
      end
    end

    slot_additions << "addslotdefault #{slot} #{actor.name_with_case}"
  end

  if slot_additions.size > 0
    keyconf_content = String.build do |io|
      io << "// ============================================================\n"
      io << "// KEYCONF — Monster Mash (auto-generated)\n"
      io << "// No WADs contributed KEYCONF entries, so all weapon slot\n"
      io << "// assignments are auto-generated from DECORATE properties.\n"
      io << "// ============================================================\n\n"
      slot_additions.each { |line| io << line << "\n" }
    end
    keyconf_path = normalize_path(File.join(PK3_BUILD_DIR, "KEYCONF"))
    File.write(keyconf_path, keyconf_content)
    log(2, "  KEYCONF: generated from scratch with #{slot_additions.size} weapon slot assignment(s)")
  end
end

###############################################################################
# WRITE MERGED CREDITS
###############################################################################

log(2, "Writing merged CREDITS lump...")

credits_merged = String.build do |io|
  io << "================================================================\n"
  io << "  MONSTER MASH — Combined Credits\n"
  io << "  Auto-generated by Unwad V2\n"
  io << "================================================================\n\n"

  if credits_parts.empty?
    io << "No individual credit lumps were found in the source WADs.\n"
    io << "See individual mod pages for author attribution.\n\n"
  end

  # Always list all source WADs, even if they didn't have a CREDITS lump
  io << "── Source WADs (" << stats_wads_processed.to_s << ") "
  io << ("─" * 40) << "\n\n"

  wad_directories.each do |wad_dir|
    wad_name = File.basename(wad_dir)
    io << "  • #{wad_name}\n"
  end
  io << "\n"

  # Then include each WAD's original credits content
  credits_parts.each do |wad_name, content|
    io << "── Credits: #{wad_name} " << ("─" * [1, 50 - wad_name.size].max) << "\n\n"
    io << content.strip
    io << "\n\n"
  end

  io << "================================================================\n"
  io << "  End of Credits\n"
  io << "================================================================\n"
end

File.write(normalize_path(File.join(PK3_BUILD_DIR, "CREDITS")), credits_merged)
log(2, "CREDITS written (#{credits_parts.size} source credits found)")

###############################################################################
# LOG SUMMARY — Unknown & Conflict Report
###############################################################################

log(2, "")
log(2, "=== PK3 Merge Summary ===")
log(2, "  WADs processed:     #{stats_wads_processed}")
log(2, "  Resource files:     #{stats_total_files}")
log(2, "  File conflicts:     #{stats_total_conflicts}")
log(2, "  DECORATE sources:   #{wad_decorate_main.size}")
log(2, "  ZSCRIPT sources:    #{wad_zscript_main.size}")
log(2, "  Text lumps merged:  #{text_lumps.size}")
log(2, "  Credits found:      #{credits_parts.size}")

unless unknown_dirs.empty?
  log(1, "")
  log(1, "── Unknown Directories (copied but may need review) ──")
  unknown_dirs.each do |dirname, wads|
    log(1, "  #{dirname}/ — found in: #{wads.join(", ")}")
  end
end

unless unknown_files.empty?
  log(1, "")
  log(1, "── Unknown Files (copied but may need review) ──")
  unknown_files.each do |filename, wads|
    log(1, "  #{filename} — found in: #{wads.join(", ")}")
  end
end

unless conflict_log.empty?
  log(1, "")
  log(1, "── Resource Conflicts (#{conflict_log.size} total) ──")
  conflict_log.each { |msg| log(1, "  #{msg}") }
end

# Write the full report to a log file for offline review
report_path = "./Completed/pk3_merge_report.txt"
File.open(report_path, "w") do |f|
  f.puts "Monster Mash PK3 Merge Report"
  f.puts "Generated by Unwad V2"
  f.puts "=" * 60
  f.puts ""
  f.puts "WADs processed: #{stats_wads_processed}"
  f.puts "Resource files copied: #{stats_total_files}"
  f.puts "File conflicts: #{stats_total_conflicts}"
  f.puts "DECORATE sources: #{wad_decorate_main.size}"
  f.puts "ZSCRIPT sources: #{wad_zscript_main.size}"
  f.puts "Text lumps merged: #{text_lumps.size}"
  f.puts "Credits found: #{credits_parts.size}"
  f.puts ""

  f.puts "DECORATE include order:"
  wad_decorate_main.sort_by { |t| t[0].downcase }.each do |wad_name, pk3_path|
    f.puts "  #{wad_name} → #{pk3_path}"
  end
  f.puts ""

  unless wad_zscript_main.empty?
    f.puts "ZSCRIPT include order:"
    wad_zscript_main.sort_by { |t| t[0].downcase }.each do |wad_name, pk3_path|
      f.puts "  #{wad_name} → #{pk3_path}"
    end
    f.puts ""
  end

  unless text_lumps.empty?
    f.puts "Text lumps:"
    text_lumps.each do |name, entries|
      f.puts "  #{name.upcase}: #{entries.map { |e| e[0] }.join(", ")}"
    end
    f.puts ""
  end

  unless unknown_dirs.empty?
    f.puts "Unknown directories:"
    unknown_dirs.each do |dirname, wads|
      f.puts "  #{dirname}/ — #{wads.join(", ")}"
    end
    f.puts ""
  end

  unless unknown_files.empty?
    f.puts "Unknown files:"
    unknown_files.each do |filename, wads|
      f.puts "  #{filename} — #{wads.join(", ")}"
    end
    f.puts ""
  end

  unless conflict_log.empty?
    f.puts "Conflicts (#{conflict_log.size}):"
    conflict_log.each { |msg| f.puts "  #{msg}" }
    f.puts ""
  end
end
log(2, "Merge report written to: #{report_path}")

###############################################################################
# CREATE PK3 (ZIP the build directory)
###############################################################################

log(2, "Creating PK3 file: #{PK3_OUTPUT}")

begin
  File.open(PK3_OUTPUT, "w") do |file|
    Compress::Zip::Writer.open(file) do |zip|
      add_dir_to_zip(zip, PK3_BUILD_DIR, "")
    end
  end
  pk3_size = File.size(PK3_OUTPUT)
  size_mb = (pk3_size / (1024.0 * 1024.0)).round(2)
  log(2, "PK3 created successfully: #{PK3_OUTPUT} (#{size_mb} MB)")
rescue ex
  log(0, "Failed to create PK3: #{ex.message}")
  log(0, "The staged PK3 content is still available in #{PK3_BUILD_DIR}/ for manual zipping.")
  log(0, "You can manually create the PK3 with:")
  log(0, "  PowerShell: Compress-Archive -Path '#{PK3_BUILD_DIR}\\*' -DestinationPath '#{PK3_OUTPUT}'")
  log(0, "  Linux/Mac:  cd '#{PK3_BUILD_DIR}' && zip -r monster_mash.pk3 .")
end


generate_lua_module(actordb, weapon_actor_set)
