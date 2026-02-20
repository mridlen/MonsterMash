###############################################################################
# pk3_merge.cr — Merge all processed WAD content into a single PK3
#
# This module contains the build_merged_pk3 function, which takes the parsed
# actor database and weapon actor set and produces a merged PK3 file from all
# extracted WAD content in the Processing/ directory.
#
# The merge process:
#   1. Resource dirs (sprites/, sounds/, etc.) -> flat-merged into PK3 dirs
#   2. DECORATE files -> per-WAD subdirs under mm_actors/, master DECORATE #includes
#   3. Text lumps (SNDINFO, GLDEFS, etc.) -> concatenated with source attribution
#   4. Credits -> merged with per-source labeling
#   5. Unknown items -> copied with warnings for manual review
#
# The output is ./Completed/monster_mash.pk3
#
# Constants used from pk3_extract.cr:
#   PK3_BUILD_DIR, PK3_OUTPUT, RESOURCE_DIRS, TEXT_LUMP_NAMES,
#   SKIP_LUMP_NAMES, DECORATE_LUMP_NAMES
#
# Helpers used from helpers.cr:
#   normalize_path, safe_read, lump_name, copy_resource_files,
#   add_dir_to_zip, print_progress_bar, collect_decorate_files,
#   infer_weapon_slot
#
# Constants used from sound_conflicts.cr:
#   DEFAULT_SNDINFO, DEFAULT_RANDOM_SOUNDS, DEFAULT_LUMP_TO_LOGICAL
###############################################################################

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
          log(3, "  Rewriting pathed include: #{inc_file} -> #{new_path}")
          "#{prefix}#{new_path}#{suffix}"
        elsif File.exists?(candidate_from_root)
          log(3, "  Rewriting pathed include (from root): #{inc_file} -> #{stripped}")
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
        log(3, "  Rewriting include: #{inc_file} -> #{new_path}")
        "#{prefix}#{new_path}#{suffix}"
      end
    end

    if content != original_content
      File.write(file_path, content)
      log(3, "  Updated includes in: mm_actors/#{wad_name}/#{filename}")
    end
  end
end

def build_merged_pk3(actordb : Array(Actor), weapon_actor_set : Set(String))
  log(2, "=== Building Merged PK3 ===")

  # Clean and create PK3 staging directory
  if Dir.exists?(PK3_BUILD_DIR)
    FileUtils.rm_rf(PK3_BUILD_DIR)
  end
  Dir.mkdir_p(PK3_BUILD_DIR)
  Dir.mkdir_p(File.join(PK3_BUILD_DIR, "mm_actors"))

  # Tracking structures
  text_lumps = Hash(String, Array(Tuple(String, String))).new     # lump_name -> [{wad, content}]
  credits_parts = Array(Tuple(String, String)).new                # [{wad, credit_text}]
  conflict_log = Array(String).new                                 # resource file conflicts
  unknown_dirs = Hash(String, Array(String)).new                   # dirname -> [wad_names]
  unknown_files = Hash(String, Array(String)).new                  # filename -> [wad_names]
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
    print_progress_bar(wad_index, total_wads, wad_name)
    puts ""  # Newline so warnings/log output don't collide with progress bar

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
              log(3, "  DECORATE: #{def_file} -> mm_actors/#{wad_name}/#{def_file}")

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
              log(3, "  DECORATE (extra): #{def_file} -> mm_actors/#{wad_name}/#{def_file}")

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
          # Redirect music/ -> sounds/: jeutool categorizes many sound effect lumps
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
            log(2, "  Root ZSCRIPT: #{entry} -> mm_actors/#{wad_name}/")
          else
            unless wad_decorate_main.any? { |t| t[0] == wad_name }
              wad_decorate_main << {wad_name, pk3_path}
            end
            log(2, "  Root DECORATE: #{entry} -> mm_actors/#{wad_name}/")
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
      log(2, "  KEYCONF: sanitized #{keyconf_fixes} directive(s) (setslot->addslotdefault, stripped player classes)")

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

        slot = infer_weapon_slot(actor)
        slot_additions << "addslotdefault #{slot} #{actor.name_with_case}"
        log(3, "  KEYCONF auto-slot: #{actor.name_with_case} -> slot #{slot}")
      end

      if slot_additions.size > 0
        merged += "\n\n// Auto-generated slot assignments for weapons missing KEYCONF entries\n"
        merged += slot_additions.join("\n")
        merged += "\n"
        log(2, "  KEYCONF: auto-assigned #{slot_additions.size} weapon(s) to slots")
      end
    end

    # Post-process MAPINFO: strip existing DoomEdNums blocks so they can be
    # reassigned cleanly via our generated block (appended after text lump writing).
    if canonical_name == "mapinfo" || canonical_name == "zmapinfo"
      stripped_lines = [] of String
      in_doomednums = false
      brace_depth = 0
      merged.each_line do |line|
        if !in_doomednums && (line.strip =~ /^DoomEdNums\s*$/i || line.strip =~ /^DoomEdNums\s*\{/i)
          in_doomednums = true
          brace_depth = line.count('{') - line.count('}')
          next
        end
        if in_doomednums
          brace_depth += line.count('{') - line.count('}')
          if brace_depth <= 0
            in_doomednums = false
          end
          next
        end
        stripped_lines << line
      end
      new_merged = stripped_lines.join("\n")
      if new_merged != merged
        log(2, "  MAPINFO: stripped existing DoomEdNums block(s) (will be reassigned)")
        merged = new_merged
      end
    end

    # Post-process SNDINFO: prefix bare lump names with their PK3 path.
    # In a WAD, SNDINFO lump references are bare names (e.g., "GUNCOCK_SING").
    # In a PK3, GZDoom needs the path relative to the PK3 root
    # (e.g., "sounds/GUNCOCK_SING" or "sounds/DoublePumpGun/DBPGFIRE").
    # Build an index of all files in sounds/ and rewrite lump references.
    if canonical_name == "sndinfo"
      # Build lookup: lowercase lump name (no ext) -> PK3-relative path
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
      # wad -> set of protected logical names this WAD defines
      wad_protected_names = Hash(String, Set(String)).new
      # wad -> all logical names defined (for finding $random children)
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
      wad_random_children = Hash(String, Set(String)).new  # wad -> extra names to rename

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
        wad_rename_map = Hash(String, Hash(String, String)).new  # wad -> {old_logical -> new_logical}
        wad_protected_names.each do |wad_name, names|
          abbrev = wad_name.downcase.gsub(/[^a-z0-9]/, "")[0, 4]
          abbrev = "mod" if abbrev.empty?
          wad_rename_map[wad_name] = Hash(String, String).new
          names.each do |old_name|
            # Replace the prefix: "grunt/death1" -> "mm_grun_grunt/death1"
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
          renames.each { |old_n, new_n| log(1, "      #{old_n} -> #{new_n}") }
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

  ###############################################################################
  # APPEND DOOMEDNUMS BLOCK TO MAPINFO FOR ZSCRIPT ACTORS
  # ZScript classes cannot have doomednums on their class line — they must be
  # assigned via a DoomEdNums block in MAPINFO.
  ###############################################################################

  zscript_ednum_entries = [] of String
  actordb.each do |actor|
    next if actor.built_in
    next unless actor.script_type == "zscript" || actor.script_type == "both"
    next if actor.doomednum == -1
    zscript_ednum_entries << "  #{actor.doomednum} = #{actor.name_with_case}"
  end

  if zscript_ednum_entries.size > 0
    doomednums_block = String.build do |io|
      io << "\n// ============================================================\n"
      io << "// DoomEdNums — Monster Mash (auto-generated for ZScript actors)\n"
      io << "// ============================================================\n\n"
      io << "DoomEdNums\n"
      io << "{\n"
      zscript_ednum_entries.each { |entry| io << entry << "\n" }
      io << "}\n"
    end

    mapinfo_path = normalize_path(File.join(PK3_BUILD_DIR, "MAPINFO"))
    mapinfo_lmp_path = normalize_path(File.join(PK3_BUILD_DIR, "MAPINFO.lmp"))

    if File.exists?(mapinfo_path)
      File.write(mapinfo_path, File.read(mapinfo_path) + doomednums_block)
      log(2, "  MAPINFO: appended DoomEdNums block with #{zscript_ednum_entries.size} ZScript actor(s)")
    elsif File.exists?(mapinfo_lmp_path)
      File.write(mapinfo_lmp_path, File.read(mapinfo_lmp_path) + doomednums_block)
      log(2, "  MAPINFO.lmp: appended DoomEdNums block with #{zscript_ednum_entries.size} ZScript actor(s)")
    else
      File.write(mapinfo_path, doomednums_block.lstrip)
      log(2, "  MAPINFO: created with DoomEdNums block for #{zscript_ednum_entries.size} ZScript actor(s)")
    end
  end

  # [BUGFIX] If no WAD contributed a KEYCONF, generate one from scratch so all
  # weapons get slot assignments. Without this, weapons from WADs that rely on
  # Weapon.SlotNumber (or have no slot at all) will be unselectable in-game.
  unless keyconf_was_processed
    slot_additions = [] of String
    actordb.each do |actor|
      next if actor.built_in
      next unless weapon_actor_set.includes?(actor.name.downcase)

      slot = infer_weapon_slot(actor)
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
      f.puts "  #{wad_name} -> #{pk3_path}"
    end
    f.puts ""

    unless wad_zscript_main.empty?
      f.puts "ZSCRIPT include order:"
      wad_zscript_main.sort_by { |t| t[0].downcase }.each do |wad_name, pk3_path|
        f.puts "  #{wad_name} -> #{pk3_path}"
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
end
