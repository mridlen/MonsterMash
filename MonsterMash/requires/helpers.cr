###############################################################################
# helpers.cr — Utility functions for Unwad / Monster Mash
###############################################################################

###############################################################################
# CONFIGURATION — Log level from CLI flags
###############################################################################

# ---------------------------------------------------------------------------
# Verbosity flags: -v = warnings, -vv = info, -vvv = debug
# Log levels: 0 = errors only, 1 = warnings, 2 = info, 3 = debug/verbose
# ---------------------------------------------------------------------------
module Config
  @@log_level : Int32 = if ARGV.includes?("-vvv")
                           3
                         elsif ARGV.includes?("-vv")
                           2
                         elsif ARGV.includes?("-v")
                           1
                         else
                           0  # default: errors only
                         end

  def self.log_level
    @@log_level
  end
end

LOG_FILE = File.open("unwad.log", "w")
LOG_FILE.puts "=== Unwad V4 Log Started: #{Time.local} ==="
LOG_FILE.flush

def log(level : Int32, msg : String)
  return if level > Config.log_level
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
# GENERAL UTILITIES
###############################################################################

# Check if a string is a valid integer
def numeric?(str : String) : Bool
  str.to_i? != nil
end

# Safely read a file, returning empty string on failure
def safe_read(path : String) : String
  norm = normalize_path(path)
  if File.exists?(norm)
    File.read(norm)
  else
    log(1, "File not found: #{norm}")
    ""
  end
end

# Normalize path separators to forward slashes (Windows compat)
def normalize_path(path : String) : String
  path.gsub("\\", "/")
end

# Safe directory move: copy then delete.
# FileUtils.mv fails on Windows when directories are locked (e.g., Dropbox sync)
# or when moving across volumes. cp_r + rm_rf is more reliable.
def safe_move_dir(src : String, dest : String)
  src_n = normalize_path(src)
  dest_n = normalize_path(dest)
  log(3, "Moving directory: #{src_n} → #{dest_n}")
  FileUtils.rm_rf(dest_n) if Dir.exists?(dest_n)
  FileUtils.cp_r(src_n, dest_n)
  FileUtils.rm_rf(src_n)
rescue ex
  log(0, "Failed to move '#{src_n}' → '#{dest_n}': #{ex.message}")
  raise ex
end

# Collect all DECORATE files for a wad (main + includes).
# Uses multi-strategy path resolution so it works with both jeutool-extracted
# WADs (files in defs/ with .raw extension) and PK3-extracted content
# (files at WAD root with various extensions like .dec, .txt, or no extension).
def collect_decorate_files(base_path : String) : Array(String)
  file_list = Array(String).new
  visited = Set(String).new
  collect_decorate_files_recursive(base_path, file_list, visited)
  file_list.uniq
end

# Recursively collect all DECORATE/ZSCRIPT files following #include directives.
# Tracks visited files to avoid infinite loops from circular includes.
def collect_decorate_files_recursive(base_path : String, file_list : Array(String), visited : Set(String))
  normalized = normalize_path(base_path)
  return if visited.includes?(normalized)
  visited << normalized

  file_list << normalized
  return unless File.exists?(normalized)

  base_dir = normalize_path(File.dirname(normalized))
  # For files in defs/, the WAD root is one level up
  wad_root = normalize_path(File.dirname(base_dir))

  File.each_line(normalized) do |line|
    if line.strip =~ /^#include\s+/i
      if md = line.match(/"([^"]+)"/)
        include_ref = md[1]

        # Try multiple resolution strategies (first match wins):
        # Include base_dir of the current file for nested includes
        current_dir = normalize_path(File.dirname(normalized))
        candidates = [
          File.join(current_dir, include_ref),                  # relative to current file
          File.join(current_dir, "#{include_ref.upcase}.raw"),  # relative + .RAW
          File.join(current_dir, include_ref.upcase),           # relative + uppercase
          File.join(base_dir, "#{include_ref.upcase}.raw"),     # defs/NAME.RAW (jeutool)
          File.join(base_dir, include_ref),                     # defs/path/as-is
          File.join(base_dir, include_ref.upcase),              # defs/NAME (no ext)
          File.join(wad_root, include_ref),                     # wad_root/path/as-is (PK3)
          File.join(wad_root, "#{include_ref.upcase}.raw"),     # wad_root/NAME.RAW
          File.join(wad_root, include_ref.upcase),              # wad_root/NAME
        ]

        found = candidates.find { |c| File.exists?(normalize_path(c)) }
        if found
          collect_decorate_files_recursive(normalize_path(found), file_list, visited)
        else
          log(1, "Include not resolved: \"#{include_ref}\" (from #{normalized})")
          log(3, "  Searched: #{candidates.map { |c| normalize_path(c) }.join(", ")}")
        end
      end
    end
  end
end

# Match balanced braces starting from a given position in text.
# Returns the substring from the opening '{' to the matching '}'.
def extract_balanced_braces(text : String, start_pos : Int32) : String?
  return nil if start_pos < 0 || start_pos >= text.size
  depth = 0
  i = start_pos
  while i < text.size
    if text[i] == '{'
      depth += 1
    elsif text[i] == '}'
      depth -= 1
      if depth == 0
        return text[start_pos..i]
      end
    end
    i += 1
  end
  nil
end

# Remove the states block from actor text using iterative brace matching.
# V1 used a recursive PCRE regex that doesn't work reliably in Crystal.
def remove_states_block(actor_text : String) : String
  result = actor_text
  # Find "states" keyword followed by "{"
  if md = result.match(/states\s*\{/mi)
    states_start = md.begin(0).not_nil!
    # Find the opening brace
    brace_start = result.index('{', states_start)
    if brace_start
      matched = extract_balanced_braces(result, brace_start)
      if matched
        # Remove "states" keyword + the entire braced block
        states_keyword_start = states_start
        states_end = brace_start + matched.size
        result = result[0...states_keyword_start] + result[states_end..]
      end
    end
  end
  result
end

# Extract the states block text (content between braces after "states")
def extract_states_text(actor_text : String, actor_name : String = "") : String?
  if md = actor_text.match(/states\s*\{/mi)
    states_start = md.begin(0).not_nil!
    brace_start = actor_text.index('{', states_start)
    if brace_start
      matched = extract_balanced_braces(actor_text, brace_start)
      if matched && matched.size > 2
        # Strip outer braces
        return matched[1..-2].strip
      else
        log(3, "  extract_states_text: brace match failed for #{actor_name} (matched=#{matched.nil? ? "nil" : matched.size.to_s} chars)")
      end
    else
      log(3, "  extract_states_text: no opening brace found after 'states' for #{actor_name}")
    end
  else
    log(3, "  extract_states_text: no 'states' keyword found for #{actor_name}")
    preview = actor_text[0, Math.min(300, actor_text.size)].gsub("\n", "\\n")
    log(3, "    actor_text preview: #{preview}")
  end
  nil
end

# Parse states text into a hash of state_label => state_content
def parse_states(states_text : String?, actor_name : String = "") : Hash(String, String)
  states = Hash(String, String).new
  return states if states_text.nil?

  parts = states_text.not_nil!.split(/^(\S+)\:/m)
  # First element is anything before the first label — discard
  parts.shift if parts.size > 0

  # Debug: log when no labels found in non-empty states text
  if parts.size < 2 && !states_text.not_nil!.strip.empty?
    preview = states_text.not_nil![0, Math.min(300, states_text.not_nil!.size)].gsub("\n", "\\n")
    log(3, "  parse_states: no labels found for #{actor_name} — preview: #{preview}")
  end

  (0...parts.size).step(2) do |i|
    break if i + 1 >= parts.size
    key = parts[i].strip.downcase
    value = parts[i + 1]
    states[key] = value
  end
  states
end

# Delete all contents of a directory without deleting the directory itself
def clear_directory(path : String)
  if Dir.exists?(path)
    Dir.each_child(path) do |child|
      child_path = File.join(path, child)
      if File.directory?(child_path)
        FileUtils.rm_rf(child_path)
      else
        File.delete(child_path)
      end
    end
  end
end

###############################################################################
# DEDUPLICATION HELPERS
# Shared patterns extracted from unwad.cr to eliminate code duplication.
###############################################################################

# Print a progress bar to STDOUT. Call with current index (0-based) and total.
def print_progress_bar(index : Int32, total : Int32, label : String)
  pct = ((index + 1) * 100 / total)
  bar_width = 40
  filled = (pct * bar_width / 100).to_i
  bar = "#" * filled + "-" * (bar_width - filled)
  print "\r  [#{bar}] #{pct}% (#{index + 1}/#{total}) #{label.ljust(30)}"
  STDOUT.flush
end

# Return the standard list of SNDINFO file path candidates for a WAD.
# Used during sound conflict resolution to find existing SNDINFO files.
# Includes dot-suffixed GZDoom variants (e.g. SNDINFO.MAGNUM.raw from SNDInfo.Magnum).
def sndinfo_candidates(wad_name : String) : Array(String)
  candidates = [
    "#{PROCESSING_DIR}/#{wad_name}/defs/SNDINFO.raw",
    "#{PROCESSING_DIR}/#{wad_name}/defs/sndinfo.raw",
    "#{PROCESSING_DIR}/#{wad_name}/defs/SNDINFO.txt",
    "#{PROCESSING_DIR}/#{wad_name}/defs/sndinfo.txt",
    "#{PROCESSING_DIR}/#{wad_name}/defs/SNDINFO.lmp",
  ]
  # Also find dot-suffixed SNDINFO variants (e.g. SNDINFO.MAGNUM.raw)
  defs_dir = "#{PROCESSING_DIR}/#{wad_name}/defs"
  if Dir.exists?(defs_dir)
    Dir.children(defs_dir).each do |f|
      canonical = lump_name(f)  # pk3_extract.cr
      base = lump_base_name(canonical)  # pk3_extract.cr
      if base == "sndinfo" && canonical != "sndinfo"
        candidates << "#{defs_dir}/#{f}"
      end
    end
  end
  candidates.map { |p| normalize_path(p) }
end

# Infer a weapon slot number from actor properties when no explicit slot is set.
# Returns the explicit slot if set, otherwise heuristic-based slot assignment.
def infer_weapon_slot(actor : Actor) : Int32
  slot = actor.weapon.slotnumber
  return slot unless slot == -1
  # Strip quotes from ammotype — DECORATE values may include embedded quotes
  ammo = actor.weapon.ammotype.downcase.gsub("\"", "")
  if actor.weapon.meleeweapon || actor.weapon.noalert
    1
  elsif actor.weapon.bfg
    7
  elsif ammo == "shell"
    3
  elsif ammo == "cell"
    6
  elsif ammo == "rocketammo"
    5
  elsif actor.weapon.ammouse > 5
    6
  elsif actor.weapon.ammouse > 1
    4
  else
    5
  end
end

# Estimate weapon damage per second from Fire state parsing.
# Uses calculate_weapon_damage() and calculate_fire_rate_with_fallthrough()
# from weapon_damage_calc.cr, with fallback to weapon_tier() estimates from lua_gen.cr.
# Includes fall-through state ticks when Fire has no flow control.
def estimate_weapon_dps(actor : Actor, actordb : Array(Actor)) : Float64
  calc_damage = calculate_weapon_damage(actor, actordb)  # weapon_damage_calc.cr
  damage = calc_damage > 0 ? calc_damage : weapon_tier(actor)[3]  # lua_gen.cr fallback

  # Calculate fire rate including fall-through states (Fire → next label → ...)
  calc_rate = calculate_fire_rate_with_fallthrough(actor)  # weapon_damage_calc.cr

  rate = calc_rate > 0 ? calc_rate : 0.9

  # Debug: log when falling back to defaults
  if calc_damage <= 0 || calc_rate <= 0
    state_keys = actor.states.keys.join(", ")
    fire_text = actor.states["fire"]? || ""
    fire_preview = fire_text.empty? ? "(empty)" : fire_text.lines.first(3).join(" | ")
    log(3, "  DPS fallback: #{actor.name_with_case} — dmg=#{calc_damage.round(1)} rate=#{calc_rate.round(2)} states=[#{state_keys}] fire=#{fire_preview}")
  end

  damage * rate
end

# Convert a DPS value to Weapon.SlotPriority (float, higher = better within slot).
# Uses logarithmic scaling to spread values evenly across the 0.0–1.0 range.
# Without log scaling, a single high-DPS weapon (e.g. BFG) causes all others
# to cluster near 0.
def dps_to_slot_priority(dps : Float64, min_dps : Float64, max_dps : Float64) : Float64
  return 0.0 if max_dps <= 0 || dps <= 0
  # Clamp min to at least 1.0 for log safety
  log_min = Math.log(Math.max(min_dps, 1.0))
  log_max = Math.log(Math.max(max_dps, 1.0))
  log_dps = Math.log(Math.max(dps, 1.0))
  return 0.5 if log_max == log_min  # All weapons have same DPS
  ((log_dps - log_min) / (log_max - log_min)).clamp(0.0, 1.0)
end

# Convert a DPS value to Weapon.SelectionOrder (int, lower = better globally).
# Uses logarithmic scaling to spread values evenly across the 100–3700 range.
# Maps inversely: highest DPS → 100, lowest DPS → 3700.
def dps_to_selection_order(dps : Float64, min_dps : Float64, max_dps : Float64) : Int32
  return 3700 if max_dps <= 0 || dps <= 0
  priority = dps_to_slot_priority(dps, min_dps, max_dps)
  (3700 - (priority * 3600)).round.to_i
end

# Iterate over actor definition lines in a DECORATE file, skipping block
# comments and ZScript field declarations. Yields (line, line_index) for
# each valid "actor ..." line found.
def each_actor_line(lines : Array(String), &block : (String, Int32) ->)
  in_block_comment = false
  lines.each_with_index do |line, line_index|
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
    block.call(line, line_index)
  end
end

# Find the opening '{' at or after line_index, then insert a //$Category
# comment on the line after it (unless one already exists). Modifies lines
# in place. Returns true if a category tag was inserted.
def inject_category_after_brace(lines : Array(String), line_index : Int32, category : String) : Bool
  brace_idx = line_index
  unless lines[brace_idx].includes?("{")
    brace_idx += 1
    while brace_idx < lines.size && !lines[brace_idx].includes?("{")
      brace_idx += 1
    end
  end
  if brace_idx < lines.size
    cat_idx = brace_idx + 1
    unless cat_idx < lines.size && lines[cat_idx] =~ /\/\/\$Category/i
      lines.insert(cat_idx, "  //$Category #{category}")
      return true
    end
  end
  false
end
