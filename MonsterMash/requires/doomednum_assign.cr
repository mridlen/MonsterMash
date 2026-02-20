###############################################################################
# doomednum_assign.cr — Reserved doomednum data & wipe/reassign pipeline
#
# Builds the reserved doomednum table, then wipes all existing doomednums
# from non-built-in actors and reassigns fresh ones to monsters, weapons,
# and ZScript actors. Also injects //$Category tags.
###############################################################################

# Build the hash of reserved doomednums that must not be assigned to actors.
# These are used by Obsidian, engine internals, and other modules.
def build_reserved_doomednums : Hash(Int32, Tuple(Int32, Int32))
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
  doomednum_info
end

# Wipe all existing doomednums from non-built-in actors, then reassign
# fresh doomednums to monsters, weapons, and ZScript actors.
# Also injects //$Category tags into DECORATE and ZScript files.
# Returns the final doomednum_counter value.
def wipe_and_reassign_doomednums(
  actordb : Array(Actor),
  weapon_actor_set : Set(String),
  doomednum_info : Hash(Int32, Tuple(Int32, Int32))
) : Int32
  log(2, "=== Wiping and Reassigning Doomednums ===")

  # Step 1: Remove all doomednums from non-built-in actors in files
  actordb.each do |actor|
    next if actor.built_in || actor.doomednum == -1

    file_text = safe_read(actor.file_path)
    lines = file_text.lines

    # [BUGFIX] Track /* ... */ block comments so actor definitions inside
    # them are not processed (lazerrifle bug).
    each_actor_line(lines) do |line, line_index|
      words = line.split
      delete_idx = -1
      replace_with_comment = nil.as(String?)
      words.each_with_index do |word, word_index|
        break if word == "{" || word =~ /^\//
        # [BUGFIX] Handle tokens like "31378//add your own..." where a number
        # is glued to a // comment with no space (phantasm, phantasm2 bug).
        if word.includes?("//")
          parts = word.split("//", 2)
          if parts[0].to_i? != nil
            delete_idx = word_index
            replace_with_comment = "//" + parts[1]
          end
        elsif word.to_i? != nil
          delete_idx = word_index
        end
      end

      if delete_idx != -1
        if replace_with_comment
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

      # [BUGFIX] Skip lines inside /* ... */ block comments (lazerrifle bug)
      each_actor_line(lines) do |line, line_index|
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

        # Insert //$Category Monsters after the '{' line if not already present.
        if inject_category_after_brace(lines, line_index, "Monsters")
          log(3, "Injected //$Category Monsters for #{actor.name_with_case}")
        end
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

    # [BUGFIX] Skip lines inside /* ... */ block comments (lazerrifle bug)
    each_actor_line(lines) do |line, line_index|
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

      # Insert //$Category Weapons after the '{' line if not already present.
      if inject_category_after_brace(lines, line_index, "Weapons")
        log(3, "Injected //$Category Weapons for #{actor.name_with_case}")
      end
    end

    File.write(actor.file_path, lines.join("\n"))
  end

  # Step 4: Assign doomednums to ZScript monsters and weapons (in actordb only).
  # Unlike DECORATE actors, these are NOT written into the source files — they
  # will be emitted via a MAPINFO DoomEdNums block later.
  actordb.each_with_index do |actor, actor_index|
    next if actor.built_in
    next unless actor.script_type == "zscript" || actor.script_type == "both"
    next unless (actor.ismonster || actor.monster) || weapon_actor_set.includes?(actor.name.downcase)
    next if actor.doomednum != -1  # already assigned somehow

    while doomednum_info.has_key?(doomednum_counter)
      doomednum_counter += 1
    end

    doomednum_info[doomednum_counter] = {-1, -1}
    actordb[actor_index].doomednum = doomednum_counter
    log(3, "Assigned ZScript doomednum #{doomednum_counter} to #{actor.name_with_case}")
  end

  log(2, "Doomednum assignment complete. Counter ended at: #{doomednum_counter}")

  ###########################################################################
  # INSERT //$Category INTO ZSCRIPT ACTORS (inside Default {} block)
  # DECORATE actors are handled inline during doomednum assignment above.
  # ZScript actors use "class Name : Parent { Default { ... } }" structure,
  # so //$Category goes after the opening '{' of the Default block.
  ###########################################################################

  log(2, "=== Inserting //$Category tags for ZScript actors ===")

  zscript_category_files = Hash(String, Hash(String, String)).new  # file_path => {actor_name_lc => category}
  actordb.each do |actor|
    next if actor.built_in
    next unless actor.script_type == "zscript" || actor.script_type == "both"
    category = if actor.ismonster || actor.monster
                 "Monsters"
               elsif weapon_actor_set.includes?(actor.name.downcase)
                 "Weapons"
               else
                 nil
               end
    next unless category
    zscript_category_files[actor.file_path] ||= Hash(String, String).new
    zscript_category_files[actor.file_path][actor.name_with_case.downcase] = category
  end

  zscript_category_files.each do |file_path, name_map|
    file_text = safe_read(file_path)
    lines = file_text.lines

    i = 0
    while i < lines.size
      line = lines[i]
      # Match ZScript class definition: "class Name : Parent"
      if line =~ /^\s*class\s+(\w+)/i
        class_name_lc = $1.downcase
        category = name_map[class_name_lc]?
        if category
          # Scan forward from class line to find "Default" then its '{'
          j = i + 1
          found_default = false
          while j < lines.size
            if lines[j] =~ /^\s*Default\s*$/i || lines[j] =~ /^\s*Default\s*\{/i
              found_default = true
              # Find the '{' — may be on this Default line or the next
              brace_idx = j
              unless lines[brace_idx].includes?("{")
                brace_idx += 1
                while brace_idx < lines.size && !lines[brace_idx].includes?("{")
                  brace_idx += 1
                end
              end
              if brace_idx < lines.size
                cat_idx = brace_idx + 1
                unless cat_idx < lines.size && lines[cat_idx] =~ /\/\/\$Category/i
                  # Match indentation of the line after the brace, or use tabs
                  indent = "    "
                  if cat_idx < lines.size
                    ind_match = lines[cat_idx].match(/^(\s+)/)
                    indent = ind_match[1] if ind_match
                  end
                  lines.insert(cat_idx, "#{indent}//$Category #{category}")
                  log(3, "Injected //$Category #{category} for ZScript class #{$1}")
                end
              end
              break
            end
            # Stop scanning if we hit another class definition or end of block
            break if lines[j] =~ /^\s*class\s+/i
            j += 1
          end
        end
      end
      i += 1
    end

    File.write(file_path, lines.join("\n"))
  end

  log(2, "//$Category ZScript injection complete.")

  doomednum_counter
end
