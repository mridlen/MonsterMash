###############################################################################
# actor_classification.cr — Monster/Weapon/Ammo/Pickup evaluation &
#                            ZScript class detection for Unwad / Monster Mash
#
# Classifies actors by walking inheritance chains and checking properties.
###############################################################################

###############################################################################
# BASE CLASS CONSTANTS
###############################################################################

# Known base weapon classes (lowercase)
WEAPON_BASE_CLASSES = Set{
  "weapon", "doomweapon", "hereticweapon", "hexenweapon", "strifeweapon",
  "fist", "chainsaw", "pistol", "shotgun", "supershotgun", "chaingun",
  "rocketlauncher", "plasmarifle", "bfg9000",
}

# Known base ammo classes (lowercase)
AMMO_BASE_CLASSES = Set{
  "ammo",
  # Standard Doom ammo actors
  "clip", "clipbox", "cell", "cellpack",
  "shell", "shellbox", "rocketammo", "rocketbox",
  # Heretic ammo
  "goldwandammo", "goldwandhemo1", "crossbowammo",
  "blasterammo", "skullrodammo", "phoenixrodammo", "maceammo",
}

# Known base pickup classes (lowercase)
PICKUP_BASE_CLASSES = Set{
  "inventory", "custominventory", "powerupgiver",
  "armorbonus", "basicarmorpickup", "basicarmor",
  "soulsphere", "megasphere",
  "health", "healthpickup", "healthbonus",
  "maprevealerpickup", "backpackitem",
}

# Subsets for pickup kind classification
HEALTH_PICKUP_CLASSES = Set{"health", "healthpickup", "healthbonus", "soulsphere", "megasphere"}
ARMOR_PICKUP_CLASSES = Set{"armorbonus", "basicarmorpickup", "basicarmor"}
POWERUP_PICKUP_CLASSES = Set{"powerupgiver"}

###############################################################################
# EVALUATE MONSTER STATUS VIA INHERITANCE
###############################################################################

def evaluate_monster_status(actordb : Array(Actor), actors_by_name : Hash(String, Array(Actor)))
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

    # Actors with +NOINTERACTION are purely decorative, not monsters
    if is_monster && actor.nointeraction
      is_monster = false
      log(3, "Monster excluded (NOINTERACTION): #{actor.name_with_case}")
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
end

###############################################################################
# EVALUATE WEAPON STATUS VIA INHERITANCE
###############################################################################

def evaluate_weapon_status(actordb : Array(Actor), actors_by_name : Hash(String, Array(Actor))) : Set(String)
  log(2, "=== Evaluating Weapon Status ===")

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

  weapon_actor_set
end

###############################################################################
# EVALUATE AMMO STATUS VIA INHERITANCE
###############################################################################

def evaluate_ammo_status(actordb : Array(Actor), actors_by_name : Hash(String, Array(Actor))) : Set(String)
  log(2, "=== Evaluating Ammo Status ===")

  ammo_actor_set = Set(String).new

  actordb.each do |actor|
    next if actor.built_in == true

    is_ammo = false

    # Check 1: Does it have ammo-specific properties applied?
    has_ammo_props = actor.ammo.backpackamount != -1 ||
                     actor.ammo.backpackmaxamount != -1 ||
                     actor.ammo.dropamount != -1

    # Check 2: Walk the inheritance chain to see if it inherits from Ammo
    if has_ammo_props || actor.inherits != "UNDEFINED"
      inheritance_chain = [actor.name.downcase]
      inherits_name = actor.inherits

      while inherits_name != "UNDEFINED"
        lc_name = inherits_name.downcase
        if AMMO_BASE_CLASSES.includes?(lc_name)
          is_ammo = true
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

    # Check 3: Has ammo properties even without recognized inheritance
    if !is_ammo && has_ammo_props
      is_ammo = true
    end

    if is_ammo
      actor.is_ammo = true
      ammo_actor_set.add(actor.name.downcase)
      log(3, "Ammo confirmed: #{actor.name_with_case} (amount: #{actor.inventory.amount})")
    end
  end

  ammo_count = ammo_actor_set.size
  log(2, "Ammo actors found: #{ammo_count}")

  ammo_actor_set
end

###############################################################################
# EVALUATE PICKUP STATUS VIA INHERITANCE
###############################################################################

def evaluate_pickup_status(actordb : Array(Actor), actors_by_name : Hash(String, Array(Actor)),
                           weapon_actor_set : Set(String), ammo_actor_set : Set(String)) : Set(String)
  log(2, "=== Evaluating Pickup Status ===")

  pickup_actor_set = Set(String).new

  actordb.each do |actor|
    next if actor.built_in == true
    # Skip weapons and ammo — they are not pickups in this context
    next if weapon_actor_set.includes?(actor.name.downcase)
    next if ammo_actor_set.includes?(actor.name.downcase)

    # Must have a pickup message
    next if actor.inventory.pickupmessage == "UNDEFINED"

    # Must have a visible spawn state
    next unless has_visible_spawn_state(actor) # requires/actor_parsing.cr

    is_pickup = false
    pickup_kind = "other"
    matched_base = ""

    # Walk the inheritance chain to check for pickup base classes
    if actor.inherits != "UNDEFINED"
      inheritance_chain = [actor.name.downcase]
      inherits_name = actor.inherits

      while inherits_name != "UNDEFINED"
        lc_name = inherits_name.downcase
        if PICKUP_BASE_CLASSES.includes?(lc_name)
          is_pickup = true
          matched_base = lc_name
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

    next unless is_pickup

    # Classify the pickup kind based on matched base class
    if HEALTH_PICKUP_CLASSES.includes?(matched_base)
      pickup_kind = "health"
    elsif ARMOR_PICKUP_CLASSES.includes?(matched_base)
      pickup_kind = "armor"
    elsif POWERUP_PICKUP_CLASSES.includes?(matched_base)
      pickup_kind = "powerup"
    elsif actor.powerup.type != "UNDEFINED" || actor.powerup.duration != "0"
      # Has powerup properties even if not directly inheriting from PowerupGiver
      pickup_kind = "powerup"
    else
      pickup_kind = "other"
    end

    actor.is_pickup = true
    actor.pickup_kind = pickup_kind
    pickup_actor_set.add(actor.name.downcase)
    log(3, "Pickup confirmed: #{actor.name_with_case} (kind: #{pickup_kind}, base: #{matched_base})")
  end

  pickup_count = pickup_actor_set.size
  log(2, "Pickup actors found: #{pickup_count}")

  pickup_actor_set
end

###############################################################################
# ZSCRIPT CLASS DETECTION
# Standalone pass for monster/weapon/ammo/pickup classification.
# The main parser only handles DECORATE 'actor' definitions. ZScript uses
# 'class Name : Parent' syntax which is not parsed into actordb. This pass
# reads ZScript files directly and classifies classes by walking inheritance.
###############################################################################

def detect_zscript_classes(actordb : Array(Actor), actors_by_name : Hash(String, Array(Actor)),
                           weapon_actor_set : Set(String), ammo_actor_set : Set(String),
                           pickup_actor_set : Set(String))
  log(2, "=== ZScript Class Detection ===")

  # Build monster base classes from built-in actors
  monster_base_classes = Set(String).new
  actordb.each do |actor|
    if actor.built_in && (actor.ismonster || actor.monster)
      monster_base_classes.add(actor.name.downcase)
    end
  end
  # Add common base classes that may not be in built-in actors
  {"doomimspecies", "doomimp"}.each { |n| monster_base_classes.add(n) }

  # Collect all ZScript files in Processing/ (including numbered duplicates: ZSCRIPT.1.raw, etc.)
  # Also include root-level ZScript.* files from PK3-extracted mods (e.g. ZScript.Magnum)
  zscript_raw_files = Dir.glob("#{PROCESSING_DIR}/*/defs/ZSCRIPT{,.?*}.raw").map { |p| normalize_path(p) }
  root_zs_files = Dir.glob("#{PROCESSING_DIR}/*/ZSCRIPT.*").map { |p| normalize_path(p) }
    .select { |p| File.file?(p) }  # exclude directories named "zscript"
  zscript_raw_files += root_zs_files
  zscript_raw_files = zscript_raw_files.uniq

  # Data structure: class_name_lc => {name_with_case, parent_lc, file_path, has_monster_flag, has_fire_state}
  zscript_class_info = Hash(String, NamedTuple(
    name_with_case: String,
    parent_lc: String,
    file_path: String,
    has_monster_flag: Bool,
    has_fire_state: Bool,
  )).new

  # ── Parse ZScript files ──────────────────────────────────────────────────
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
          name_with_case:  class_name,
          parent_lc:       parent_name.downcase,
          file_path:       file_path,
          has_monster_flag: has_monster_flag,
          has_fire_state:   has_fire_state,
        }
      end
      i += 1
    end
  end

  log(2, "  ZScript classes found: #{zscript_class_info.size}")

  # ── Classify each ZScript class ──────────────────────────────────────────
  zscript_class_info.each do |class_lc, info|
    # Walk inheritance chain
    is_monster = info[:has_monster_flag]
    is_weapon = false
    is_ammo = false
    is_pickup = false
    pickup_matched_base = ""
    chain_name = info[:parent_lc]
    visited = Set{class_lc}

    while true
      break if visited.includes?(chain_name)  # cycle guard
      visited.add(chain_name)

      if monster_base_classes.includes?(chain_name)
        is_monster = true
        break
      end
      if WEAPON_BASE_CLASSES.includes?(chain_name)
        is_weapon = true
        break
      end
      if AMMO_BASE_CLASSES.includes?(chain_name)
        is_ammo = true
        break
      end
      if PICKUP_BASE_CLASSES.includes?(chain_name)
        is_pickup = true
        pickup_matched_base = chain_name
        break
      end

      # Check if parent is another ZScript class we know about
      parent_info = zscript_class_info[chain_name]?
      if parent_info
        is_monster = true if parent_info[:has_monster_flag]
        chain_name = parent_info[:parent_lc]
      else
        # Check if parent is a known monster/ammo/pickup from actordb (built-in DECORATE actors)
        db_actors = actors_by_name[chain_name]?
        if db_actors
          db_actor = db_actors.first
          if db_actor.ismonster || db_actor.monster
            is_monster = true
          end
          if db_actor.is_ammo
            is_ammo = true
          end
          if db_actor.is_pickup
            is_pickup = true
            pickup_matched_base = chain_name
          end
        end
        break
      end
    end

    # Pickups must not also be weapons or ammo
    if is_pickup && (is_weapon || is_ammo)
      is_pickup = false
    end

    if is_monster || is_weapon || is_ammo || is_pickup
      # Check if this actor already exists in actordb (from DECORATE parsing)
      existing = actors_by_name[class_lc]?
      if existing
        # Actor exists in both DECORATE and ZScript — mark as "both"
        existing.each { |a| a.script_type = "both" }
        if is_ammo
          existing.each { |a| a.is_ammo = true }
          ammo_actor_set.add(class_lc)
        end
        if is_pickup
          existing.each do |a|
            a.is_pickup = true
            if HEALTH_PICKUP_CLASSES.includes?(pickup_matched_base)
              a.pickup_kind = "health"
            elsif ARMOR_PICKUP_CLASSES.includes?(pickup_matched_base)
              a.pickup_kind = "armor"
            elsif POWERUP_PICKUP_CLASSES.includes?(pickup_matched_base)
              a.pickup_kind = "powerup"
            end
          end
          pickup_actor_set.add(class_lc)
        end
        kind = is_monster ? "monster" : (is_weapon ? "weapon" : (is_ammo ? "ammo" : "pickup"))
        log(3, "  ZScript #{kind} (both): #{info[:name_with_case]}")
      else
        # Create a new Actor entry for this ZScript class
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

        # Extract states from ZScript source so DPS estimation works  # helpers.cr
        zs_content = safe_read(info[:file_path])
        # Find this class's body in the file
        if class_md = zs_content.match(/class\s+#{Regex.escape(info[:name_with_case])}\s*[^{]*\{/mi)
          class_start = class_md.end(0).not_nil! - 1  # position of the opening brace
          class_body = extract_balanced_braces(zs_content, class_start)
          if class_body
            states_text = extract_states_text(class_body, info[:name_with_case])
            new_actor.states = parse_states(states_text, info[:name_with_case])
            log(3, "  ZScript states extracted: #{info[:name_with_case]} (#{new_actor.states.keys.join(", ")})")
          end
        end

        if is_monster
          new_actor.ismonster = true
          new_actor.monster = info[:has_monster_flag]
        end
        if is_ammo
          new_actor.is_ammo = true
        end
        if is_pickup
          new_actor.is_pickup = true
          if HEALTH_PICKUP_CLASSES.includes?(pickup_matched_base)
            new_actor.pickup_kind = "health"
          elsif ARMOR_PICKUP_CLASSES.includes?(pickup_matched_base)
            new_actor.pickup_kind = "armor"
          elsif POWERUP_PICKUP_CLASSES.includes?(pickup_matched_base)
            new_actor.pickup_kind = "powerup"
          end
        end

        actordb << new_actor
        actors_by_name[class_lc] ||= [] of Actor
        actors_by_name[class_lc] << new_actor

        if is_weapon
          weapon_actor_set.add(class_lc)
        end
        if is_ammo
          ammo_actor_set.add(class_lc)
        end
        if is_pickup
          pickup_actor_set.add(class_lc)
        end

        kind = is_monster ? "monster" : (is_weapon ? "weapon" : (is_ammo ? "ammo" : "pickup"))
        log(3, "  ZScript #{kind}: #{info[:name_with_case]} (#{info[:file_path]})")
      end
    end
  end

  # Stats
  zs_monster_count = actordb.count { |a| !a.built_in && a.script_type != "decorate" && (a.ismonster || a.monster) }
  zs_weapon_count = actordb.count { |a| !a.built_in && a.script_type != "decorate" && weapon_actor_set.includes?(a.name.downcase) }
  zs_ammo_count = actordb.count { |a| !a.built_in && a.script_type != "decorate" && ammo_actor_set.includes?(a.name.downcase) }
  zs_pickup_count = actordb.count { |a| !a.built_in && a.script_type != "decorate" && pickup_actor_set.includes?(a.name.downcase) }
  log(2, "  ZScript monsters: #{zs_monster_count}, weapons: #{zs_weapon_count}, ammo: #{zs_ammo_count}, pickups: #{zs_pickup_count}")
end
