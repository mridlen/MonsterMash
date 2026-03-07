###############################################################################
# sprite_conflicts.cr — Sprite prefix conflict resolution
#
# When multiple WADs share the same 4-character sprite prefix (e.g., POSS),
# their sprites would overwrite each other in the merged PK3. This module
# detects conflicts, renames prefixes for conflicting WADs, and updates
# DECORATE/ZSCRIPT references to match.
###############################################################################

# Generate the next available 4-char sprite prefix by incrementing the last
# character. Skips prefixes already in use.
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

# Scan all sprite files across Processing/ and IWADs_Extracted/, detect prefix
# conflicts between WADs, rename conflicting prefixes, and update DECORATE/ZSCRIPT.
def resolve_sprite_conflicts(actordb : Array(Actor))
  log(2, "=== Resolving Sprite Prefix Conflicts ===")

  # [FEATURE] Track all sprite prefix renames for a summary log at the end.
  # Each entry: {wad_name, original_prefix, new_prefix, sprite_count, decorate_files_updated}
  sprite_rename_log = Array(Tuple(String, String, String, Int32, Int32)).new

  sprite_prefix = Hash(String, Array(Tuple(String, String))).new

  sprite_files = (Dir.glob("#{PROCESSING_DIR}/*/sprites/*") + Dir.glob("#{PROCESSING_DIR}/*/sprites/**/*") + Dir.glob("#{IWADS_EXTRACTED_DIR}/*/sprites/*") + Dir.glob("#{IWADS_EXTRACTED_DIR}/*/sprites/**/*")).map { |p| normalize_path(p) }
  sprite_files.each do |path|
    next if File.directory?(path)
    key = path.split("/").last.split(".").first[0..3].upcase
    sha = Digest::SHA256.new.file(path).hexfinal
    sprite_prefix[key] ||= Array(Tuple(String, String)).new
    sprite_prefix[key] << {path, sha}
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

      list_of_sprites = Dir.glob("#{PROCESSING_DIR}/#{wad_name}/sprites/#{key}*").map { |p| normalize_path(p) }
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
      # Also match numbered duplicates from jeutool: DECORATE.1.raw, DECORATE.2.raw, etc.
      script_files = Array(String).new
      Dir.glob("#{PROCESSING_DIR}/#{wad_name}/defs/DECORATE{,.?*}.raw").each do |dec_file|
        script_files += collect_decorate_files(dec_file) if File.exists?(dec_file)
      end
      Dir.glob("#{PROCESSING_DIR}/#{wad_name}/defs/ZSCRIPT{,.?*}.raw").each do |zsc_file|
        script_files += collect_decorate_files(zsc_file) if File.exists?(zsc_file)
      end
      script_files.uniq!

      decorate_updates = 0
      script_files.each do |script_file|
        next unless File.exists?(script_file)
        text = File.read(script_file)
        # Replace sprite prefix references in state frame definitions.
        # Sprite refs in DECORATE/ZSCRIPT are always: PREFIX FRAMES DURATION [ACTION]
        # where PREFIX is exactly 4 chars, FRAMES is one or more letters A-Z, DURATION is a number.
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

  # ── Sprite Rename Summary Log ──────────────────────────────────────────────
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

  # ── Full Sprite Prefix Inventory ───────────────────────────────────────────
  log(2, "")
  log(2, "=== Sprite Prefix Inventory (per WAD, post-rename) ===")

  wad_prefix_inventory = Hash(String, Hash(String, Int32)).new
  sprite_inventory_files = Dir.glob("#{PROCESSING_DIR}/*/sprites/**/*").map { |p| normalize_path(p) }
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
end
