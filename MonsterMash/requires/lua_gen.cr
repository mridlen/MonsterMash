###############################################################################
# lua_gen.cr — Lua module generation for Obsidian integration
#
# Generates the monster_mash.lua file containing MONSTER_MASH.MONSTERS,
# MONSTER_MASH.WEAPONS tables, control_setup function, and OB_MODULES
# registration with per-actor slider controls.
###############################################################################

# Determine attack type from DECORATE states
# Returns "melee", "missile", or "hitscan" only (Obsidian's valid attack types).
# If a monster has both Melee and Missile states, "missile" wins (ranged is the
# primary threat, matching how vanilla Doom classifies Imp etc.)
def detect_attack_type(actor : Actor) : String
  has_melee = actor.states.has_key?("melee")
  has_missile = actor.states.has_key?("missile")
  if has_missile
    "missile"
  elsif has_melee
    "melee"
  else
    "missile"  # Default — most custom monsters are ranged
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
  when  501..1000 then {25, 0.6, 50.0}  # Heavy (Baron-class)
  when 1001..2000 then {18, 0.5, 80.0}  # Boss-tier (Cyberdemon-class)
  when 2001..4000 then {12, 0.4, 120.0} # Super-boss
  else                 {7, 0.3, 200.0}  # Ultra-boss (4000+)
  end
end

# Return a sortable tier index and display label for a monster's health.
# Used for grouping monsters by difficulty in OB_MODULES UI headers.
def difficulty_tier_info(health : Int32) : {Int32, String}
  case health
  when     ..60  then {1, "Fodder (0-60 HP)"}
  when   61..200 then {2, "Low-tier (61-200 HP)"}
  when  201..500 then {3, "Mid-tier (201-500 HP)"}
  when  501..1000 then {4, "Heavy (501-1000 HP)"}
  when 1001..2000 then {5, "Boss-tier (1001-2000 HP)"}
  when 2001..4000 then {6, "Super-boss (2001-4000 HP)"}
  else                 {7, "Ultra-boss (4000+ HP)"}
  end
end

# Determine boss_type from health tier and name.
# Returns nil for non-boss monsters (health <= 500).
# Monsters with "rocket" or "bfg" in their name are always "nasty".
def boss_type_for_health(health : Int32, name : String = "") : String?
  lower_name = name.downcase
  if lower_name.includes?("rocket") || lower_name.includes?("bfg")
    return "nasty"
  end

  case health
  when  501..1000 then "minor"   # Baron-class
  when 1001..2000 then "tough"   # Cyberdemon-class
  when 2001..     then "nasty"   # Super-boss / Ultra-boss
  else                 nil        # Not a boss
  end
end

# Determine weapon preferences based on health tier.
# Returns a Lua table string like "{ shotty=1.5, chain=1.3 }".
# Modelled after vanilla Doom monster entries in games/doom/monsters.lua.
# Built-in weapon keys: shotty, chain, super, launch, plasma, bfg
def weap_prefs_for_health(health : Int32) : String
  case health
  when     ..60    # Fodder — any basic weapon works
    "{ shotty=1.2, chain=1.5 }"
  when   61..200   # Low-tier (Imp-class)
    "{ shotty=1.5, chain=1.25, super=1.2 }"
  when  201..500   # Mid-tier (Cacodemon/Revenant-class)
    "{ launch=1.5, super=1.5, chain=1.2, plasma=1.2 }"
  when  501..1000  # Heavy (Baron-class)
    "{ launch=1.75, super=1.5, plasma=1.75, bfg=1.5 }"
  when 1001..2000  # Boss-tier (Cyberdemon-class)
    "{ launch=1.5, plasma=1.5, bfg=10.0 }"
  else             # Super-boss / Ultra-boss (2001+)
    "{ bfg=10.0 }"
  end
end

# Determine how far into an episode a monster should appear (1..9).
# Lower = appears earlier, higher = later in the episode.
# Based on vanilla Doom progression in games/doom/monsters.lua.
def monster_level_for_health(health : Int32) : Float64
  case health
  when     ..60  then 1.0   # Fodder — from the start (zombie, imp)
  when   61..150 then 2.0   # Low-tier (gunner, skull, demon)
  when  151..300 then 4.0   # Mid-tier (revenant, caco)
  when  301..500 then 5.0   # Upper-mid (knight, arach, mancubus)
  when  501..1000 then 6.0  # Heavy / minor boss (baron)
  when 1001..2000 then 7.0  # Boss-tier (Cyberdemon-class)
  when 2001..4000 then 8.0  # Super-boss
  else                 9.0  # Ultra-boss (Spiderdemon-class)
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

# Map DECORATE ammo class names to Obsidian ammo type strings.
# Known Doom/Heretic/Hexen ammo classes get mapped to standard names.
# Unknown classes (custom mod ammo) are passed through lowercased.
AMMO_CLASS_MAP = {
  "clip"           => "bullet",
  "clipbox"        => "bullet",
  "cell"           => "cell",
  "cellpack"       => "cell",
  "shell"          => "shell",
  "shellbox"       => "shell",
  "rocketammo"     => "rocket",
  "rocketbox"      => "rocket",
  # Heretic ammo
  "goldwandammo"   => "bullet",
  "goldwandhemo1"  => "bullet",
  "crossbowammo"   => "shell",
  "blasterammo"    => "cell",
  "skullrodammo"   => "rocket",
  "phoenixrodammo" => "rocket",
  "maborb"         => "cell",
}

def map_ammo_type(ammo_class : String) : String
  return "bullet" if ammo_class == "UNDEFINED" || ammo_class.empty?
  # Strip surrounding quotes — DECORATE stores values like "Clip" with quotes
  key = ammo_class.strip('"').downcase
  AMMO_CLASS_MAP[key]? || key
end

# Detect weapon attack type from Fire state content.
# Checks for known action functions to classify as melee/missile/hitscan.
def detect_weapon_attack_type(actor : Actor) : String
  fire_text = (actor.states["fire"]? || "").downcase
  altfire_text = (actor.states["altfire"]? || "").downcase
  combined = fire_text + " " + altfire_text

  melee_actions = ["a_punch", "a_saw", "a_custompunch", "a_meleeattack",
                   "a_custommeleeattack", "a_extremepunch", "a_sawrefire"]
  missile_actions = ["a_firecustommissile", "a_fireprojectile", "a_launchprojectile",
                     "a_firemissile", "a_firebfg", "a_custommissile"]

  has_melee = melee_actions.any? { |a| combined.includes?(a) }
  has_missile = missile_actions.any? { |a| combined.includes?(a) }

  if has_melee && !has_missile
    "melee"
  elsif has_missile
    "missile"
  else
    "hitscan"  # Default — most modded weapons are hitscan variants
  end
end

# Calculate weapon tier from slot number and weapon properties.
# Doom weapon slots: 1=melee, 2=pistol, 3=shotgun, 4=chaingun, 5=rocket, 6=plasma, 7=BFG
# Returns {level, pref, add_prob, damage_estimate}
def weapon_tier(actor : Actor) : {Float64, Int32, Int32, Float64}
  slot = infer_weapon_slot(actor)  # helpers.cr

  # add_prob values calibrated to vanilla Doom range (20-70) so modded
  # weapons compete fairly in Obsidian's decide_weapon() probability pool.
  # level values staggered within slots to spread new_weapons across levels.
  case slot
  when 1  # Melee (fist/chainsaw)
    {1.0, 5, 15, 10.0}
  when 2  # Pistol class
    {1.2, 7, 20, 15.0}
  when 3  # Shotgun class
    {1.8, 20, 35, 70.0}
  when 4  # Chaingun class
    {3.0, 20, 35, 50.0}
  when 5  # Rocket launcher class
    {4.5, 15, 40, 170.0}
  when 6  # Plasma rifle class
    {5.5, 12, 35, 80.0}
  when 7  # BFG class
    {8.0, 6, 20, 300.0}
  when 8, 9, 0  # Exotic / overflow slots
    {8.0, 6, 20, 300.0}
  else
    # No slot info — estimate from weapon flags and ammo use
    if actor.weapon.bfg
      {8.0, 6, 20, 300.0}
    elsif actor.weapon.meleeweapon
      {1.0, 5, 15, 10.0}
    elsif actor.weapon.ammouse > 5
      {6.5, 10, 30, 150.0}   # High ammo use = powerful
    elsif actor.weapon.ammouse > 1
      {3.5, 17, 35, 80.0}    # Moderate ammo use
    else
      {2.5, 17, 35, 50.0}    # Default — mid-tier
    end
  end
end

# Filter weapons for Lua output — skip sub-weapons and non-functional actors.
def should_include_weapon_in_lua(actor : Actor) : Bool
  return false if actor.doomednum == -1
  return false if actor.weapon.cheatnotweapon
  return false if actor.weapon.powered_up
  return false if actor.weaponpiece.weapon != "UNDEFINED"
  return false unless actor.states.has_key?("fire") || actor.states.has_key?("altfire")
  true
end

# Filter ammo pickups for Lua output — skip actors with no editor number.
def should_include_pickup_in_lua(actor : Actor) : Bool
  return false if actor.doomednum == -1
  true
end

# Calculate health-equivalent give value for armor pickups.
# Armor absorbs damage proportionally, so effective health gain ≈ saveamount * savepercent.
def armor_health_equivalent(actor : Actor) : Int32
  if actor.armor.saveamount > 0 && actor.armor.savepercent > 0
    result = (actor.armor.saveamount * actor.armor.savepercent / 100.0).to_i
    return result < 1 ? 1 : result
  elsif actor.armor.saveamount > 0
    # No savepercent set — assume ~50% absorption
    half = actor.armor.saveamount // 2
    return half < 1 ? 1 : half
  elsif actor.inventory.amount > 0
    return actor.inventory.amount
  end
  10 # fallback default
end

# Parse powerup duration string to seconds. Returns nil if infinite or unset.
def parse_powerup_duration(duration_str : String) : Int32?
  return nil if duration_str == "0" || duration_str == "UNDEFINED"

  # Handle hex values (e.g., "0x7FFFFFFD")
  seconds = if duration_str =~ /^-?0x/i
               duration_str.to_i(prefix: true) rescue nil
             else
               duration_str.to_i rescue nil
             end

  return nil if seconds.nil?

  # Absolute value — negative means "seconds active" per ZDoom docs
  seconds = seconds.abs

  # Very large values (0x7FFFFFFD etc.) are effectively infinite
  return nil if seconds > 999999

  return nil if seconds == 0

  seconds
end

# Generate the complete Lua module file for Obsidian integration.
# Writes MONSTER_MASH.MONSTERS, MONSTER_MASH.WEAPONS, MONSTER_MASH.PICKUPS,
# and OB_MODULES registration.
def generate_lua_module(actordb : Array(Actor), weapon_actor_set : Set(String), ammo_actor_set : Set(String), pickup_actor_set : Set(String))
  log(2, "=== Generating Lua Module ===")

  lua_monster_count = 0
  lua_ally_count = 0
  lua_weapon_count = 0
  lua_ammo_count = 0
  lua_pickup_count = 0

  lua = String.build do |io|
    io << "----------------------------------------------------------------\n"
    io << "--  Monster Mash — Obsidian Module (auto-generated by Unwad)  --\n"
    io << "----------------------------------------------------------------\n\n"
    io << "MONSTER_MASH = { }\n\n"

    # Note: everything MUST get float_<name> because that is how
    #       Obsidian works. Using float_somethingelse_<name> will break
    #       functionality. That's how the actors are referenced.

    # ── control_setup function ──────────────────────────────────────────
    io << "function MONSTER_MASH.control_setup(self)\n"
    io << "  -- Load slider values into PARAM[] (same as ctl_doom.lua)\n"
    io << "  module_param_up(self)\n"
    io << "\n"
    io << "  -- Apply slider factors to GAME.* tables (the deep copies Obsidian reads)\n"
    io << "  for _,opt in pairs(self.options) do\n"
    io << "    local name = string.sub(opt.name, 7)\n"
    io << "    local factor = PARAM[opt.name]\n"
    io << "    if factor and type(factor) == \"number\" then\n"
    io << "      -- Monsters\n"
    io << "      local M = GAME.MONSTERS and GAME.MONSTERS[name]\n"
    io << "      if M then\n"
    io << "        M.prob = M.prob * factor\n"
    io << "        M.density = M.density * factor\n"
    io << "      end\n"
    io << "      -- Weapons\n"
    io << "      local W = GAME.WEAPONS and GAME.WEAPONS[name]\n"
    io << "      if W then\n"
    io << "        W.add_prob = W.add_prob * factor\n"
    io << "      end\n"
    io << "      -- Pickups\n"
    io << "      local P = GAME.PICKUPS and GAME.PICKUPS[name]\n"
    io << "      if P and P.add_prob then\n"
    io << "        P.add_prob = P.add_prob * factor\n"
    io << "      end\n"
    io << "    end\n"
    io << "  end\n"
    io << "end\n\n"

    # ── MONSTER_MASH.MONSTERS table ────────────────────────────────────
    io << "MONSTER_MASH.MONSTERS =\n{\n"

    # Sort monsters by difficulty tier, then alphabetically (case-insensitive) within each tier
    sorted_monsters = actordb.select { |a| (a.ismonster || a.monster) && a.doomednum != -1 && should_include_in_lua(a) && !a.friendly }
      .sort_by { |a| {difficulty_tier_info(a.health)[0], a.name.downcase} }

    sorted_monsters.each do |actor|

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

      # [FEATURE] Add source WAD as a comment for traceability (formerranger2 bug)
      source_comment = actor.source_wad_folder != "UNDEFINED" ? "  -- source: #{actor.source_wad_folder}" : ""
      io << "  #{lua_key} =#{source_comment}\n"
      io << "  {\n"
      io << "    id = #{actor.doomednum},\n"
      io << "    r = #{actor.radius.to_i},\n"
      io << "    h = #{actor.height},\n"
      io << "    level = #{monster_level_for_health(actor.health)},\n"
      io << "    prob = #{prob},\n"
      io << "    health = #{actor.health},\n"
      io << "    damage = #{damage},\n"
      io << "    attack = \"#{attack}\",\n"
      io << "    density = #{density},\n"
      io << "    weap_prefs = #{weap_prefs_for_health(actor.health)},\n"
      boss_type = boss_type_for_health(actor.health, actor.name)
      if boss_type
        io << "    boss_type = \"#{boss_type}\",\n"
        io << "    boss_prob = 50,\n"
      end
      io << "  },\n"
      lua_monster_count += 1
    end

    io << "}\n\n"

    # ── MONSTER_MASH.ALLIES table ─────────────────────────────────────
    io << "MONSTER_MASH.ALLIES =\n{\n"

    # Sort allies by difficulty tier, then alphabetically (case-insensitive) within each tier
    sorted_allies = actordb.select { |a| (a.ismonster || a.monster) && a.doomednum != -1 && should_include_in_lua(a) && a.friendly }
      .sort_by { |a| {difficulty_tier_info(a.health)[0], a.name.downcase} }

    sorted_allies.each do |actor|

      attack = detect_attack_type(actor)
      prob, density, damage = difficulty_tier(actor.health)

      if actor.float || actor.nogravity
        prob = (prob * 0.8).to_i
        prob = 1 if prob < 1
      end

      lua_key = actor.name.gsub(/[^a-zA-Z0-9_]/, "_")
      lua_key = "_#{lua_key}" if lua_key[0]?.try(&.ascii_number?)

      source_comment = actor.source_wad_folder != "UNDEFINED" ? "  -- source: #{actor.source_wad_folder}" : ""
      io << "  #{lua_key} =#{source_comment}\n"
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
      lua_ally_count += 1
    end

    io << "}\n\n"

    # ── MONSTER_MASH.WEAPONS table ──────────────────────────────────────
    io << "MONSTER_MASH.WEAPONS =\n{\n"

    # Sort weapons by slot number (using infer_weapon_slot from helpers.cr),
    # then alphabetically (case-insensitive) within each slot
    sorted_weapons = actordb.select { |a| weapon_actor_set.includes?(a.name.downcase) && a.doomednum != -1 && should_include_weapon_in_lua(a) }
      .sort_by { |a| {infer_weapon_slot(a), a.name.downcase} }

    sorted_weapons.each do |actor|

      attack = detect_weapon_attack_type(actor)
      level, pref, add_prob, tier_damage = weapon_tier(actor)

      # Calculate damage from Fire state actions — fallback to tier estimate
      # requires/weapon_damage_calc.cr
      calc_damage = calculate_weapon_damage(actor, actordb)
      damage = calc_damage > 0 ? calc_damage : tier_damage

      # Calculate rate from Fire state ticks — fallback to 0.9
      # requires/weapon_damage_calc.cr
      fire_text = actor.states["fire"]? || ""
      calc_rate = calculate_fire_rate(fire_text)
      rate = calc_rate > 0 ? calc_rate : 0.9

      ammo_type = map_ammo_type(actor.weapon.ammotype)
      ammo_per = actor.weapon.ammouse > 0 ? actor.weapon.ammouse : 1
      ammo_give = actor.weapon.ammogive > 0 ? actor.weapon.ammogive : 10

      lua_key = actor.name.gsub(/[^a-zA-Z0-9_]/, "_")
      lua_key = "_#{lua_key}" if lua_key[0]?.try(&.ascii_number?)

      # [FEATURE] Add source WAD as a comment for traceability (formerranger2 bug)
      source_comment = actor.source_wad_folder != "UNDEFINED" ? "  -- source: #{actor.source_wad_folder}" : ""
      io << "  #{lua_key} =#{source_comment}\n"
      io << "  {\n"
      io << "    id = #{actor.doomednum},\n"
      io << "    level = #{level},\n"
      io << "    pref = #{pref},\n"
      io << "    add_prob = #{add_prob},\n"
      io << "    attack = \"#{attack}\",\n"
      io << "    rate = #{rate.round(2)},\n"
      io << "    damage = #{damage.round(1)},\n"
      io << "    ammo = \"#{ammo_type}\",\n"
      io << "    per = #{ammo_per},\n"
      io << "    give = { {ammo=\"#{ammo_type}\",count=#{ammo_give}} }\n"
      io << "  },\n"
      lua_weapon_count += 1
    end

    io << "}\n\n"

    # ── MONSTER_MASH.PICKUPS table ────────────────────────────────────
    # Contains both ammo and non-ammo pickups so Obsidian can spawn them
    io << "MONSTER_MASH.PICKUPS =\n{\n"

    # Ammo pickups — sorted alphabetically (case-insensitive)
    sorted_ammo = actordb.select { |a| ammo_actor_set.includes?(a.name.downcase) && a.doomednum != -1 && should_include_pickup_in_lua(a) }
      .sort_by { |a| a.name.downcase }

    sorted_ammo.each do |actor|

      # Ammo type: use map_ammo_type so the string matches what weapons reference
      ammo_type = map_ammo_type(actor.name)

      # Amount: use inventory.amount if set, otherwise default to 10
      amount = actor.inventory.amount > 0 ? actor.inventory.amount : 10

      # Sanitize name for Lua key
      lua_key = actor.name.gsub(/[^a-zA-Z0-9_]/, "_")
      lua_key = "_#{lua_key}" if lua_key[0]?.try(&.ascii_number?)

      source_comment = actor.source_wad_folder != "UNDEFINED" ? "  -- source: #{actor.source_wad_folder}" : ""
      io << "  #{lua_key} =#{source_comment}\n"
      io << "  {\n"
      io << "    id = #{actor.doomednum},\n"
      io << "    kind = \"ammo\",\n"
      io << "    rank = 2,\n"
      io << "    add_prob = 60,\n"
      io << "    give = { {ammo=\"#{ammo_type}\",count=#{amount}} },\n"
      io << "    cluster = { 4,9 },\n"
      io << "  },\n"
      lua_ammo_count += 1
    end

    # Non-ammo pickups: health, armor, powerup, other — sorted alphabetically (case-insensitive)
    sorted_pickups = actordb.select { |a| pickup_actor_set.includes?(a.name.downcase) && a.doomednum != -1 && should_include_pickup_in_lua(a) }
      .sort_by { |a| a.name.downcase }

    sorted_pickups.each do |actor|

      kind = actor.pickup_kind
      lua_key = actor.name.gsub(/[^a-zA-Z0-9_]/, "_")
      lua_key = "_#{lua_key}" if lua_key[0]?.try(&.ascii_number?)

      source_comment = actor.source_wad_folder != "UNDEFINED" ? "  -- source: #{actor.source_wad_folder}" : ""
      io << "  #{lua_key} =#{source_comment}\n"
      io << "  {\n"
      io << "    id = #{actor.doomednum},\n"
      io << "    kind = \"#{kind}\",\n"
      io << "    rank = 2,\n"

      case kind
      when "health"
        health_amount = actor.inventory.amount > 0 ? actor.inventory.amount : 10
        io << "    add_prob = 10,\n"
        io << "    give = { {health=#{health_amount}} }\n"
      when "armor"
        health_equiv = armor_health_equivalent(actor)
        io << "    add_prob = 7,\n"
        io << "    give = { {health=#{health_equiv}} }\n"
      when "powerup"
        io << "    add_prob = 2,\n"
        duration = parse_powerup_duration(actor.powerup.duration)
        if duration
          io << "    time_limit = #{duration},\n"
        end
      else # "other"
        io << "    add_prob = 5,\n"
        other_amount = actor.inventory.amount > 0 ? actor.inventory.amount : 5
        io << "    give = { {health=#{other_amount}} }\n"
      end

      io << "  },\n"
      lua_pickup_count += 1
    end

    io << "}\n\n"

    # ── OB_MODULES registration: Monsters ──────────────────────────────
    io << "OB_MODULES[\"monster_mash_monsters\"] =\n{\n"
    io << "  name = \"monster_mash_monsters_control\",\n"
    io << "  label = _(\"Monster Mash Monsters\"),\n"
    io << "  game = \"doomish\",\n"
    io << "  port = \"zdoom\",\n"
    io << "  where = \"combat\",\n"
    io << "  tables =\n  {\n    MONSTER_MASH\n  },\n"
    io << "  hooks =\n  {\n    setup = MONSTER_MASH.control_setup\n  },\n"
    io << "  options =\n  {\n"

    # Reuse sorted_monsters from the data table above — grouped by difficulty tier with headers
    current_tier = -1
    sorted_monsters.each do |actor|
      # Emit tier header when entering a new difficulty group
      tier_index, tier_label = difficulty_tier_info(actor.health)
      if tier_index != current_tier
        current_tier = tier_index
        io << "    {\n"
        io << "      name = \"header_monstertier#{current_tier}\",\n"
        io << "      label = _(\"#{tier_label}\"),\n"
        io << "    },\n"
      end

      lua_key = actor.name.gsub(/[^a-zA-Z0-9_]/, "_")
      lua_key = "_#{lua_key}" if lua_key[0]?.try(&.ascii_number?)
      slider_default = actor.slider_zero ? 0 : 1
      io << "    {\n"
      io << "      name = \"float_#{lua_key}\",\n"
      io << "      label = _(\"#{actor.name_with_case}\"),\n"
      io << "      valuator = \"slider\",\n"
      io << "      min = 0,\n"
      io << "      max = 20,\n"
      io << "      increment = 0.02,\n"
      io << "      default = #{slider_default},\n"
      if actor.slider_zero
        io << "      tooltip = _(\"slider disabled in configuration\"),\n"
      end
      io << "      presets = _(\"0:0 (None),0.02:0.02 (Scarce),0.14:0.14 (Less),0.5:0.5 (Plenty),1.2:1.2 (More),3:3 (Heaps),20:20 (INSANE)\"),\n"
      io << "      randomize_group = \"monsters\",\n"
      io << "    },\n"
    end

    io << "  },\n}\n\n"

    # ── OB_MODULES registration: Allies ──────────────────────────────
    io << "OB_MODULES[\"monster_mash_allies\"] =\n{\n"
    io << "  name = \"monster_mash_allies_control\",\n"
    io << "  label = _(\"Monster Mash Allies\"),\n"
    io << "  game = \"doomish\",\n"
    io << "  port = \"zdoom\",\n"
    io << "  where = \"combat\",\n"
    io << "  tables =\n  {\n    MONSTER_MASH\n  },\n"
    io << "  hooks =\n  {\n    setup = MONSTER_MASH.control_setup\n  },\n"
    io << "  options =\n  {\n"

    # Reuse sorted_allies from the data table above — grouped by difficulty tier with headers
    current_tier = -1
    sorted_allies.each do |actor|
      # Emit tier header when entering a new difficulty group
      tier_index, tier_label = difficulty_tier_info(actor.health)
      if tier_index != current_tier
        current_tier = tier_index
        io << "    {\n"
        io << "      name = \"header_allytier#{current_tier}\",\n"
        io << "      label = _(\"#{tier_label}\"),\n"
        io << "    },\n"
      end

      lua_key = actor.name.gsub(/[^a-zA-Z0-9_]/, "_")
      lua_key = "_#{lua_key}" if lua_key[0]?.try(&.ascii_number?)
      slider_default = actor.slider_zero ? 0 : 1
      io << "    {\n"
      io << "      name = \"float_#{lua_key}\",\n"
      io << "      label = _(\"#{actor.name_with_case}\"),\n"
      io << "      valuator = \"slider\",\n"
      io << "      min = 0,\n"
      io << "      max = 20,\n"
      io << "      increment = 0.02,\n"
      io << "      default = #{slider_default},\n"
      if actor.slider_zero
        io << "      tooltip = _(\"slider disabled in configuration\"),\n"
      end
      io << "      presets = _(\"0:0 (None),0.02:0.02 (Scarce),0.14:0.14 (Less),0.5:0.5 (Plenty),1.2:1.2 (More),3:3 (Heaps),20:20 (INSANE)\"),\n"
      io << "      randomize_group = \"allies\",\n"
      io << "    },\n"
    end

    io << "  },\n}\n\n"

    # ── OB_MODULES registration: Ammo ───────────────────────────────
    io << "OB_MODULES[\"monster_mash_ammo\"] =\n{\n"
    io << "  name = \"monster_mash_ammo_control\",\n"
    io << "  label = _(\"Monster Mash Ammo\"),\n"
    io << "  game = \"doomish\",\n"
    io << "  port = \"zdoom\",\n"
    io << "  where = \"pickup\",\n"
    io << "  tables =\n  {\n    MONSTER_MASH\n  },\n"
    io << "  hooks =\n  {\n    setup = MONSTER_MASH.control_setup\n  },\n"
    io << "  options =\n  {\n"

    # Reuse sorted_ammo from the data table above
    sorted_ammo.each do |actor|
      lua_key = actor.name.gsub(/[^a-zA-Z0-9_]/, "_")
      lua_key = "_#{lua_key}" if lua_key[0]?.try(&.ascii_number?)
      slider_default = actor.slider_zero ? 0 : 10
      io << "    {\n"
      io << "      name = \"float_#{lua_key}\",\n"
      io << "      label = _(\"#{actor.name_with_case}\"),\n"
      io << "      valuator = \"slider\",\n"
      io << "      min = 0,\n"
      io << "      max = 20,\n"
      io << "      increment = 0.02,\n"
      io << "      default = #{slider_default},\n"
      if actor.slider_zero
        io << "      tooltip = _(\"slider disabled in configuration\"),\n"
      end
      io << "      presets = _(\"0:0 (None),0.02:0.02 (Scarce),0.14:0.14 (Less),0.5:0.5 (Plenty),1.2:1.2 (More),3:3 (Heaps),20:20 (INSANE)\"),\n"
      io << "      randomize_group = \"pickups\",\n"
      io << "    },\n"
    end

    io << "  },\n}\n\n"


    # ── OB_MODULES registration: Pickups ─────────────────────────────
    io << "OB_MODULES[\"monster_mash_pickups\"] =\n{\n"
    io << "  name = \"monster_mash_pickups_control\",\n"
    io << "  label = _(\"Monster Mash Pickups\"),\n"
    io << "  game = \"doomish\",\n"
    io << "  port = \"zdoom\",\n"
    io << "  where = \"pickup\",\n"
    io << "  tables =\n  {\n    MONSTER_MASH\n  },\n"
    io << "  hooks =\n  {\n    setup = MONSTER_MASH.control_setup\n  },\n"
    io << "  options =\n  {\n"

    # Reuse sorted_pickups from the data table above
    sorted_pickups.each do |actor|
      lua_key = actor.name.gsub(/[^a-zA-Z0-9_]/, "_")
      lua_key = "_#{lua_key}" if lua_key[0]?.try(&.ascii_number?)
      slider_default = actor.slider_zero ? 0 : 0.3
      io << "    {\n"
      io << "      name = \"float_#{lua_key}\",\n"
      io << "      label = _(\"#{actor.name_with_case}\"),\n"
      io << "      valuator = \"slider\",\n"
      io << "      min = 0,\n"
      io << "      max = 20,\n"
      io << "      increment = 0.02,\n"
      io << "      default = #{slider_default},\n"
      if actor.slider_zero
        io << "      tooltip = _(\"slider disabled in configuration\"),\n"
      end
      io << "      presets = _(\"0:0 (None),0.02:0.02 (Scarce),0.14:0.14 (Less),0.5:0.5 (Plenty),1.2:1.2 (More),3:3 (Heaps),20:20 (INSANE)\"),\n"
      io << "      randomize_group = \"pickups\",\n"
      io << "    },\n"
    end

    io << "  },\n}\n\n"

    # ── OB_MODULES registration: Weapons ─────────────────────────────
    io << "OB_MODULES[\"monster_mash_weapons\"] =\n{\n"
    io << "  name = \"monster_mash_weapons_control\",\n"
    io << "  label = _(\"Monster Mash Weapons\"),\n"
    io << "  game = \"doomish\",\n"
    io << "  port = \"zdoom\",\n"
    io << "  where = \"pickup\",\n"
    io << "  tables =\n  {\n    MONSTER_MASH\n  },\n"
    io << "  hooks =\n  {\n    setup = MONSTER_MASH.control_setup\n  },\n"
    io << "  options =\n  {\n"

    # Reuse sorted_weapons from the data table above — grouped by slot with headers
    current_slot = -999  # sentinel so first weapon always triggers a header
    sorted_weapons.each do |actor|
      # Emit slot header when entering a new slot group
      weapon_slot = infer_weapon_slot(actor)  # helpers.cr
      if weapon_slot != current_slot
        current_slot = weapon_slot
        io << "    {\n"
        io << "      name = \"header_slotnumber#{current_slot}\",\n"
        io << "      label = _(\"Slot Number #{current_slot}\"),\n"
        io << "    },\n"
      end

      lua_key = actor.name.gsub(/[^a-zA-Z0-9_]/, "_")
      lua_key = "_#{lua_key}" if lua_key[0]?.try(&.ascii_number?)
      slider_default = 0  # All weapons default to 0 — user selects their own loadout
      # Note: SliderZero behavior preserved via actor.slider_zero for future revert
      io << "    {\n"
      io << "      name = \"float_#{lua_key}\",\n"
      io << "      label = _(\"#{actor.name_with_case}\"),\n"
      io << "      valuator = \"slider\",\n"
      io << "      min = 0,\n"
      io << "      max = 20,\n"
      io << "      increment = 0.02,\n"
      io << "      default = #{slider_default},\n"
      if actor.slider_zero
        io << "      tooltip = _(\"slider disabled in configuration\"),\n"
      end
      io << "      presets = _(\"0:0 (None),0.02:0.02 (Scarce),0.14:0.14 (Less),0.5:0.5 (Plenty),1.2:1.2 (More),3:3 (Heaps),20:20 (INSANE)\"),\n"
      io << "      randomize_group = \"pickups\",\n"
      io << "    },\n"
    end

    io << "  },\n}\n"
  end

  # Write lua output
  lua_output_path = "../modules/monster_mash.lua"
  File.write(lua_output_path, lua)
  log(2, "Lua module written to: #{lua_output_path}")
  log(2, "Lua monsters included: #{lua_monster_count}")
  log(2, "Lua allies included: #{lua_ally_count}")
  log(2, "Lua weapons included: #{lua_weapon_count}")
  log(2, "Lua ammo included: #{lua_ammo_count}")
  log(2, "Lua pickups included: #{lua_pickup_count}")

  puts lua if Config.log_level >= 3
end
