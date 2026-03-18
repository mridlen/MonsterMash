###############################################################################
# actor_renaming.cr — Actor renaming and deduplication for Unwad / Monster Mash
#
# Handles:
#  - Renaming actors that conflict with built-in engine names
#  - Renaming duplicate actor names across mods
#  - Refreshing actordb to remove actors no longer present in files
###############################################################################

###############################################################################
# RENAME ACTORS THAT CONFLICT WITH BUILT-IN NAMES
###############################################################################

# Renames non-built-in actors whose names collide with built-in actor names.
# Updates all references in the wad folder's files. Returns updated actor_counter.
def rename_builtin_conflicts(actordb : Array(Actor), actor_counter : Int32) : Int32
  log(2, "=== Renaming Actors That Conflict With Built-In Names ===")

  built_in_names = Set(String).new
  actordb.each { |a| built_in_names << a.name if a.built_in }

  actordb.each do |actor|
    next if actor.built_in
    next unless built_in_names.includes?(actor.name)

    renamed_actor = "#{actor.name_with_case}_MM#{actor_counter}"
    wad_folder = actor.file_path.split("/")[0..-2].join("/") + "/"

    log(2, "Built-in conflict: #{actor.name_with_case} → #{renamed_actor} (conflicts with engine actor)")

    rename_actor_in_folder(actor, renamed_actor, wad_folder)

    # Update actordb entry to match the new name in files
    actor.name = renamed_actor.downcase
    actor.name_with_case = renamed_actor
    actor_counter += 1
  end

  actor_counter
end

###############################################################################
# RENAME DUPLICATE ACTOR NAMES
###############################################################################

# Renames duplicate actor names across mods. The first occurrence keeps its name;
# subsequent duplicates get a _MM suffix. Returns updated actor_counter.
def rename_duplicate_actors(actordb : Array(Actor), actor_counter : Int32) : Int32
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

      rename_actor_in_folder(actor, renamed_actor, wad_folder)

      # [BUGFIX] Update actordb entry to match the new name in files.
      # Without this, the refresh step can't find the old name in files and
      # removes the actor, causing doomednum assignment to fail.
      actor.name = renamed_actor.downcase
      actor.name_with_case = renamed_actor

      actor_counter += 1
    end
  end

  actor_counter
end

###############################################################################
# SHARED RENAME HELPER
###############################################################################

# Applies the 6 standard rename patterns to all files in a wad folder.
# Patterns cover: actor definitions, class definitions, inheritance refs,
# replaces keyword, quoted class name refs, and ZScript 'is' type checks.
def rename_actor_in_folder(actor : Actor, renamed_actor : String, wad_folder : String)
  # Recursively collect all files (PK3-extracted mods may have nested dirs like actors/monsters/)
  all_files = Dir.glob("#{wad_folder}**/*").select { |f| File.file?(f) }.map { |f| normalize_path(f) }
  all_files.each do |file_path_rename|
    next if File.directory?(file_path_rename)

    # Skip binary files — check for null bytes which indicate non-text content.
    # Binary files (sprites, sounds) contain non-UTF-8 bytes that crash regex.
    file_text = File.read(file_path_rename)
    next if file_text.includes?('\0')
    next unless file_text.valid_encoding?

    escaped = Regex.escape(actor.name_with_case)

    # 1. Actor definition line: "actor Name" at line start (DECORATE).
    #    Excludes ZScript variable declarations like "actor nuke = ..."
    file_text = file_text.gsub(/^(\s*actor\s+)#{escaped}(?=[\s:{])(?![ \t]*=)/mi) { "#{$1}#{renamed_actor}" }
    # 2. Class definition line: "class Name" at line start
    file_text = file_text.gsub(/^(\s*class\s+)#{escaped}(?=[\s:{])/mi) { "#{$1}#{renamed_actor}" }
    # 3. Inheritance reference: ": Name" or ": Name,"
    #    Use [ \t]* to prevent matching across lines (state labels use colons too)
    file_text = file_text.gsub(/(:[ \t]*)#{escaped}(?=[\s,{])/mi) { "#{$1}#{renamed_actor}" }
    # 4. Replaces keyword: "replaces Name"
    file_text = file_text.gsub(/(replaces\s+)#{escaped}(?=[\s{])/mi) { "#{$1}#{renamed_actor}" }
    # 5. Quoted class name references: "Name"
    file_text = file_text.gsub(/"#{escaped}"/i, "\"#{renamed_actor}\"")
    # 6. ZScript 'is' type check: 'Name'
    file_text = file_text.gsub(/'#{escaped}'/i, "'#{renamed_actor}'")

    File.write(file_path_rename, file_text)
  end
end

###############################################################################
# REFRESH ACTORDB — Remove actors that no longer exist in files
###############################################################################

# Removes actors from the database whose definitions can no longer be found
# in their source files. This cleans up after renames that may have changed
# actor names in the files.
def refresh_actordb(actordb : Array(Actor))
  log(2, "=== Refreshing Actor Database ===")

  actordb.reject! do |actor|
    next false if actor.native == true

    # Match both DECORATE ("actor Name") and ZScript ("class Name")
    regex = /^\s*(?:actor|class)\s+#{Regex.escape(actor.name)}/mi
    all_files = [actor.file_path]

    # Check includes — resolve both DECORATE bare-name and ZScript path-style includes
    file_text = safe_read(actor.file_path)
    file_text.each_line do |line|
      if line.strip =~ /^#include/i
        if md = line.match(/"([^"]+)"/i)
          include_value = md[1]
          next if include_value.downcase.ends_with?(".acs")
          has_extension = include_value.includes?(".")
          has_path_sep  = include_value.includes?("/") || include_value.includes?("\\")
          if has_extension || has_path_sep
            # ZScript-style path include (e.g. "../zscript/foo/bar.txt")
            inc_path = normalize_path(File.join(File.dirname(actor.file_path), include_value))
          else
            # DECORATE bare-name include (e.g. "Baby" → BABY.raw)
            inc_path = normalize_path(File.join(File.dirname(actor.file_path), "#{include_value.upcase}.raw"))
          end
          all_files << inc_path if File.exists?(inc_path)
        end
      end
    end

    found = all_files.any? { |f| safe_read(f) =~ regex }
    unless found
      log(3, "Removing missing actor: #{actor.name} from #{actor.file_path}")
    end
    !found
  end
end
