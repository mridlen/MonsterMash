###############################################################################
# weapon_damage_calc.cr — Calculate weapon damage and fire rate from DECORATE
#
# Parses the Fire state text to determine:
#   1. Fire rate (shots per second) from tick counts
#   2. Per-shot damage from action functions (hitscan, melee, projectile)
#
# Falls back to 0.0 when parsing fails, so callers can use tier-based defaults.
###############################################################################

# Doom engine runs at 35 ticks per second
DOOM_TICS_PER_SECOND = 35.0

# ── Damage Expression Parsing ────────────────────────────────────────────────

# Parse a DECORATE damage expression into a numeric value.
# Handles integers, parenthesized values, random(), and simple arithmetic.
# Returns 0.0 if the expression can't be parsed.
#
# Examples:
#   "30"               → 30.0
#   "(30)"             → 30.0
#   "random(4,16)"     → 10.0  (median)
#   "20+random(4,16)"  → 30.0
#   "5*random(1,8)"    → 22.5
def parse_damage_expression(expr : String) : Float64
  return 0.0 if expr.empty?

  # Strip whitespace and outer parentheses
  clean = expr.strip
  while clean.starts_with?("(") && clean.ends_with?(")")
    inner = clean[1..-2]
    # Only strip if balanced
    depth = 0
    balanced = true
    inner.each_char do |c|
      if c == '('
        depth += 1
      elsif c == ')'
        depth -= 1
        if depth < 0
          balanced = false
          break
        end
      end
    end
    break unless balanced && depth == 0
    clean = inner.strip
  end

  return 0.0 if clean.empty?

  # Pure integer
  if clean =~ /^-?\d+$/
    return clean.to_f64
  end

  # Pure float
  if clean =~ /^-?\d+\.\d+$/
    return clean.to_f64
  end

  # Standalone random(a, b) → median (a+b)/2
  if md = clean.match(/^random\s*\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)$/i)
    a = md[1].to_f64
    b = md[2].to_f64
    return (a + b) / 2.0
  end

  # N + random(a, b)
  if md = clean.match(/^(-?\d+(?:\.\d+)?)\s*\+\s*random\s*\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)$/i)
    n = md[1].to_f64
    a = md[2].to_f64
    b = md[3].to_f64
    return n + (a + b) / 2.0
  end

  # random(a, b) + N
  if md = clean.match(/^random\s*\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)\s*\+\s*(-?\d+(?:\.\d+)?)$/i)
    a = md[1].to_f64
    b = md[2].to_f64
    n = md[3].to_f64
    return (a + b) / 2.0 + n
  end

  # N * random(a, b)
  if md = clean.match(/^(-?\d+(?:\.\d+)?)\s*\*\s*random\s*\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)$/i)
    n = md[1].to_f64
    a = md[2].to_f64
    b = md[3].to_f64
    return n * (a + b) / 2.0
  end

  # random(a, b) * N
  if md = clean.match(/^random\s*\(\s*(-?\d+)\s*,\s*(-?\d+)\s*\)\s*\*\s*(-?\d+(?:\.\d+)?)$/i)
    a = md[1].to_f64
    b = md[2].to_f64
    n = md[3].to_f64
    return (a + b) / 2.0 * n
  end

  # Fallback: try to grab any leading integer
  if md = clean.match(/^(-?\d+)/)
    return md[1].to_f64
  end

  0.0
end

# ── Tick Counting ─────────────────────────────────────────────────────────────

# Count total ticks in a Fire state text block.
# Each DECORATE state line: SPRT FRAMES DURATION [action]
# Multi-frame shorthand: SPRT ABCDE 3 = 5 frames × 3 ticks = 15 ticks
# Stops counting at Goto, Loop, Stop, or a new label definition.
# Returns 0 if parsing fails.
def count_fire_state_ticks(fire_state_text : String) : Int32
  total_ticks = 0

  fire_state_text.each_line do |raw_line|
    line = raw_line.strip
    next if line.empty?
    next if line.starts_with?("//")  # Skip comments

    lc = line.downcase

    # Stop at flow control or new labels
    break if lc.starts_with?("goto ")
    break if lc.starts_with?("loop")
    break if lc.starts_with?("stop")
    break if lc.starts_with?("wait")
    # New label definition (word followed by colon at start of line)
    break if line =~ /^[a-zA-Z_]\w*\s*:/

    # Match DECORATE state line: SPRITE FRAMES DURATION [action...]
    # Sprite can be 4 chars, "####", "----", or quoted "####"
    # Frames can be letters like ABCDE, or "#", or quoted "#"
    if md = line.match(/^(?:"[^"]*"|[A-Za-z0-9_#\-]{4})\s+(?:"([^"]*)"|([A-Za-z0-9#\[\]\\]+))\s+(-?\d+)/i)
      frames_str = md[1]? || md[2]? || ""
      duration = md[3].to_i

      # Count number of frames
      num_frames = frames_str.size
      num_frames = 1 if num_frames == 0

      # Check for A_SetTics override on this line
      if tic_md = line.match(/a_settics\s*\(\s*(\d+)\s*\)/i)
        duration = tic_md[1].to_i
      end

      # Only count positive durations
      if duration > 0
        total_ticks += num_frames * duration
      end
    end
  end

  total_ticks
end

# ── Fire Rate Calculation ─────────────────────────────────────────────────────

# Calculate fire rate (shots per second) from Fire state ticks.
# Returns 0.0 if ticks can't be determined (triggers fallback in caller).
def calculate_fire_rate(fire_state_text : String) : Float64
  ticks = count_fire_state_ticks(fire_state_text)
  return 0.0 if ticks <= 0
  DOOM_TICS_PER_SECOND / ticks.to_f64
end

# ── Projectile Damage Lookup ─────────────────────────────────────────────────

# Look up a projectile actor by name in the actordb and return its damage.
# Checks the actor's "damage" property and "explosion_damage".
# Returns 0.0 if the projectile can't be found.
def lookup_projectile_damage(projectile_name : String, actordb : Array(Actor)) : Float64
  return 0.0 if projectile_name.empty?

  # Strip quotes from projectile name
  clean_name = projectile_name.strip.strip('"').strip('\'')
  return 0.0 if clean_name.empty?

  # Search actordb for the projectile (case-insensitive)
  target_lc = clean_name.downcase
  proj_actor = actordb.find { |a| a.name.downcase == target_lc }
  return 0.0 if proj_actor.nil?

  # Parse the projectile's damage property
  damage = parse_damage_expression(proj_actor.damage)

  # Add explosion_damage if present
  if proj_actor.explosion_damage > 0
    damage += proj_actor.explosion_damage.to_f64
  end

  damage
end

# ── Action Function Argument Extraction ──────────────────────────────────────

# Extract the argument list from an action function call.
# e.g. "A_FireBullets(3, 5, 9, 6, \"BulletPuff\", 1)" → "3, 5, 9, 6, \"BulletPuff\", 1"
# Returns nil if no parenthesized args found.
def extract_action_args(line : String, function_name : String) : String?
  lc_line = line.downcase
  lc_func = function_name.downcase

  idx = lc_line.index(lc_func)
  return nil unless idx

  # Find the opening paren after the function name
  paren_start = line.index('(', idx + function_name.size)
  return nil unless paren_start

  # Find matching closing paren (handle nesting)
  depth = 1
  pos = paren_start + 1
  while pos < line.size && depth > 0
    if line[pos] == '('
      depth += 1
    elsif line[pos] == ')'
      depth -= 1
    end
    pos += 1 if depth > 0
    pos += 1 if depth == 0
  end

  return nil if depth != 0
  # pos is now one past the closing paren
  line[(paren_start + 1)..(pos - 2)].strip
end

# Split a comma-separated argument string, respecting parentheses.
# "3, 5, random(1,3), \"BulletPuff\"" → ["3", "5", "random(1,3)", "\"BulletPuff\""]
def split_action_args(args_str : String) : Array(String)
  result = [] of String
  current = ""
  depth = 0

  args_str.each_char do |c|
    if c == '(' || c == '['
      depth += 1
      current += c
    elsif c == ')' || c == ']'
      depth -= 1
      current += c
    elsif c == ',' && depth == 0
      result << current.strip
      current = ""
    else
      current += c
    end
  end
  result << current.strip unless current.strip.empty?
  result
end

# ── Main Damage Calculation ──────────────────────────────────────────────────

# Hardcoded damage values for vanilla action functions (no arguments needed).
VANILLA_DAMAGE = {
  "a_punch"         => 10.0,   # Fist: 2-20 median
  "a_saw"           =>  4.0,   # Chainsaw: 2-20 per hit, very fast
  "a_firepistol"    => 10.0,   # Pistol: 5*random(1,3) median
  "a_fireshotgun"   => 70.0,   # Shotgun: 7 pellets × 5 × 2
  "a_fireshotgun2"  => 150.0,  # SSG: 20 pellets × 5 × 1.5
  "a_firecgun"      => 10.0,   # Chaingun: 5*random(1,3) median
  "a_firemissile"   => 170.0,  # Rocket launcher
  "a_fireplasma"    => 22.0,   # Plasma: 5*random(1,8) median
  "a_firebfg"       => 640.0,  # BFG9000
  "a_fireoldbfg"    => 640.0,  # Old BFG
  "a_firerailgun"   => 150.0,  # Railgun
  # Heretic weapons
  "a_firegoldwandpl1" => 10.0,
  "a_firegoldwandpl2" => 15.0,
  "a_firecrossbowpl1" => 10.0,
  "a_firecrossbowpl2" => 20.0,
  "a_fireblasterpl1"  => 12.0,
  "a_fireskullrodpl1" => 15.0,
  "a_fireskullrodpl2" => 40.0,
  "a_firephoenixpl1"  => 40.0,
  "a_firephoenixpl2"  => 30.0,
  "a_initphoenixpl2"  => 30.0,
  "a_shutdownphoenixpl2" => 0.0,
  "a_firemacepl1"    => 25.0,
  "a_firemacepl2"    => 50.0,
  "a_firearrow"      => 10.0,
  "a_beakattackpl1"  => 5.0,
  "a_beakattackpl2"  => 10.0,
  "a_gauntletattack"  => 8.0,
  "a_staffattack"    => 8.0,
  "a_cstaffattack"   => 15.0,
  "a_cstaffcheck"    => 0.0,
  # Strife weapons
  "a_firemauler1"    => 80.0,
  "a_firemauler2"    => 100.0,
  "a_firemauler2pre" => 0.0,
  "a_fireassaultgun" => 10.0,
  "a_firestgrenade"  => 100.0,
  "a_firegrenade"    => 100.0,
  "a_jabdagger"      => 10.0,
  "a_fpunchattack"   => 40.0,
  "a_snoutattack"    => 5.0,
  "a_blast"          => 0.0,
  # Railgun variants
  "a_firerailgunleft"  => 150.0,
  "a_firerailgunright" => 150.0,
}

# Calculate weapon damage by parsing the Fire state for action functions.
# Checks Fire state first, then AltFire if Fire yields nothing.
# Returns 0.0 if damage can't be determined (triggers tier-based fallback).
def calculate_weapon_damage(actor : Actor, actordb : Array(Actor)) : Float64
  damage = 0.0

  fire_text = actor.states["fire"]? || ""
  damage = parse_fire_state_for_damage(fire_text, actordb)

  # If Fire state yielded no damage, try AltFire
  if damage <= 0.0
    altfire_text = actor.states["altfire"]? || ""
    damage = parse_fire_state_for_damage(altfire_text, actordb)
  end

  damage
end

# Parse a single state block (Fire or AltFire) for damage-dealing actions.
# Returns the total damage per firing cycle.
def parse_fire_state_for_damage(state_text : String, actordb : Array(Actor)) : Float64
  return 0.0 if state_text.empty?

  total_damage = 0.0

  state_text.each_line do |raw_line|
    line = raw_line.strip
    next if line.empty?
    next if line.starts_with?("//")

    lc = line.downcase

    # Stop at flow control
    break if lc.starts_with?("goto ")
    break if lc.starts_with?("loop")
    break if lc.starts_with?("stop")
    break if lc.starts_with?("wait")
    break if line =~ /^[a-zA-Z_]\w*\s*:/

    # ── A_FireBullets ────────────────────────────────────────────────
    # A_FireBullets(hspread, vspread, numbullets, damageperbullet, ...)
    # Each bullet does: damageperbullet * random(1,3), median multiplier = 2
    if lc.includes?("a_firebullets")
      args_str = extract_action_args(line, "A_FireBullets")
      if args_str
        args = split_action_args(args_str)
        if args.size >= 4
          num_bullets = parse_damage_expression(args[2])
          # -1 or 0 means single accurate shot
          num_bullets = 1.0 if num_bullets <= 0
          damage_per = parse_damage_expression(args[3])
          # Each bullet: damage * random(1,3), median = 2
          total_damage += num_bullets * damage_per * 2.0
        end
      end
      next
    end

    # ── A_CustomPunch ────────────────────────────────────────────────
    # A_CustomPunch(damage, [norandom, [flags, [pufftype, [range]]]])
    if lc.includes?("a_custompunch")
      args_str = extract_action_args(line, "A_CustomPunch")
      if args_str
        args = split_action_args(args_str)
        if args.size >= 1
          dmg = parse_damage_expression(args[0])
          # Check norandom flag (2nd arg) — if true, no random multiplier
          norandom = false
          if args.size >= 2
            norandom = args[1].strip == "1" || args[1].strip.downcase == "true"
          end
          total_damage += norandom ? dmg : dmg  # CustomPunch damage is already the full value
        end
      end
      next
    end

    # ── A_CustomMeleeAttack ──────────────────────────────────────────
    # A_CustomMeleeAttack(damage, [meleesound, [misssound, [damagetype, [norandom]]]])
    if lc.includes?("a_custommeleeattack")
      args_str = extract_action_args(line, "A_CustomMeleeAttack")
      if args_str
        args = split_action_args(args_str)
        if args.size >= 1
          total_damage += parse_damage_expression(args[0])
        end
      else
        total_damage += 10.0  # Default melee
      end
      next
    end

    # ── A_MeleeAttack ────────────────────────────────────────────────
    if lc.includes?("a_meleeattack") && !lc.includes?("a_custommeleeattack")
      total_damage += 10.0  # Default melee damage
      next
    end

    # ── Projectile-firing functions ──────────────────────────────────
    # A_FireCustomMissile(missiletype, [angle, [useammo, [spawnofs_xy, [spawnheight]]]])
    # A_FireProjectile(missiletype, ...)
    # A_CustomMissile(missiletype, ...)
    # A_LaunchProjectile(missiletype, ...)  (ZScript alias)
    projectile_funcs = ["a_firecustommissile", "a_fireprojectile",
                        "a_custommissile", "a_launchprojectile"]
    matched_proj = false
    projectile_funcs.each do |func_name|
      if lc.includes?(func_name)
        # Use original case for extraction
        display_name = case func_name
                       when "a_firecustommissile" then "A_FireCustomMissile"
                       when "a_fireprojectile"    then "A_FireProjectile"
                       when "a_custommissile"     then "A_CustomMissile"
                       when "a_launchprojectile"  then "A_LaunchProjectile"
                       else func_name
                       end
        args_str = extract_action_args(line, display_name)
        if args_str
          args = split_action_args(args_str)
          if args.size >= 1
            proj_name = args[0].strip.strip('"').strip('\'')
            proj_dmg = lookup_projectile_damage(proj_name, actordb)
            total_damage += proj_dmg
          end
        end
        matched_proj = true
        break
      end
    end
    next if matched_proj

    # ── A_RailAttack ─────────────────────────────────────────────────
    # A_RailAttack(damage, [spawnofs_xy, ...])
    if lc.includes?("a_railattack")
      args_str = extract_action_args(line, "A_RailAttack")
      if args_str
        args = split_action_args(args_str)
        if args.size >= 1
          total_damage += parse_damage_expression(args[0])
        end
      else
        total_damage += 150.0
      end
      next
    end

    # ── Vanilla / Heretic / Strife hardcoded functions ───────────────
    VANILLA_DAMAGE.each do |func_lc, dmg|
      # Match function name as a whole word (not substring of another function)
      # Use word boundary check: the char before and after should not be alphanumeric/_
      if lc.includes?(func_lc) && dmg > 0
        # Verify it's a standalone match (not part of a longer function name)
        idx = lc.index(func_lc)
        if idx
          before_ok = idx == 0 || !lc[idx - 1].ascii_alphanumeric?
          after_idx = idx + func_lc.size
          after_ok = after_idx >= lc.size || !lc[after_idx].ascii_alphanumeric?
          if before_ok && after_ok
            total_damage += dmg
            break  # Only count one vanilla function per line
          end
        end
      end
    end
  end

  total_damage
end
