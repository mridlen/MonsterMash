###############################################################################
# pk3_extract.cr — PK3/ZIP extraction and resource file utilities
#
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
