###############################################################################
# lua_gen.cr — Lua module generation for Obsidian integration
#
# Generates the monster_mash.lua file containing MONSTER_MASH.MONSTERS,
# MONSTER_MASH.WEAPONS tables, control_setup function, and OB_MODULES
# registration with per-actor slider controls.
###############################################################################

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
  slot = actor.weapon.slotnumber

  case slot
  when 1  # Melee (fist/chainsaw)
    {1.0, 10, 30, 10.0}
  when 2  # Pistol class
    {1.0, 15, 35, 15.0}
  when 3  # Shotgun class
    {1.5, 40, 40, 70.0}
  when 4  # Chaingun class
    {2.5, 40, 50, 50.0}
  when 5  # Rocket launcher class
    {4.0, 30, 45, 170.0}
  when 6  # Plasma rifle class
    {5.0, 25, 40, 80.0}
  when 7  # BFG class
    {8.0, 12, 20, 300.0}
  when 8, 9, 0  # Exotic / overflow slots
    {8.0, 12, 20, 300.0}
  else
    # No slot info — estimate from weapon flags and ammo use
    if actor.weapon.bfg
      {8.0, 12, 20, 300.0}
    elsif actor.weapon.meleeweapon
      {1.0, 10, 30, 10.0}
    elsif actor.weapon.ammouse > 5
      {6.0, 20, 30, 150.0}   # High ammo use = powerful
    elsif actor.weapon.ammouse > 1
      {3.0, 35, 45, 80.0}    # Moderate ammo use
    else
      {2.0, 35, 50, 50.0}    # Default — mid-tier
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

# Generate the complete Lua module file for Obsidian integration.
# Writes MONSTER_MASH.MONSTERS, MONSTER_MASH.WEAPONS, and OB_MODULES registration.
def generate_lua_module(actordb : Array(Actor), weapon_actor_set : Set(String))
  log(2, "=== Generating Lua Module ===")

  lua_monster_count = 0
  lua_weapon_count = 0

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
    io << "  for name, info in pairs(MONSTER_MASH.WEAPONS) do\n"
    io << "    local opt = self.options[\"float_weap_\" .. name]\n"
    io << "    if opt then\n"
    io << "      local factor = opt.value\n"
    io << "      if factor then\n"
    io << "        info.add_prob = info.add_prob * factor\n"
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

    # ── MONSTER_MASH.WEAPONS table ──────────────────────────────────────
    io << "MONSTER_MASH.WEAPONS =\n{\n"

    actordb.each do |actor|
      next unless weapon_actor_set.includes?(actor.name.downcase) && actor.doomednum != -1
      next unless should_include_weapon_in_lua(actor)

      attack = detect_weapon_attack_type(actor)
      level, pref, add_prob, damage = weapon_tier(actor)
      ammo_type = map_ammo_type(actor.weapon.ammotype)
      ammo_per = actor.weapon.ammouse > 0 ? actor.weapon.ammouse : 1
      ammo_give = actor.weapon.ammogive > 0 ? actor.weapon.ammogive : 10

      lua_key = actor.name.gsub(/[^a-zA-Z0-9_]/, "_")
      lua_key = "_#{lua_key}" if lua_key[0]?.try(&.ascii_number?)

      io << "  #{lua_key} =\n"
      io << "  {\n"
      io << "    id = #{actor.doomednum},\n"
      io << "    level = #{level},\n"
      io << "    pref = #{pref},\n"
      io << "    add_prob = #{add_prob},\n"
      io << "    attack = \"#{attack}\",\n"
      io << "    rate = 0.9,\n"
      io << "    damage = #{damage},\n"
      io << "    ammo = \"#{ammo_type}\",\n"
      io << "    per = #{ammo_per},\n"
      io << "    give = { {ammo=\"#{ammo_type}\",count=#{ammo_give}} }\n"
      io << "  },\n"
      lua_weapon_count += 1
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

    # ── Weapon slider controls ──────────────────────────────────────────
    actordb.each do |actor|
      next unless weapon_actor_set.includes?(actor.name.downcase) && actor.doomednum != -1
      next unless should_include_weapon_in_lua(actor)
      lua_key = actor.name.gsub(/[^a-zA-Z0-9_]/, "_")
      lua_key = "_#{lua_key}" if lua_key[0]?.try(&.ascii_number?)
      io << "    {\n"
      io << "      name = \"float_weap_#{lua_key}\",\n"
      io << "      label = _(\"#{actor.name_with_case}\"),\n"
      io << "      valuator = \"slider\",\n"
      io << "      min = 0,\n"
      io << "      max = 20,\n"
      io << "      increment = 0.02,\n"
      io << "      default = 0.2,\n"
      io << "      presets = _(\"0:0 (None),0.02:0.02 (Scarce),0.14:0.14 (Less),0.5:0.5 (Plenty),1.2:1.2 (More),3:3 (Heaps),20:20 (INSANE)\"),\n"
      io << "      randomize_group = \"weapons\",\n"
      io << "    },\n"
    end

    io << "  },\n}\n"
  end

  # Write lua output
  lua_output_path = "../modules/monster_mash.lua"
  File.write(lua_output_path, lua)
  log(2, "Lua module written to: #{lua_output_path}")
  log(2, "Lua monsters included: #{lua_monster_count}")
  log(2, "Lua weapons included: #{lua_weapon_count}")

  puts lua if LOG_LEVEL >= 3
end
