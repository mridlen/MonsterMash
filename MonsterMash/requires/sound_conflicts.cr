###############################################################################
# sound_conflicts.cr — Sound lump conflict resolution
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

# GZDoom default SNDINFO: logical_name → lump_name
# This maps Doom II engine lumps to their default logical sound names.
# Only includes monster/world sounds likely to be overridden by monster mods.
# Source: zdoom.git wadsrc/static/filter/game-doomchex/sndinfo.txt
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
  # Player weapons
  "weapons/sawup" => "dssawup", "weapons/sawidl" => "dssawidl",
  "weapons/sawfull" => "dssawful", "weapons/sawhit" => "dssawhit",
  "weapons/pistol" => "dspistol", "weapons/shotgf" => "dsshotgn",
  "weapons/shotgr" => "dssgcock", "weapons/sshotf" => "dsdshtgn",
  "weapons/sshoto" => "dsdbopn", "weapons/sshotc" => "dsdbcls",
  "weapons/sshotl" => "dsdbload",
  "weapons/chngun" => "dschgun", "weapons/rocklf" => "dsrlaunc",
  "weapons/rockrx" => "dsbarexp", "weapons/plasmaf" => "dsplasma",
  "weapons/plasmax" => "dsfirxpl", "weapons/bfgf" => "dsbfg",
  "weapons/bfgx" => "dsrxplod",
  # Misc player sounds
  "*fist" => "dspunch",
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

# Reverse map: lump_name (uppercase) → [logical_names]
DEFAULT_LUMP_TO_LOGICAL = Hash(String, Array(String)).new
DEFAULT_SNDINFO.each do |logical, lump|
  key = lump.upcase
  DEFAULT_LUMP_TO_LOGICAL[key] ||= Array(String).new
  DEFAULT_LUMP_TO_LOGICAL[key] << logical
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

# Detect and resolve sound lump conflicts across WADs, rename conflicting
# files, rewrite SNDINFO, and generate synthetic SNDINFO for lump-replacement WADs.
def resolve_sound_conflicts(actordb : Array(Actor))
  log(2, "=== Resolving Sound Lump Conflicts ===")

  # Build inventory: sound_lump_name (uppercase, no ext) → [{path, wad_name, is_iwad}]
  sound_inventory = Hash(String, Array(NamedTuple(path: String, wad_name: String, is_iwad: Bool))).new

  # Scan IWAD sounds first
  iwad_sound_files = Dir.glob("#{IWADS_EXTRACTED_DIR}/*/sounds/*").map { |p| normalize_path(p) }
  iwad_sound_files.each do |path|
    next if File.directory?(path)
    lump = File.basename(path, File.extname(path)).upcase
    wad_name = path.split("/")[2]
    sound_inventory[lump] ||= Array(NamedTuple(path: String, wad_name: String, is_iwad: Bool)).new
    sound_inventory[lump] << {path: path, wad_name: wad_name, is_iwad: true}
  end

  # Scan mod sounds (both sounds/ and music/ — jeutool often miscategorizes
  # sound effects as "music" for WADs without proper S_START/S_END markers)
  mod_sound_files = (Dir.glob("#{PROCESSING_DIR}/*/sounds/*") + Dir.glob("#{PROCESSING_DIR}/*/music/*")).map { |p| normalize_path(p) }
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
      wad_has_sndinfo = sndinfo_candidates(entry[:wad_name]).any? { |p| File.exists?(p) }

      # Note: WADs without SNDINFO will still be renamed. A synthetic SNDINFO
      # and DECORATE rewrite will be generated after this loop.
      unless wad_has_sndinfo
        log(2, "    #{entry[:wad_name]} has no SNDINFO — will generate synthetic mapping for #{lump}")
      end

      # Generate a unique new lump name.
      # Strategy: truncate lump + append WAD-derived suffix, keeping total <= 8 chars.
      # GZDoom auto-detects DS* sound lumps by name, so longer names risk
      # matching on the first 8 characters and overwriting IWAD sounds.
      wad_abbrev = entry[:wad_name].gsub(/[^a-zA-Z0-9]/, "")[0..1].upcase  # 2-char WAD abbreviation
      max_base = 8 - 1 - wad_abbrev.size  # 1 for underscore separator
      truncated_lump = lump[0...max_base]
      candidate = "#{truncated_lump}_#{wad_abbrev}"

      # Ensure uniqueness — swap last char for a digit if needed
      suffix_counter = 0
      while all_sound_lumps.includes?(candidate)
        suffix_counter += 1
        # Trim further to fit the counter digit within 8 chars
        max_with_counter = 8 - 1 - suffix_counter.to_s.size
        candidate = "#{lump[0...max_with_counter]}_#{suffix_counter}"
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
    sndinfo_files = sndinfo_candidates(wad_name).select { |p| File.exists?(p) }

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

  #############################################################################
  # SYNTHETIC SNDINFO + DECORATE REWRITE FOR NO-SNDINFO WADS
  #############################################################################

  log(2, "=== Generating Synthetic SNDINFO for Lump-Replacement WADs ===")

  # Also build a reverse map for $random: child_logical → parent_logical
  random_child_to_parent = Hash(String, String).new
  DEFAULT_RANDOM_SOUNDS.each do |parent, children|
    children.each { |child| random_child_to_parent[child] = parent }
  end

  synthetic_sndinfo_count = 0
  synthetic_decorate_rewrites = 0

  sound_renames.each do |wad_name, renames|
    next if renames.empty?

    # Check if this WAD already has a SNDINFO (already handled above)
    has_existing_sndinfo = sndinfo_candidates(wad_name).any? { |p| File.exists?(p) }

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
            children = DEFAULT_RANDOM_SOUNDS[matched_logical]
            new_children = Array(String).new

            children.each_with_index do |child, idx|
              child_lump = DEFAULT_SNDINFO[child]?.try(&.upcase)
              new_child_logical = "#{new_logical}#{idx + 1}"

              if child_lump && renames.has_key?(child_lump)
                sndinfo_lines << "#{new_child_logical} #{renames[child_lump].downcase}"
                log(3, "      SNDINFO: #{new_child_logical} #{renames[child_lump].downcase}")
              elsif child_lump
                sndinfo_lines << "#{new_child_logical} #{child_lump.downcase}"
                log(3, "      SNDINFO: #{new_child_logical} #{child_lump.downcase}")
              end
              new_children << new_child_logical
            end

            sndinfo_lines << "$random #{new_logical} { #{new_children.join(" ")} }"
            log(3, "      SNDINFO: $random #{new_logical} { #{new_children.join(" ")} }")
          else
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
      sndinfo_path = normalize_path("#{PROCESSING_DIR}/#{wad_name}/defs/SNDINFO.raw")
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
end
