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

###############################################################################
# CONFIGURATION
###############################################################################

# Log levels: 0 = errors only, 1 = warnings, 2 = info, 3 = debug/verbose
LOG_LEVEL = 2

def log(level : Int32, msg : String)
  return if level > LOG_LEVEL
  prefix = case level
           when 0 then "[ERROR]"
           when 1 then "[WARN] "
           when 2 then "[INFO] "
           else        "[DEBUG]"
           end
  puts "#{prefix} #{msg}"
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
# HELPER METHODS
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
  file_list = [base_path]
  return file_list unless File.exists?(base_path)

  base_dir = normalize_path(File.dirname(base_path))
  # For files in defs/, the WAD root is one level up
  wad_root = normalize_path(File.dirname(base_dir))

  File.each_line(base_path) do |line|
    if line.strip =~ /^#include\s+/i
      if md = line.match(/"([^"]+)"/)
        include_ref = md[1]

        # Try multiple resolution strategies (first match wins):
        candidates = [
          File.join(base_dir, "#{include_ref.upcase}.raw"),   # defs/NAME.RAW (jeutool)
          File.join(base_dir, include_ref),                    # defs/path/as-is
          File.join(base_dir, include_ref.upcase),             # defs/NAME (no ext)
          File.join(wad_root, include_ref),                    # wad_root/path/as-is (PK3)
          File.join(wad_root, "#{include_ref.upcase}.raw"),    # wad_root/NAME.RAW
          File.join(wad_root, include_ref.upcase),             # wad_root/NAME
        ]

        found = candidates.find { |c| File.exists?(normalize_path(c)) }
        if found
          file_list << normalize_path(found)
        else
          log(1, "Include not resolved: \"#{include_ref}\" (from #{base_path})")
          log(3, "  Searched: #{candidates.map { |c| normalize_path(c) }.join(", ")}")
        end
      end
    end
  end
  file_list.uniq
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
def extract_states_text(actor_text : String) : String?
  if md = actor_text.match(/states\s*\{/mi)
    states_start = md.begin(0).not_nil!
    brace_start = actor_text.index('{', states_start)
    if brace_start
      matched = extract_balanced_braces(actor_text, brace_start)
      if matched && matched.size > 2
        # Strip outer braces
        return matched[1..-2].strip
      end
    end
  end
  nil
end

# Parse states text into a hash of state_label => state_content
def parse_states(states_text : String?) : Hash(String, String)
  states = Hash(String, String).new
  return states if states_text.nil?

  parts = states_text.not_nil!.split(/^(\S+)\:/m)
  # First element is anything before the first label — discard
  parts.shift if parts.size > 0

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
# PK3/ZIP SOURCE EXTRACTION
# Extracts PK3 (ZIP) files and normalizes their directory structure to match
# what jeutool produces for WADs, so the existing processing pipeline works
# unchanged. Root-level definition lumps are moved to defs/ with .raw extension.
###############################################################################

# List of file extensions (lowercase) to treat as definition/text lumps
# when found at the PK3 root level. These get moved to defs/ with .raw suffix.
PK3_ROOT_TEXT_EXTENSIONS = Set{".dec", ".txt", ".zs", ".zsc", ".acs", ""}

# Detect whether a root-level file in a PK3 is a definition/text lump
# that belongs in the defs/ directory.
def pk3_is_root_text_lump?(filename : String) : Bool
  canonical = lump_name(filename)
  return true if DECORATE_LUMP_NAMES.includes?(canonical)
  return true if TEXT_LUMP_NAMES.includes?(canonical)
  return true if canonical == "credits" || canonical == "credit"
  false
end

# Extract a PK3/ZIP file into dest_dir, normalizing structure to match
# jeutool WAD extraction format:
#   - Root-level text/def lumps → defs/LUMPNAME.raw
#   - Subdirectory content (sprites/, sounds/, etc.) → preserved as-is
#   - Other root files → left at root
#
# This allows the existing DECORATE processing pipeline (which globs for
# Processing/*/defs/DECORATE.raw) to find PK3-sourced DECORATE files.
def extract_pk3(pk3_path : String, dest_dir : String)
  pk3_name = File.basename(pk3_path)
  log(2, "Extracting PK3: #{pk3_name} → #{dest_dir}")
  Dir.mkdir_p(dest_dir)
  defs_dir = normalize_path(File.join(dest_dir, "defs"))
  Dir.mkdir_p(defs_dir)

  files_extracted = 0
  root_lumps_moved = 0
  dirs_created = Set(String).new

  begin
    File.open(pk3_path) do |file|
      Compress::Zip::Reader.open(file) do |zip|
        zip.each_entry do |entry|
          next if entry.dir?

          entry_name = normalize_path(entry.filename)
          # Skip macOS resource fork junk
          next if entry_name.includes?("__MACOSX") || entry_name.starts_with?("._")

          if entry_name.includes?("/")
            # ── File is inside a subdirectory ─────────────────────────
            # Preserve the PK3's internal directory structure as-is.
            # Most PK3 dirs (sprites/, sounds/, etc.) map 1:1 to what we need.
            dest_path = normalize_path(File.join(dest_dir, entry_name))
            dir = File.dirname(dest_path)
            unless dirs_created.includes?(dir)
              Dir.mkdir_p(dir)
              dirs_created << dir
            end
          else
            # ── Root-level file ───────────────────────────────────────
            if pk3_is_root_text_lump?(entry_name)
              # Move definition lumps to defs/ with .raw extension
              raw_name = lump_name(entry_name).upcase + ".raw"
              dest_path = normalize_path(File.join(defs_dir, raw_name))
              root_lumps_moved += 1
              log(3, "  Root lump → defs/: #{entry_name} → defs/#{raw_name}")
            else
              # Keep other root files in place
              dest_path = normalize_path(File.join(dest_dir, entry_name))
              log(3, "  Root file (kept): #{entry_name}")
            end
          end

          # Write the file
          File.open(dest_path, "wb") do |outfile|
            IO.copy(entry.io, outfile)
          end
          files_extracted += 1
        end
      end
    end
  rescue ex
    log(0, "Failed to extract PK3 '#{pk3_name}': #{ex.message}")
    log(0, "  This file will be skipped. Check if it's a valid ZIP/PK3.")
    return
  end

  # If a PK3 had an `actors/` directory with DECORATE-like files but
  # no root DECORATE file, create a synthetic one that #includes everything.
  decorate_path = normalize_path(File.join(defs_dir, "DECORATE.raw"))
  actors_dir = normalize_path(File.join(dest_dir, "actors"))

  if !File.exists?(decorate_path) && Dir.exists?(actors_dir)
    log(2, "  No DECORATE found; generating synthetic DECORATE from actors/ directory")
    actor_files = Dir.glob("#{actors_dir}/**/*")
      .select { |f| File.file?(f) }
      .map { |f| normalize_path(f).sub(dest_dir + "/", "") }
      .sort

    unless actor_files.empty?
      synthetic = String.build do |io|
        io << "// Synthetic DECORATE — auto-generated from PK3 actors/ directory\n"
        io << "// Source: #{pk3_name}\n\n"
        actor_files.each do |af|
          io << "#include \"#{af}\"\n"
        end
      end
      File.write(decorate_path, synthetic)
      log(2, "  Created synthetic DECORATE with #{actor_files.size} includes")
    end
  end

  # If DECORATE/ZSCRIPT exists and references files via include that are in the WAD root
  # (not in defs/), update the include paths to be relative from defs/
  [decorate_path, normalize_path(File.join(defs_dir, "ZSCRIPT.raw"))].each do |script_path|
    next unless File.exists?(script_path)
    content = File.read(script_path)
    original = content
    content = content.gsub(/^(\s*#include\s+")([^"]+)(")/mi) do
      prefix_match = $1
      inc_file = $2
      suffix_match = $3

      # If the include references a file that exists at the WAD root but not in defs/,
      # prepend ../ so it resolves correctly from defs/
      inc_from_defs = normalize_path(File.join(defs_dir, inc_file))
      inc_from_root = normalize_path(File.join(dest_dir, inc_file))

      if !File.exists?(inc_from_defs) && File.exists?(inc_from_root)
        log(3, "  Rewriting include: \"#{inc_file}\" → \"../#{inc_file}\"")
        "#{prefix_match}../#{inc_file}#{suffix_match}"
      else
        "#{prefix_match}#{inc_file}#{suffix_match}"
      end
    end

    if content != original
      File.write(script_path, content)
      log(2, "  Updated #{(content.scan(/#include/).size)} include paths for defs/ relocation")
    end
  end

  log(2, "  PK3 extracted: #{files_extracted} files, #{root_lumps_moved} root lumps → defs/")
end

PK3_BUILD_DIR = "./PK3_Build"
PK3_OUTPUT    = "./Completed/monster_mash.pk3"

# Known resource directories — contents get copied flat into the PK3.
# These hold binary files (sprites, sounds, etc.) identified by filename.
RESOURCE_DIRS = Set{
  "sprites", "sounds", "graphics", "patches", "flats",
  "textures", "hires", "acs", "models", "brightmaps",
  "colormaps", "voxels", "music", "filter", "materials",
  "skins", "voices",
  # jeutool puts uncategorized lumps here — copy them as generic resources
  "unknown",
}

# Known text lumps — these are concatenated across WADs with source attribution.
# Compared case-insensitively, with .raw/.txt/.lmp extensions stripped.
TEXT_LUMP_NAMES = Set{
  "sndinfo", "gldefs", "lockdefs", "animdefs", "decaldef",
  "sbarinfo", "menudef", "cvarinfo", "terrain", "voxeldef",
  "modeldef", "keyconf", "textures", "gameinfo", "zmapinfo",
  "mapinfo", "fontdefs", "reverbs", "althudcf", "x11r6rgb",
  "textcolo", "textcolors", "dehacked", "loadacs", "s_skin",
  "skininfo", "dialogue", "doomdefs", "hticdefs", "hexndefs",
  "strifedefs", "language", "sndseq", "teaminfo", "in_acs",
  # Translation lumps
  "trnslate",
  # ACS-related lumps (compiled ACS libraries loaded by LOADACS)
  "bloadacs",
}

# Binary/metadata lumps to skip — these come from the IWAD, engine, or jeutool.
SKIP_LUMP_NAMES = Set{
  "playpal", "colormap", "endoom", "dmxgus", "dmxgusc",
  "pnames", "texture1", "texture2",
  # jeutool extraction metadata — present in every extracted WAD
  "base-pal", "config", "info", "updates",
  # Documentation / old versions — not needed at runtime
  "readme", "document", "notes", "original", "oldcode",
  "oldmapin", "oldzscri",
}

# Lump names that are DECORATE-like (handled separately via master #include)
DECORATE_LUMP_NAMES = Set{
  "decorate", "zscript",
}

# Strip common lump file extensions to get the canonical lump name
def lump_name(filename : String) : String
  filename
    .gsub(/\.(raw|txt|lmp|dec|zs|acs|cfg)$/i, "")
    .downcase
    .strip
end

# Copy all files from src_dir into dest_dir (flat merge).
# Logs conflicts when a file already exists with different content.
# Returns count of files copied and conflicts detected.
def copy_resource_files(src_dir : String, dest_dir : String, wad_name : String,
                        conflict_log : Array(String),
                        is_sprites_dir : Bool = false) : {Int32, Int32}
  copied = 0
  conflicts = 0
  Dir.mkdir_p(dest_dir)

  Dir.each_child(src_dir) do |filename|
    src_path = normalize_path(File.join(src_dir, filename))

    # For sprites, strip .raw extension — WAD lumps have no extensions and
    # .raw breaks GZDoom's parsing of dual-rotation names (e.g., ISHMA1A5)
    dest_filename = filename
    if is_sprites_dir && File.extname(filename).downcase == ".raw"
      dest_filename = File.basename(filename, File.extname(filename))
    end
    dest_path = normalize_path(File.join(dest_dir, dest_filename))

    if File.directory?(src_path)
      # Recurse into subdirectories (e.g., filter/doom.id.doom2/)
      sub_copied, sub_conflicts = copy_resource_files(
        src_path,
        normalize_path(File.join(dest_dir, filename)),
        wad_name, conflict_log, is_sprites_dir
      )
      copied += sub_copied
      conflicts += sub_conflicts
      next
    end

    # Filter invalid sprites — jeutool sometimes creates 0-byte placeholder files
    if is_sprites_dir
      file_size = File.size(src_path)
      basename = File.basename(dest_filename, File.extname(dest_filename))
      # Skip zero-byte files (jeutool placeholders, not real image data)
      if file_size == 0
        log(3, "  Skipping 0-byte sprite placeholder: #{filename} in #{wad_name}")
        next
      end
      # Skip names that are too short to be valid sprites (need 4-char prefix + frame)
      # but only if they're also small — legitimate short-named lumps exist
      if basename.size < 5 && file_size < 64
        log(3, "  Skipping invalid sprite: #{filename} in #{wad_name} (name=#{basename.size}chars, size=#{file_size}bytes)")
        next
      end
    end

    if File.exists?(dest_path)
      # File already exists — check if identical
      src_sha = Digest::SHA256.new.file(src_path).hexfinal
      dest_sha = Digest::SHA256.new.file(dest_path).hexfinal
      if src_sha != dest_sha
        conflicts += 1
        msg = "CONFLICT: '#{dest_filename}' in #{dest_dir.sub(PK3_BUILD_DIR, "")} — " \
              "#{wad_name} differs from existing (keeping existing)"
        conflict_log << msg
        log(1, msg)
      else
        log(3, "  Skipping identical file: #{dest_filename}")
      end
    else
      FileUtils.cp(src_path, dest_path)
      copied += 1
    end
  end

  {copied, conflicts}
end

# Recursively add all files in a directory to a zip writer.
def add_dir_to_zip(zip : Compress::Zip::Writer, base_path : String, zip_prefix : String)
  Dir.each_child(base_path) do |entry|
    full_path = normalize_path(File.join(base_path, entry))
    zip_path = zip_prefix.empty? ? entry : "#{zip_prefix}/#{entry}"

    if File.directory?(full_path)
      add_dir_to_zip(zip, full_path, zip_path)
    else
      zip.add(zip_path) do |entry_io|
        File.open(full_path, "r") do |src|
          IO.copy(src, entry_io)
        end
      end
    end
  end
end

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
    log(3, "Extracting WAD: #{file_path}")
    system "./#{jeutoolexe} extract \"#{file_path}\" -r"

  elsif pk3_extensions.includes?(ext)
    dest = normalize_path("./Source/#{base}")
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
    system "./#{jeutoolexe} extract \"#{file_path}\" -r"

  elsif pk3_extensions.includes?(ext)
    dest = normalize_path("./IWADs/#{base}")
    log(2, "Extracting IWAD PK3: #{file_path}")
    extract_pk3(file_path, dest)

  else
    log(1, "Skipping unknown file type in IWADs/: #{file_name} (#{ext})")
  end
end

log(2, "Extraction complete.")

###############################################################################
# MOVE EXTRACTED DIRECTORIES
###############################################################################

log(2, "Moving extracted directories to Processing...")

Dir.glob("./Source/*/").each do |path|
  path = normalize_path(path)
  dest_path = File.join("./Processing/", File.basename(path))
  safe_move_dir(path, dest_path)
end

Dir.glob("./IWADs/*/").each do |path|
  path = normalize_path(path)
  dest_path = File.join("./IWADs_Extracted/", File.basename(path))
  safe_move_dir(path, dest_path)
end

log(2, "Move completed.")

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

# Sets a boolean flag on an actor by name. Returns true if the flag was recognized.
def set_actor_flag(actor : Actor, flag_name : String, value : Bool) : Bool
  # Actor-level flags (direct properties)
  case flag_name
  when "interpolateangles"    then actor.interpolateangles = value
  when "flatsprite"           then actor.flatsprite = value
  when "rollsprite"           then actor.rollsprite = value
  when "wallsprite"           then actor.wallsprite = value
  when "rollcenter"           then actor.rollcenter = value
  when "spriteangle"          then actor.spriteangle = value
  when "spriteflip"           then actor.spriteflip = value
  when "xflip"                then actor.xflip = value
  when "yflip"                then actor.yflip = value
  when "maskrotation"         then actor.maskrotation = value
  when "absmaskangle"         then actor.absmaskangle = value
  when "absmaskpitch"         then actor.absmaskpitch = value
  when "dontinterpolate"      then actor.dontinterpolate = value
  when "zdoomtrans"           then actor.zdoomtrans = value
  when "absviewangles"        then actor.absviewangles = value
  when "castspriteshadow"     then actor.castspriteshadow = value
  when "nospriteshadow"       then actor.nospriteshadow = value
  when "masternosee"          then actor.masternosee = value
  when "addlightlevel"        then actor.addlightlevel = value
  when "invisibleinmirrors"   then actor.invisibleinmirrors = value
  when "onlyvisibleinmirrors" then actor.onlyvisibleinmirrors = value
  when "solid"                then actor.solid = value
  when "shootable"            then actor.shootable = value
  when "float"                then actor.float = value
  when "nogravity"            then actor.nogravity = value
  when "windthrust"           then actor.windthrust = value
  when "pushable"             then actor.pushable = value
  when "dontfall"             then actor.dontfall = value
  when "canpass"              then actor.canpass = value
  when "actlikebridge"        then actor.actlikebridge = value
  when "noblockmap"           then actor.noblockmap = value
  when "movewithsector"       then actor.movewithsector = value
  when "relativetofloor"      then actor.relativetofloor = value
  when "noliftdrop"           then actor.noliftdrop = value
  when "slidesonwalls"        then actor.slidesonwalls = value
  when "nodropoff"            then actor.nodropoff = value
  when "noforwardfall"        then actor.noforwardfall = value
  when "notrigger"            then actor.notrigger = value
  when "blockedbysolidactors" then actor.blockedbysolidactors = value
  when "blockasplayer"        then actor.blockasplayer = value
  when "nofriction"           then actor.nofriction = value
  when "nofrictionbounce"     then actor.nofrictionbounce = value
  when "falldamage"           then actor.falldamage = value
  when "allowthrubits"        then actor.allowthrubits = value
  when "crosslinecheck"       then actor.crosslinecheck = value
  when "alwaysrespawn"        then actor.alwaysrespawn = value
  when "ambush"               then actor.ambush = value
  when "avoidmelee"           then actor.avoidmelee = value
  when "boss"                 then actor.boss = value
  when "dontcorpse"           then actor.dontcorpse = value
  when "dontfacetalker"       then actor.dontfacetalker = value
  when "dormant"              then actor.dormant = value
  when "friendly"             then actor.friendly = value
  when "jumpdown"             then actor.jumpdown = value
  when "lookallaround"        then actor.lookallaround = value
  when "missileevenmore"      then actor.missileevenmore = value
  when "missilemore"          then actor.missilemore = value
  when "neverrespawn"         then actor.neverrespawn = value
  when "nosplashalert"        then actor.nosplashalert = value
  when "notargetswitch"       then actor.notargetswitch = value
  when "noverticalmeleerange" then actor.noverticalmeleerange = value
  when "quicktoretaliate"     then actor.quicktoretaliate = value
  when "standstill"           then actor.standstill = value
  when "avoidhazards"         then actor.avoidhazards = value
  when "stayonlift"           then actor.stayonlift = value
  when "dontfollowplayers"    then actor.dontfollowplayers = value
  when "seefriendlymonsters"  then actor.seefriendlymonsters = value
  when "cannotpush"           then actor.cannotpush = value
  when "noteleport"           then actor.noteleport = value
  when "activateimpact"       then actor.activateimpact = value
  when "canpushwalls"         then actor.canpushwalls = value
  when "canusewalls"          then actor.canusewalls = value
  when "activatemcross"       then actor.activatemcross = value
  when "activatepcross"       then actor.activatepcross = value
  when "cantleavefloorpic"    then actor.cantleavefloorpic = value
  when "telestomp"            then actor.telestomp = value
  when "notelestomp"          then actor.notelestomp = value
  when "staymorphed"          then actor.staymorphed = value
  when "canblast"             then actor.canblast = value
  when "noblockmonst"         then actor.noblockmonst = value
  when "allowthruflags"       then actor.allowthruflags = value
  when "thrughost"            then actor.thrughost = value
  when "thruactors"           then actor.thruactors = value
  when "thruspecies"          then actor.thruspecies = value
  when "mthruspecies"         then actor.mthruspecies = value
  when "spectral"             then actor.spectral = value
  when "frightened"           then actor.frightened = value
  when "frightening"          then actor.frightening = value
  when "notarget"             then actor.notarget = value
  when "nevertarget"          then actor.nevertarget = value
  when "noinfightspecies"     then actor.noinfightspecies = value
  when "forceinfighting"      then actor.forceinfighting = value
  when "noinfighting"         then actor.noinfighting = value
  when "notimefreeze"         then actor.notimefreeze = value
  when "nofear"               then actor.nofear = value
  when "cantseek"             then actor.cantseek = value
  when "seeinvisible"         then actor.seeinvisible = value
  when "dontthrust"           then actor.dontthrust = value
  when "allowpain"            then actor.allowpain = value
  when "usekillscripts"       then actor.usekillscripts = value
  when "nokillscripts"        then actor.nokillscripts = value
  when "stoprails"            then actor.stoprails = value
  when "minvisible"           then actor.minvisible = value
  when "mvisblocked"          then actor.mvisblocked = value
  when "shadowaim"            then actor.shadowaim = value
  when "doshadowblock"        then actor.doshadowblock = value
  when "shadowaimvert"        then actor.shadowaimvert = value
  when "invulnerable"         then actor.invulnerable = value
  when "buddha"               then actor.buddha = value
  when "reflective"           then actor.reflective = value
  when "shieldreflect"        then actor.shieldreflect = value
  when "deflect"              then actor.deflect = value
  when "mirrorreflect"        then actor.mirrorreflect = value
  when "aimreflect"           then actor.aimreflect = value
  when "thrureflect"          then actor.thrureflect = value
  when "noradiusdmg"          then actor.noradiusdmg = value
  when "dontblast"            then actor.dontblast = value
  when "shadow"               then actor.shadow = value
  when "ghost"                then actor.ghost = value
  when "dontmorph"            then actor.dontmorph = value
  when "dontsquash"           then actor.dontsquash = value
  when "noteleother"          then actor.noteleother = value
  when "harmfriends"          then actor.harmfriends = value
  when "dontdrain"            then actor.dontdrain = value
  when "dontrip"              then actor.dontrip = value
  when "bright"               then actor.bright = value
  when "invisible"            then actor.invisible = value
  when "noblood"              then actor.noblood = value
  when "noblooddecals"        then actor.noblooddecals = value
  when "stealth"              then actor.stealth = value
  when "floorclip"            then actor.floorclip = value
  when "spawnfloat"           then actor.spawnfloat = value
  when "spawnceiling"         then actor.spawnceiling = value
  when "floatbob"             then actor.floatbob = value
  when "noicedeath"           then actor.noicedeath = value
  when "dontgib"              then actor.dontgib = value
  when "dontsplash"           then actor.dontsplash = value
  when "dontoverlap"          then actor.dontoverlap = value
  when "randomize"            then actor.randomize = value
  when "fixmapthingpos"       then actor.fixmapthingpos = value
  when "fullvolactive"        then actor.fullvolactive = value
  when "fullvoldeath"         then actor.fullvoldeath = value
  when "fullvolsee"           then actor.fullvolsee = value
  when "nowallbouncesnd"      then actor.nowallbouncesnd = value
  when "visibilitypulse"      then actor.visibilitypulse = value
  when "rockettrail"          then actor.rockettrail = value
  when "grenadetrail"         then actor.grenadetrail = value
  when "nobouncesound"        then actor.nobouncesound = value
  when "noskin"               then actor.noskin = value
  when "donttranslate"        then actor.donttranslate = value
  when "nopain"               then actor.nopain = value
  when "forceybillboard"      then actor.forceybillboard = value
  when "forcexybillboard"     then actor.forcexybillboard = value
  when "missile"              then actor.missile = value
  when "ripper"               then actor.ripper = value
  when "nobossrip"            then actor.nobossrip = value
  when "nodamagethrust"       then actor.nodamagethrust = value
  when "dontreflect"          then actor.dontreflect = value
  when "noshieldreflect"      then actor.noshieldreflect = value
  when "floorhugger"          then actor.floorhugger = value
  when "ceilinghugger"        then actor.ceilinghugger = value
  when "bloodlessimpact"      then actor.bloodlessimpact = value
  when "bloodsplatter"        then actor.bloodsplatter = value
  when "foilinvul"            then actor.foilinvul = value
  when "foilbuddha"           then actor.foilbuddha = value
  when "seekermissile"        then actor.seekermissile = value
  when "screenseeker"         then actor.screenseeker = value
  when "skyexplode"           then actor.skyexplode = value
  when "noexplodefloor"       then actor.noexplodefloor = value
  when "strifedamage"         then actor.strifedamage = value
  when "extremedeath"         then actor.extremedeath = value
  when "noextremedeath"       then actor.noextremedeath = value
  when "dehexplosion"         then actor.dehexplosion = value
  when "piercearmor"          then actor.piercearmor = value
  when "forceradiusdmg"       then actor.forceradiusdmg = value
  when "forcezeroradiusdmg"   then actor.forcezeroradiusdmg = value
  when "spawnsoundsource"     then actor.spawnsoundsource = value
  when "painless"             then actor.painless = value
  when "forcepain"            then actor.forcepain = value
  when "causepain"            then actor.causepain = value
  when "dontseekinvisible"    then actor.dontseekinvisible = value
  when "stepmissile"          then actor.stepmissile = value
  when "additivepoisondamage"    then actor.additivepoisondamage = value
  when "additivepoisonduration"  then actor.additivepoisonduration = value
  when "poisonalways"         then actor.poisonalways = value
  when "hittarget"            then actor.hittarget = value
  when "hitmaster"            then actor.hitmaster = value
  when "hittracer"            then actor.hittracer = value
  when "hitowner"             then actor.hitowner = value
  when "bounceonwalls"        then actor.bounceonwalls = value
  when "bounceonfloors"       then actor.bounceonfloors = value
  when "bounceonceilings"     then actor.bounceonceilings = value
  when "allowbounceonactors"  then actor.allowbounceonactors = value
  when "bounceautooff"        then actor.bounceautooff = value
  when "bounceautooffflooronly" then actor.bounceautooffflooronly = value
  when "bouncelikeheretic"    then actor.bouncelikeheretic = value
  when "bounceonactors"       then actor.bounceonactors = value
  when "bounceonunrippables"  then actor.bounceonunrippables = value
  when "explodeonwater"       then actor.explodeonwater = value
  when "canbouncewater"       then actor.canbouncewater = value
  when "mbfbouncer"           then actor.mbfbouncer = value
  when "usebouncestate"       then actor.usebouncestate = value
  when "dontbounceonshootables" then actor.dontbounceonshootables = value
  when "dontbounceonsky"      then actor.dontbounceonsky = value
  when "iceshatter"           then actor.iceshatter = value
  when "dropped"              then actor.dropped = value
  when "ismonster"            then actor.ismonster = value
  when "corpse"               then actor.corpse = value
  when "countitem"            then actor.countitem = value
  when "countkill"            then actor.countkill = value
  when "countsecret"          then actor.countsecret = value
  when "notdmatch"            then actor.notdmatch = value
  when "nonshootable"         then actor.nonshootable = value
  when "dropoff"              then actor.dropoff = value
  when "puffonactors"         then actor.puffonactors = value
  when "allowparticles"       then actor.allowparticles = value
  when "alwayspuff"           then actor.alwayspuff = value
  when "puffgetsowner"        then actor.puffgetsowner = value
  when "forcedecal"           then actor.forcedecal = value
  when "nodecal"              then actor.nodecal = value
  when "synchronized"         then actor.synchronized = value
  when "alwaysfast"           then actor.alwaysfast = value
  when "neverfast"            then actor.neverfast = value
  when "oldradiusdmg"         then actor.oldradiusdmg = value
  when "usespecial"           then actor.usespecial = value
  when "bumpspecial"          then actor.bumpspecial = value
  when "bossdeath"            then actor.bossdeath = value
  when "nointeraction"        then actor.nointeraction = value
  when "notautoaimed"         then actor.notautoaimed = value
  when "nomenu"               then actor.nomenu = value
  when "pickup"               then actor.pickup = value
  when "touchy"               then actor.touchy = value
  when "vulnerable"           then actor.vulnerable = value
  when "notonautomap"         then actor.notonautomap = value
  when "weaponspawn"          then actor.weaponspawn = value
  when "getowner"             then actor.getowner = value
  when "seesdaggers"          then actor.seesdaggers = value
  when "incombat"             then actor.incombat = value
  when "noclip"               then actor.noclip = value
  when "nosector"             then actor.nosector = value
  when "icecorpse"            then actor.icecorpse = value
  when "justhit"              then actor.justhit = value
  when "justattacked"         then actor.justattacked = value
  when "teleport"             then actor.teleport = value
  when "e1m8boss"             then actor.e1m8boss = value
  when "e2m8boss"             then actor.e2m8boss = value
  when "e3m8boss"             then actor.e3m8boss = value
  when "e4m6boss"             then actor.e4m6boss = value
  when "e4m8boss"             then actor.e4m8boss = value
  when "inchase"              then actor.inchase = value
  when "unmorphed"            then actor.unmorphed = value
  when "fly"                  then actor.fly = value
  when "onmobj"               then actor.onmobj = value
  when "argsdefined"          then actor.argsdefined = value
  when "nosightcheck"         then actor.nosightcheck = value
  when "crashed"              then actor.crashed = value
  when "warnbot"              then actor.warnbot = value
  when "huntplayers"          then actor.huntplayers = value
  when "nohateplayers"        then actor.nohateplayers = value
  when "scrollmove"           then actor.scrollmove = value
  when "vfriction"            then actor.vfriction = value
  when "bossspawned"          then actor.bossspawned = value
  when "avoidingdropoff"      then actor.avoidingdropoff = value
  when "chasegoal"            then actor.chasegoal = value
  when "inconversation"       then actor.inconversation = value
  when "armed"                then actor.armed = value
  when "falling"              then actor.falling = value
  when "linedone"             then actor.linedone = value
  when "shattering"           then actor.shattering = value
  when "killed"               then actor.killed = value
  when "bosscube"             then actor.bosscube = value
  when "intrymove"            then actor.intrymove = value
  when "handlenodelay"        then actor.handlenodelay = value
  when "flycheat"             then actor.flycheat = value
  when "respawninvul"         then actor.respawninvul = value
  when "lowgravity"           then actor.lowgravity = value
  when "quartergravity"       then actor.quartergravity = value
  when "longmeleerange"       then actor.longmeleerange = value
  when "shortmissilerange"    then actor.shortmissilerange = value
  when "highermprob"          then actor.highermprob = value
  when "fireresist"           then actor.fireresist = value
  when "donthurtspecies"      then actor.donthurtspecies = value
  when "firedamage"           then actor.firedamage = value
  when "icedamage"            then actor.icedamage = value
  when "hereticbounce"        then actor.hereticbounce = value
  when "hexenbounce"          then actor.hexenbounce = value
  when "doombounce"           then actor.doombounce = value
  when "faster"               then actor.faster = value
  when "fastmelee"            then actor.fastmelee = value
  when "explodeondeath"       then actor.explodeondeath = value
  when "allowclientspawn"     then actor.allowclientspawn = value
  when "clientsideonly"       then actor.clientsideonly = value
  when "nonetid"              then actor.nonetid = value
  when "dontidentifytarget"   then actor.dontidentifytarget = value
  when "scorepillar"          then actor.scorepillar = value
  when "serversideonly"       then actor.serversideonly = value
  when "blueteam"             then actor.blueteam = value
  when "redteam"              then actor.redteam = value
  when "node"                 then actor.node = value
  when "basehealth"           then actor.basehealth = value
  when "superhealth"          then actor.superhealth = value
  when "basearmor"            then actor.basearmor = value
  when "superarmor"           then actor.superarmor = value
  # Sub-object flags (inventory, weapon, etc.)
  when "inventory.quiet"               then actor.inventory.quiet = value
  when "inventory.autoactivate"        then actor.inventory.autoactivate = value
  when "inventory.undroppable", "undroppable"  then actor.inventory.undroppable = value
  when "inventory.unclearable"         then actor.inventory.unclearable = value
  when "inventory.invbar", "invbar"    then actor.inventory.invbar = value
  when "inventory.hubpower"            then actor.inventory.hubpower = value
  when "inventory.persistentpower"     then actor.inventory.persistentpower = value
  when "inventory.interhubstrip"       then actor.inventory.interhubstrip = value
  # Note: inventory.pickupflash is a String property (actor name), not a Bool flag.
  # The +INVENTORY.PICKUPFLASH flag form is extremely rare and handled via property.
  when "inventory.alwayspickup"        then actor.inventory.alwayspickup = value
  when "inventory.fancypickupsound", "fancypickupsound" then actor.inventory.fancypickupsound = value
  when "inventory.noattenpickupsound"  then actor.inventory.noattenpickupsound = value
  when "inventory.bigpowerup"          then actor.inventory.bigpowerup = value
  when "inventory.neverrespawn"        then actor.inventory.neverrespawn = value
  when "inventory.keepdepleted"        then actor.inventory.keepdepleted = value
  when "inventory.ignoreskill"         then actor.inventory.ignoreskill = value
  when "inventory.additivetime"        then actor.inventory.additivetime = value
  when "inventory.untossable"          then actor.inventory.untossable = value
  when "inventory.restrictabsolutely"  then actor.inventory.restrictabsolutely = value
  when "inventory.noscreenflash"       then actor.inventory.noscreenflash = value
  when "inventory.tossed"              then actor.inventory.tossed = value
  when "inventory.alwaysrespawn"       then actor.inventory.alwaysrespawn = value
  when "inventory.transfer"            then actor.inventory.transfer = value
  when "inventory.noteleportfreeze"    then actor.inventory.noteleportfreeze = value
  when "inventory.noscreenblink"       then actor.inventory.noscreenblink = value
  when "inventory.ishealth"            then actor.inventory.ishealth = value
  when "inventory.isarmor"             then actor.inventory.isarmor = value
  when "inventory.forcerespawninsurvival" then actor.inventory.forcerespawninsurvival = value
  when "weapon.noautofire"             then actor.weapon.noautofire = value
  when "weapon.readysndhalf"           then actor.weapon.readysndhalf = value
  when "weapon.dontbob"                then actor.weapon.dontbob = value
  when "weapon.axeblood"               then actor.weapon.axeblood = value
  when "weapon.noalert"                then actor.weapon.noalert = value
  when "weapon.ammo_optional"          then actor.weapon.ammo_optional = value
  when "weapon.alt_ammo_optional"      then actor.weapon.alt_ammo_optional = value
  when "weapon.ammo_checkboth"         then actor.weapon.ammo_checkboth = value
  when "weapon.primary_uses_both"      then actor.weapon.primary_uses_both = value
  when "weapon.alt_uses_both"          then actor.weapon.alt_uses_both = value
  when "weapon.wimpy_weapon", "wimpy_weapon"   then actor.weapon.wimpy_weapon = value
  when "weapon.powered_up", "powered_up"       then actor.weapon.powered_up = value
  when "weapon.staff2_kickback"        then actor.weapon.staff2_kickback = value
  when "weapon.explosive"              then actor.weapon.explosive = value
  when "weapon.meleeweapon", "meleeweapon"     then actor.weapon.meleeweapon = value
  when "weapon.bfg"                    then actor.weapon.bfg = value
  when "weapon.cheatnotweapon"         then actor.weapon.cheatnotweapon = value
  when "weapon.noautoswitchto"         then actor.weapon.noautoswitchto = value
  when "weapon.noautoaim"              then actor.weapon.noautoaim = value
  when "weapon.nodeathdeselect"        then actor.weapon.nodeathdeselect = value
  when "weapon.nodeathinput"           then actor.weapon.nodeathinput = value
  when "weapon.allow_with_respawn_invul" then actor.weapon.allow_with_respawn_invul = value
  when "weapon.nolms"                  then actor.weapon.nolms = value
  when "powerspeed.notrail"            then actor.powerspeed.notrail = value
  when "playerpawn.nothrustwheninvul", "nothrustwheninvul"  then actor.player.nothrustwheninvul = value
  when "playerpawn.cansupermorph", "cansupermorph"          then actor.player.cansupermorph = value
  when "playerpawn.crouchablemorph"    then actor.player.crouchablemorph = value
  when "playerpawn.weaponlevel2ended"  then actor.player.weaponlevel2ended = value
  else
    return false
  end
  true
end

# Sets a property value on an actor. Returns true if recognized.
def set_actor_property(actor : Actor, prop_name : String, line : String) : Bool
  # Strip trailing semicolons — ZSCRIPT uses them as line terminators
  clean_line = line.rstrip.rstrip(';').rstrip
  words = clean_line.split
  val1 = words[1]?
  rest = words[1..]?.try(&.join(' ')) || ""

  begin
    case prop_name
    when "health"
      # Avoid collision with the "Health" actor name
      return false if actor.name.downcase.strip == "health"
      # Clamp to Int32 range — some mods use absurdly large values
      health_val = val1.not_nil!.to_i64?
      if health_val
        actor.health = health_val.clamp(Int32::MIN.to_i64, Int32::MAX.to_i64).to_i32
      else
        log(1, "Cannot parse health value: #{val1}")
      end
    when "gibhealth"         then actor.gib_health = val1.not_nil!.to_i
    when "woundhealth"       then actor.wound_health = val1.not_nil!.to_i
    when "reactiontime"      then actor.reaction_time = val1.not_nil!.to_i
    when "painchance"        then actor.pain_chance = "#{val1},#{words[2]?}"
    when "painthreshold"     then actor.pain_threshold = val1.not_nil!.to_i
    when "damagefactor"      then actor.damage_factor = rest
    when "selfdamagefactor"  then actor.self_damage_factor = val1.not_nil!.to_f
    when "damagemultiply"    then actor.damage_multiply = val1.not_nil!.to_f
    when "damage"            then actor.damage = val1.to_s
    when "poisondamage"      then actor.poison_damage = rest
    when "poisondamagetype"  then actor.poison_damage_type = rest
    when "radiusdamagefactor" then actor.radius_damage_factor = val1.not_nil!.to_f
    when "ripperlevel"       then actor.ripper_level = val1.not_nil!.to_i
    when "riplevelmin"       then actor.rip_level_min = val1.not_nil!.to_i
    when "riplevelmax"       then actor.rip_level_max = val1.not_nil!.to_i
    when "designatedteam"    then actor.designated_team = val1.not_nil!.to_i
    when "speed"             then actor.speed = val1.not_nil!.to_f
    when "vspeed"            then actor.v_speed = val1.not_nil!.to_f
    when "fastspeed"         then actor.fast_speed = val1.not_nil!.to_i
    when "floatspeed"        then actor.float_speed = val1.not_nil!.to_i
    when "species"           then actor.species = val1.to_s
    when "accuracy"          then actor.accuracy = val1.not_nil!.to_i
    when "stamina"           then actor.stamina = val1.not_nil!.to_i
    when "activation"        then actor.activation = rest
    when "telefogsourcetype"  then actor.tele_fog_source_type = val1.to_s
    when "telefogdesttype"   then actor.tele_fog_dest_type = val1.to_s
    when "threshold"         then actor.threshold = val1.not_nil!.to_i
    when "defthreshold"      then actor.def_threshold = val1.not_nil!.to_i
    when "friendlyseeblocks" then actor.friendly_see_blocks = val1.not_nil!.to_i
    when "shadowaimfactor"   then actor.shadow_aim_factor = val1.not_nil!.to_f
    when "shadowpenaltyfactor" then actor.shadow_penalty_factor = val1.not_nil!.to_f
    when "radius"            then actor.radius = val1.not_nil!.to_f
    when "height"            then actor.height = val1.not_nil!.to_i
    when "deathheight"       then actor.death_height = val1.not_nil!.to_i
    when "burnheight"        then actor.burn_height = val1.not_nil!.to_i
    when "projectilepassheight" then actor.projectile_pass_height = val1.not_nil!.to_i
    when "gravity"           then actor.gravity = val1.not_nil!.to_f
    when "friction"          then actor.friction = val1.not_nil!.to_f
    when "mass"              then actor.mass = val1.to_s
    when "maxstepheight"     then actor.max_step_height = val1.not_nil!.to_i
    when "maxdropoffheight"  then actor.max_drop_off_height = val1.not_nil!.to_i
    when "maxslopesteepness" then actor.max_slope_steepness = val1.not_nil!.to_f
    when "bouncetype"        then actor.bounce_type = val1.to_s
    when "bouncefactor"      then actor.bounce_factor = val1.not_nil!.to_f
    when "wallbouncefactor"  then actor.wall_bounce_factor = val1.not_nil!.to_f
    when "bouncecount"       then actor.bounce_count = val1.not_nil!.to_i
    when "projectilekickback" then actor.projectile_kick_back = val1.not_nil!.to_i
    when "pushfactor"        then actor.push_factor = val1.not_nil!.to_f
    when "weaveindexxy"      then actor.weave_index_xy = val1.not_nil!.to_i
    when "weaveindexz"       then actor.weave_index_z = val1.not_nil!.to_i
    when "thrubits"          then actor.thru_bits = val1.not_nil!.to_i
    when "activesound"       then actor.active_sound = val1.to_s
    when "attacksound"       then actor.attack_sound = val1.to_s
    when "bouncesound"       then actor.bounce_sound = val1.to_s
    when "crushpainsound"    then actor.crush_pain_sound = val1.to_s
    when "deathsound"        then actor.death_sound = val1.to_s
    when "howlsound"         then actor.howl_sound = val1.to_s
    when "painsound"         then actor.pain_sound = val1.to_s
    when "ripsound"          then actor.rip_sound = val1.to_s
    when "seesound"          then actor.see_sound = val1.to_s
    when "wallbouncesound"   then actor.wall_bounce_sound = val1.to_s
    when "pushsound"         then actor.push_sound = val1.to_s
    when "renderstyle"       then actor.render_style = val1.to_s
    when "alpha"             then actor.alpha = val1.not_nil!.to_f
    when "defaultalpha"      then actor.default_alpha = true
    when "stealthalpha"      then actor.stealth_alpha = val1.not_nil!.to_f
    when "xscale"            then actor.x_scale = val1.not_nil!.to_f
    when "yscale"            then actor.y_scale = val1.not_nil!.to_f
    when "scale"             then actor.scale = val1.not_nil!.to_f
    when "lightlevel"        then actor.light_level = val1.not_nil!.to_i
    when "translation"       then actor.translation = rest
    when "bloodcolor"        then actor.blood_color = rest
    when "bloodtype"         then actor.blood_type = rest
    when "decal"             then actor.decal = val1.to_s
    when "stencilcolor"      then actor.stencil_color = val1.to_s
    when "floatbobphase"     then actor.float_bob_phase = val1.not_nil!.to_i
    when "floatbobstrength"  then actor.float_bob_strength = val1.not_nil!.to_i
    when "distancecheck"     then actor.distance_check = val1.to_s
    when "spriteangle"       then actor.sprite_angle = val1.not_nil!.to_i
    when "spriterotation"    then actor.sprite_rotation = val1.not_nil!.to_i
    when "visibleangles"     then actor.visible_angles = rest
    when "visiblepitch"      then actor.visible_pitch = rest
    when "renderradius"      then actor.render_radius = val1.not_nil!.to_f
    when "cameraheight"      then actor.camera_height = val1.not_nil!.to_i
    when "camerafov"         then actor.camera_fov = val1.not_nil!.to_f
    when "hitobituary"       then actor.hit_obituary = val1.to_s
    when "obituary"          then actor.obituary = val1.to_s
    when "minmissilechance"  then actor.min_missile_chance = val1.not_nil!.to_i
    when "damagetype"        then actor.damage_type = val1.to_s
    when "deathtype"         then actor.death_type = val1.to_s
    when "meleethreshold"    then actor.melee_threshold = val1.not_nil!.to_i
    when "meleerange"        then actor.melee_range = val1.not_nil!.to_i
    when "maxtargetrange"    then actor.max_target_range = val1.not_nil!.to_i
    when "meleedamage"       then actor.melee_damage = val1.not_nil!.to_i
    when "meleesound"        then actor.melee_sound = val1.to_s
    when "missileheight"     then actor.missile_height = val1.not_nil!.to_i
    when "missiletype"       then actor.missile_type = val1.to_s
    when "explosionradius"   then actor.explosion_radius = val1.not_nil!.to_i
    when "explosiondamage"   then actor.explosion_damage = val1.not_nil!.to_i
    when "donthurtshooter"   then actor.dont_hurt_shooter = true
    when "paintype"          then actor.pain_type = val1.to_s
    when "projectile"        then actor.projectile = true
    when "game"              then actor.game = val1.to_s
    when "spawnid"           then actor.spawn_id = val1.not_nil!.to_i
    when "conversationid"    then actor.conversation_id = rest
    when "tag"               then actor.tag = rest
    when "args"              then actor.args = rest
    when "clearflags"        then actor.clear_flags = true
    when "dropitem"          then actor.drop_item = rest
    when "skip_super"        then actor.skip_super = true
    when "visibletoteam"     then actor.visible_to_team = val1.not_nil!.to_i
    # Inventory properties
    when "inventory.amount"           then actor.inventory.amount = val1.not_nil!.to_i
    when "inventory.defmaxamount"     then actor.inventory.defmaxamount = true
    when "inventory.maxamount"        then actor.inventory.maxamount = val1.to_s.gsub("\"", "")
    when "inventory.interhubamount"   then actor.inventory.interhubamount = val1.not_nil!.to_i
    when "inventory.icon"             then actor.inventory.icon = val1.to_s
    when "inventory.althudicon"       then actor.inventory.althudicon = val1.to_s
    when "inventory.pickupmessage"    then actor.inventory.pickupmessage = rest
    when "inventory.pickupsound"      then actor.inventory.pickupsound = val1.to_s
    when "inventory.pickupflash"      then actor.inventory.pickupflash = val1.to_s
    when "inventory.usesound"         then actor.inventory.usesound = val1.to_s
    when "inventory.respawntics"      then actor.inventory.respawntics = val1.not_nil!.to_i
    when "inventory.givequest"        then actor.inventory.givequest = val1.not_nil!.to_i
    when "inventory.forbiddento"      then actor.inventory.forbiddento = val1.to_s
    when "inventory.restrictedto"     then actor.inventory.restrictedto = val1.to_s
    # Weapon properties
    when "weapon.ammogive", "weapon.ammogive1"  then actor.weapon.ammogive = val1.not_nil!.to_i
    when "weapon.ammogive2"           then actor.weapon.ammogive2 = val1.not_nil!.to_i
    when "weapon.ammotype", "weapon.ammotype1"  then actor.weapon.ammotype = val1.to_s
    when "weapon.ammotype2"           then actor.weapon.ammotype2 = val1.to_s
    when "weapon.ammouse", "weapon.ammouse1"    then actor.weapon.ammouse = val1.not_nil!.to_i
    when "weapon.ammouse2"            then actor.weapon.ammouse2 = val1.not_nil!.to_i
    when "weapon.minselectionammo1"   then actor.weapon.minselectionammo1 = val1.not_nil!.to_i
    when "weapon.minselectionammo2"   then actor.weapon.minselectionammo2 = val1.not_nil!.to_i
    when "weapon.bobpivot3d"          then actor.weapon.bobpivot3d = rest
    when "weapon.bobrangex"           then actor.weapon.bobrangex = val1.not_nil!.to_f
    when "weapon.bobrangey"           then actor.weapon.bobrangey = val1.not_nil!.to_f
    when "weapon.bobspeed"            then actor.weapon.bobspeed = val1.not_nil!.to_f
    when "weapon.bobstyle"            then actor.weapon.bobstyle = rest
    when "weapon.kickback"            then actor.weapon.kickback = val1.not_nil!.to_i
    when "weapon.defaultkickback"     then actor.weapon.defaultkickback = true
    when "weapon.readysound"          then actor.weapon.readysound = rest
    when "weapon.selectionorder"      then actor.weapon.selectionorder = val1.not_nil!.to_i
    when "weapon.sisterweapon"        then actor.weapon.sisterweapon = rest
    when "weapon.slotnumber"          then actor.weapon.slotnumber = val1.not_nil!.to_i
    when "weapon.slotpriority"        then actor.weapon.slotpriority = val1.not_nil!.to_f
    when "weapon.upsound"             then actor.weapon.upsound = rest
    when "weapon.weaponscalex"        then actor.weapon.weaponscalex = val1.not_nil!.to_f
    when "weapon.weaponscaley"        then actor.weapon.weaponscaley = val1.not_nil!.to_f
    when "weapon.yadjust"             then actor.weapon.yadjust = val1.not_nil!.to_i
    when "weapon.lookscale"           then actor.weapon.lookscale = val1.not_nil!.to_f
    # Ammo
    when "ammo.backpackamount"        then actor.ammo.backpackamount = val1.not_nil!.to_i
    when "ammo.backpackmaxamount"     then actor.ammo.backpackmaxamount = val1.not_nil!.to_i
    when "ammo.dropamount"            then actor.ammo.dropamount = val1.not_nil!.to_i
    # WeaponPiece
    when "weaponpiece.number"         then actor.weaponpiece.number = val1.not_nil!.to_i
    when "weaponpiece.weapon"         then actor.weaponpiece.weapon = rest
    # Health class
    when "health.lowmessage"          then actor.healthclass.lowmessage = rest
    # PuzzleItem
    when "puzzleitem.number"          then actor.puzzleitem.number = val1.not_nil!.to_i
    when "puzzleitem.failmessage"     then actor.puzzleitem.failmessage = rest
    when "puzzleitem.failsound"       then actor.puzzleitem.failsound = val1.to_s
    # PlayerPawn
    when "player.aircapacity"         then actor.player.aircapacity = val1.not_nil!.to_f
    when "player.attackzoffset"       then actor.player.attackzoffset = val1.not_nil!.to_i
    when "player.clearcolorset"       then actor.player.clearcolorset = val1.not_nil!.to_i
    when "player.colorrange"          then actor.player.colorrange = rest
    when "player.colorset"            then actor.player.colorset = val1.to_s
    when "player.colorsetfile"        then actor.player.colorsetfile = rest
    when "player.crouchsprite"        then actor.player.crouchsprite = val1.to_s
    when "player.damagescreencolor"   then actor.player.damagescreencolor = rest
    when "player.displayname"         then actor.player.displayname = val1.to_s
    when "player.face"                then actor.player.face = val1.to_s
    when "player.fallingscreamspeed"  then actor.player.fallingscreamspeed = rest
    when "player.flechettetype"       then actor.player.flechettetype = val1.to_s
    when "player.flybob"              then actor.player.flybob = val1.not_nil!.to_f
    when "player.forwardmove"         then actor.player.forwardmove = rest
    when "player.gruntspeed"          then actor.player.gruntspeed = val1.not_nil!.to_f
    when "player.healradiustype"      then actor.player.healradiustype = val1.to_s
    when "player.hexenarmor"          then actor.player.hexenarmor = val1.to_s
    when "player.invulnerabilitymode" then actor.player.invulnerabilitymode = val1.to_s
    when "player.jumpz"              then actor.player.jumpz = val1.not_nil!.to_f
    when "player.maxhealth"          then actor.player.maxhealth = val1.not_nil!.to_i
    when "player.morphweapon"        then actor.player.morphweapon = val1.to_s
    when "player.mugshotmaxhealth"   then actor.player.mugshotmaxhealth = val1.not_nil!.to_i
    when "player.runhealth"          then actor.player.runhealth = val1.not_nil!.to_i
    when "player.scoreicon"          then actor.player.scoreicon = val1.to_s
    when "player.sidemove"           then actor.player.sidemove = rest
    when "player.soundclass"         then actor.player.soundclass = val1.to_s
    when "player.spawnclass"         then actor.player.spawnclass = val1.to_s
    when "player.startitem"          then actor.player.startitem = rest
    when "player.viewbob"            then actor.player.viewbob = val1.not_nil!.to_f
    when "player.viewheight"         then actor.player.viewheight = val1.not_nil!.to_i
    when "player.waterclimbspeed"    then actor.player.waterclimbspeed = val1.not_nil!.to_f
    when "player.weaponslot"         then actor.player.weaponslot = rest
    # Powerup
    when "powerup.color"             then actor.powerup.color = rest
    when "powerup.colormap"          then actor.powerup.colormap = rest
    when "powerup.duration"          then actor.powerup.duration = val1.to_s
    when "powerup.mode"              then actor.powerup.mode = val1.to_s
    when "powerup.strength"          then actor.powerup.strength = val1.not_nil!.to_f
    when "powerup.type"              then actor.powerup.type = val1.to_s
    # HealthPickup
    when "healthpickup.autouse"      then actor.healthpickup.autouse = val1.not_nil!.to_i
    # MorphProjectile
    when "morphprojectile.playerclass"    then actor.morphprojectile.playerclass = val1.to_s
    when "morphprojectile.monsterclass"   then actor.morphprojectile.monsterclass = val1.to_s
    when "morphprojectile.duration"       then actor.morphprojectile.duration = val1.not_nil!.to_i
    when "morphprojectile.morphstyle"     then actor.morphprojectile.morphstyle = rest
    when "morphprojectile.morphflash"     then actor.morphprojectile.morphflash = rest
    when "morphprojectile.unmorphflash"   then actor.morphprojectile.unmorphflash = rest
    else
      return false
    end
  rescue ex
    log(1, "Failed to parse property '#{prop_name}' from line: #{line} (#{ex.message})")
    return false
  end
  true
end

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
# REMOVING IDENTICAL ACTORS
###############################################################################

log(2, "=== Removing Identical Actors ===")

actor_counter = 0

# Group actors by their normalized content (name + inheritance + body)
identical_actors = actordb.group_by { |actor|
  lines = actor.full_actor_text.lines
  first_line = lines[0]? || ""
  inherits = first_line.partition(/\:\s+[^\s]*/)
  first_line = first_line.split[0..1].join(' ')
  first_line = first_line + " " + inherits[1] if inherits[1] != ""
  rest = lines[1..]?.try(&.join("\n")) || ""
  formatted = (first_line + "\n" + rest).lines.map(&.strip.downcase).reject(&.empty?).join("\n")
  formatted
}.select { |_, actors| actors.size > 1 }
 .flat_map { |_, actors| actors }

# Mark first of each group as primary, remove the rest
identical_actor_name = "UNDEFINED"
identical_actors.each do |actor|
  if identical_actor_name != actor.name
    identical_actor_name = actor.name
    actordb.each { |a| a.primary = true if a.index == actor.index && a.file_path == actor.file_path }
    next
  end

  log(3, "Removing duplicate actor: #{actor.name} from #{actor.source_wad_folder}")

  # Remove from the file using balanced brace matching
  file_text = safe_read(actor.file_path)
  regex = /^[\ \t]*actor\s+#{Regex.escape(actor.name)}\s+[^{]*\{/mi
  if md = file_text.match(regex)
    match_start = md.begin(0).not_nil!
    brace_start = file_text.index('{', match_start)
    if brace_start
      # Find the "actor" keyword position
      actor_keyword_pos = file_text.rindex("actor", brace_start) || match_start
      matched = extract_balanced_braces(file_text, brace_start)
      if matched
        actor_end = brace_start + matched.size
        file_text = file_text[0...actor_keyword_pos] +
                    "// duplicate actor removed: #{actor.name}" +
                    file_text[actor_end..]
        File.write(actor.file_path, file_text)
      end
    end
  end

  # Remove from actordb
  actordb.reject! { |a| a.index == actor.index && a.file_path == actor.file_path }
end

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
      file_text = File.read(wad_folder + file)
      file_text = file_text.gsub(/(?<=[\s"])#{Regex.escape(actor.name_with_case)}(?=[\s"])/, renamed_actor)
      File.write(wad_folder + file, file_text)
    end

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
# WIPE ALL DOOMEDNUMS AND REASSIGN TO MONSTERS
###############################################################################

log(2, "=== Wiping and Reassigning Doomednums ===")

# Step 1: Remove all doomednums from non-built-in actors in files
actordb.each do |actor|
  next if actor.built_in || actor.doomednum == -1

  file_text = safe_read(actor.file_path)
  lines = file_text.lines

  lines.each_with_index do |line, line_index|
    next unless line =~ /^\s*actor\s+/i

    words = line.split
    delete_idx = -1
    words.each_with_index do |word, word_index|
      break if word == "{" || word =~ /^\//
      if word.to_i? != nil
        delete_idx = word_index
      end
    end

    if delete_idx != -1
      words.delete_at(delete_idx)
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

    lines.each_with_index do |line, line_index|
      next unless line =~ /^\s*actor\s+/i

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
  else
    # Non-monster: clear doomednum
    actordb[actor_index].doomednum = -1
  end
end

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

sprite_prefix = Hash(String, Array(Tuple(String, String))).new

sprite_files = (Dir.glob("./Processing/*/sprites/*") + Dir.glob("./IWADs_Extracted/*/sprites/*")).map { |p| normalize_path(p) }
sprite_files.each do |path|
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
    list_of_sprites.each do |sprite|
      dir = File.dirname(sprite)
      old_name = File.basename(sprite)
      new_name = old_name.sub(/^#{key}/i, new_prefix)
      new_path = normalize_path(File.join(dir, new_name))
      log(3, "Renaming sprite: #{old_name} → #{new_name}")
      File.rename(sprite, new_path)
    end

    # Update DECORATE and ZSCRIPT references
    # Collect all script files for this WAD (DECORATE + ZSCRIPT + their includes)
    script_files = Array(String).new
    dec_main = "./Processing/#{wad_name}/defs/DECORATE.raw"
    zsc_main = "./Processing/#{wad_name}/defs/ZSCRIPT.raw"
    script_files += collect_decorate_files(dec_main) if File.exists?(dec_main)
    script_files += collect_decorate_files(zsc_main) if File.exists?(zsc_main)
    script_files.uniq!

    script_files.each do |script_file|
      next unless File.exists?(script_file)
      text = File.read(script_file)
      # Replace ALL occurrences of the prefix in sprite reference contexts:
      # - State frame lines: "  SRG2 E 5 A_Chase"
      # - Could appear multiple times on a line or in goto targets
      # Use word-boundary-aware replacement to avoid partial matches
      # Replace sprite prefix references in state frame definitions.
      # Sprite refs in DECORATE/ZSCRIPT are always: PREFIX FRAME DURATION [ACTION]
      # where PREFIX is exactly 4 chars, FRAME is a single letter A-Z, DURATION is a number.
      # Example: "PROJ A 5 A_Chase"
      # We must NOT match inside words like "Projectile" or property names.
      # The pattern requires: start-of-line/whitespace, then PREFIX, then space(s),
      # then a single letter followed by a space or end (the frame character).
      new_text = text.gsub(/(^|[ \t])#{key}([ \t]+[A-Z][ \t\d])/mi) do
        "#{$1}#{new_prefix}#{$2}"
      end
      if new_text != text
        File.write(script_file, new_text)
        log(3, "  Updated sprite references in #{script_file}: #{key} → #{new_prefix}")
      end
    end
  end
end

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
        # Known resource directory — flat-merge contents
        dest_dir = normalize_path(File.join(PK3_BUILD_DIR, entry_lower))
        is_sprites = (entry_lower == "sprites")
        copied, conflicts = copy_resource_files(entry_path, dest_dir, wad_name, conflict_log, is_sprites)
        stats_total_files += copied
        stats_total_conflicts += conflicts
        log(3, "  Resources: #{entry_lower}/ — #{copied} files copied, #{conflicts} conflicts")

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
all_actor_mains = wad_decorate_main + wad_zscript_main
all_actor_mains.each do |wad_name, pk3_path|
  dec_dir = normalize_path(File.join(PK3_BUILD_DIR, "mm_actors", wad_name))
  next unless Dir.exists?(dec_dir)

  Dir.each_child(dec_dir) do |filename|
    file_path = normalize_path(File.join(dec_dir, filename))
    next if File.directory?(file_path)

    content = File.read(file_path)
    original_content = content

    # Strip 'version "x.y.z"' from ZSCRIPT files — only the master ZSCRIPT
    # should have a version directive. Duplicate version in #include'd files
    # causes a parse error.
    content = content.gsub(/^\s*version\s+"[^"]*"\s*$/mi, "// version directive moved to master ZSCRIPT")

    # Match #include "FILENAME" and update path
    content = content.gsub(/^(\s*#include\s+")([^"]+)(")/mi) do |match|
      prefix = $1
      inc_file = $2
      suffix = $3

      if inc_file.includes?("/") || inc_file.includes?("\\")
        # Path includes directory separators — resolve relative to PK3 structure.
        # Original includes like "../FSerpent/FSerpent.txt" were relative to defs/
        # In the PK3, mm_actors/WadName/ is the DECORATE directory, so "../" means
        # up to the WAD root which is now at the PK3 root.
        #
        # Strategy: normalize the path, strip leading "../", and check if the
        # target file exists somewhere in the PK3 build directory.
        normalized_inc = normalize_path(inc_file)

        # Try to find the file in PK3_BUILD_DIR
        # First, strip all leading "../" since those just go up from mm_actors/WadName/
        stripped = normalized_inc.gsub(/^(\.\.\/)+/, "")
        candidate_from_root = normalize_path(File.join(PK3_BUILD_DIR, stripped))
        candidate_in_actors = normalize_path(File.join(PK3_BUILD_DIR, "mm_actors", wad_name, stripped))

        if File.exists?(candidate_in_actors)
          new_path = "mm_actors/#{wad_name}/#{stripped}"
          log(3, "  Rewriting pathed include: #{inc_file} → #{new_path}")
          "#{prefix}#{new_path}#{suffix}"
        elsif File.exists?(candidate_from_root)
          log(3, "  Rewriting pathed include (from root): #{inc_file} → #{stripped}")
          "#{prefix}#{stripped}#{suffix}"
        else
          # Can't resolve — leave as-is and log warning
          log(1, "  Cannot resolve include path: #{inc_file} in #{wad_name} (tried #{candidate_in_actors} and #{candidate_from_root})")
          match
        end
      else
        # Simple filename — convert to PK3-relative path
        # The included file should be in the same mm_actors/WadName/ directory
        new_path = "mm_actors/#{wad_name}/#{inc_file}"
        # Ensure .raw extension if not present
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
      log(3, "  Updated includes in: decorate/#{wad_name}/#{filename}")
    end
  end
end

###############################################################################
# WRITE CONCATENATED TEXT LUMPS
###############################################################################

log(2, "Writing concatenated text lumps...")
log(2, "  #{text_lumps.size} distinct lump types found")

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

  File.write(normalize_path(File.join(PK3_BUILD_DIR, output_name)), merged)
  log(2, "  #{output_name}: #{entries.size} source(s) merged")
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

###############################################################################
# GENERATE LUA MODULE FILE
###############################################################################

log(2, "=== Generating Lua Module ===")

# Determine attack type from DECORATE states
# "melee" = only has Melee state, no Missile state
# "missile" = has Missile state (ranged attack)
# "combo" = has both Melee and Missile states
def detect_attack_type(actor : Actor) : String
  has_melee = actor.states.has_key?("melee")
  has_missile = actor.states.has_key?("missile")
  if has_melee && has_missile
    "combo"
  elsif has_melee
    "melee"
  else
    "missile"
  end
end

# Calculate difficulty tier from health
# Returns {prob, density, damage} based on health thresholds
# Tougher monsters get lower prob/density so they appear less often
def difficulty_tier(health : Int32) : {Int32, Float64, Float64}
  case health
  when     ..60 then {50, 1.2, 5.0}     # Fodder (weaker than Imp)
  when   61..200 then {40, 1.0, 15.0}   # Low-tier (Imp-class)
  when  201..500 then {30, 0.8, 30.0}   # Mid-tier (Cacodemon-class)
  when  501..1000 then {20, 0.5, 50.0}  # Heavy (Baron-class)
  when 1001..2000 then {10, 0.3, 80.0}  # Boss-tier (Cyberdemon-class)
  when 2001..4000 then {5, 0.2, 120.0}  # Super-boss
  else                 {2, 0.1, 200.0}  # Ultra-boss (4000+)
  end
end

# Filter: skip sub-actors, projectiles disguised as monsters, and other
# actors that shouldn't be independently spawned by Obsidian.
# Heuristics:
#   - Very small radius (<=5) AND very small height (<=8): likely a projectile/effect
#   - Height of 1: sub-actor or dummy
#   - Health <= 0: not meant to be fought
def should_include_in_lua(actor : Actor) : Bool
  return false if actor.health <= 0
  return false if actor.radius <= 5 && actor.height <= 8
  return false if actor.height <= 1
  return false if actor.radius <= 1
  true
end

lua_monster_count = 0

lua = String.build do |io|
  io << "----------------------------------------------------------------\n"
  io << "--  Monster Mash — Obsidian Module (auto-generated by Unwad)  --\n"
  io << "----------------------------------------------------------------\n\n"
  io << "MONSTER_MASH = { }\n\n"

  # ── control_setup function ──────────────────────────────────────────
  io << "function MONSTER_MASH.control_setup(self)\n"
  io << "  for name, info in pairs(MONSTER_MASH.MONSTERS) do\n"
  io << "    local opt = self.options[\"float_\" .. name]\n"
  io << "    if opt then\n"
  io << "      local factor = opt.value\n"
  io << "      if factor then\n"
  io << "        info.prob = info.prob * factor\n"
  io << "        info.density = info.density * factor\n"
  io << "      end\n"
  io << "    end\n"
  io << "  end\n"
  io << "end\n\n"

  # ── MONSTER_MASH.MONSTERS table ────────────────────────────────────
  io << "MONSTER_MASH.MONSTERS =\n{\n"

  actordb.each do |actor|
    next unless (actor.ismonster || actor.monster) && actor.doomednum != -1
    next unless should_include_in_lua(actor)

    attack = detect_attack_type(actor)
    prob, density, damage = difficulty_tier(actor.health)

    # Adjust for flying monsters — slightly lower prob (harder to fight)
    if actor.float || actor.nogravity
      prob = (prob * 0.8).to_i
      prob = 1 if prob < 1
    end

    # Sanitize name for Lua: replace non-alphanumeric/underscore with underscore
    lua_key = actor.name.gsub(/[^a-zA-Z0-9_]/, "_")
    # If name starts with a digit, prefix with underscore
    lua_key = "_#{lua_key}" if lua_key[0]?.try(&.ascii_number?)

    io << "  #{lua_key} =\n"
    io << "  {\n"
    io << "    id = #{actor.doomednum},\n"
    io << "    r = #{actor.radius.to_i},\n"
    io << "    h = #{actor.height},\n"
    io << "    prob = #{prob},\n"
    io << "    health = #{actor.health},\n"
    io << "    damage = #{damage},\n"
    io << "    attack = \"#{attack}\",\n"
    io << "    density = #{density}\n"
    io << "  },\n"
    lua_monster_count += 1
  end

  io << "}\n\n"

  # ── OB_MODULES registration ────────────────────────────────────────
  io << "OB_MODULES[\"monster_mash\"] =\n{\n"
  io << "  name = \"monster_mash_control\",\n"
  io << "  label = _(\"Monster Mash\"),\n"
  io << "  game = \"doomish\",\n"
  io << "  port = \"zdoom\",\n"
  io << "  tables =\n  {\n    MONSTER_MASH\n  },\n"
  io << "  hooks =\n  {\n    setup = MONSTER_MASH.control_setup\n  },\n"
  io << "  options =\n  {\n"

  actordb.each do |actor|
    next unless (actor.ismonster || actor.monster) && actor.doomednum != -1
    next unless should_include_in_lua(actor)
    lua_key = actor.name.gsub(/[^a-zA-Z0-9_]/, "_")
    lua_key = "_#{lua_key}" if lua_key[0]?.try(&.ascii_number?)
    io << "    {\n"
    io << "      name = \"float_#{lua_key}\",\n"
    io << "      label = _(\"#{actor.name_with_case}\"),\n"
    io << "      valuator = \"slider\",\n"
    io << "      min = 0,\n"
    io << "      max = 20,\n"
    io << "      increment = 0.02,\n"
    io << "      default = 0.2,\n"
    io << "      presets = _(\"0:0 (None),0.02:0.02 (Scarce),0.14:0.14 (Less),0.5:0.5 (Plenty),1.2:1.2 (More),3:3 (Heaps),20:20 (INSANE)\"),\n"
    io << "      randomize_group = \"monsters\",\n"
    io << "    },\n"
  end

  io << "  },\n}\n"
end

# Write lua output
lua_output_path = "../modules/monster_mash.lua"
File.write(lua_output_path, lua)
log(2, "Lua module written to: #{lua_output_path}")
log(2, "Lua monsters included: #{lua_monster_count}")

puts lua if LOG_LEVEL >= 3

log(2, "=== Unwad V4 Completed Successfully ===")
