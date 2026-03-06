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

# ── Jump Target Extraction ───────────────────────────────────────────────────

# Jump functions where the last argument is the target state name.
# All comparisons are case-insensitive. The target arg index is 0-based.
JUMP_FUNCTIONS = {
  "a_jumpifinventory"   => 2,  # A_JumpIfInventory("item", count, "TargetState")
  "a_jumpifhealthlower" => 1,  # A_JumpIfHealthLower(health, "TargetState")
  "a_jump"              => 1,  # A_Jump(chance, "TargetState")
}

# Extract the jump target state name from a line containing a jump function.
# Returns the target state name (lowercase) or nil if no jump is detected.
# Only returns targets that reference a state within the same actor (no "Super::" etc).
def extract_jump_target(line : String) : String?
  lc = line.downcase

  # Check each known jump function (case-insensitive via lowercase comparison)
  # Use word boundary check to prevent "a_jump" matching "a_jumpifinventory"
  JUMP_FUNCTIONS.each do |func_lc, target_arg_idx|
    idx = lc.index(func_lc)
    next unless idx
    # Verify it's a standalone match (not part of a longer function name)
    after_idx = idx + func_lc.size
    next if after_idx < lc.size && lc[after_idx].ascii_alphanumeric?

    args_str = extract_action_args(line, func_lc)
    next unless args_str

    args = split_action_args(args_str)
    next unless args.size > target_arg_idx

    target = args[target_arg_idx].strip.strip('"').strip('\'')
    next if target.empty?

    # Skip numeric offset targets (e.g. A_JumpIfInventory("Item",1,1) — skips N frames)
    next if target =~ /^\d+$/

    # Skip cross-actor references like "Super::Fire"
    next if target.includes?("::")

    return target.downcase
  end

  nil
end

# Extract the A_GunFlash target state from a line.
# A_GunFlash runs the target on the overlay layer (doesn't transfer execution).
# Returns the target state name (lowercase): first arg if provided, "flash" by default.
# Returns nil if no A_GunFlash is found on the line.
def extract_gunflash_target(line : String) : String?
  lc = line.downcase
  return nil unless lc.includes?("a_gunflash")

  args_str = extract_action_args(line, "a_gunflash")
  if args_str
    args = split_action_args(args_str)
    if args.size >= 1
      target = args[0].strip.strip('"').strip('\'')
      if !target.empty? && !target.includes?("::")
        return target.downcase
      end
    end
  end
  # No args or empty first arg — defaults to "Flash" state
  "flash"
end

# Check if a line contains a reload-check function that ends the firing cycle.
# A_CheckForReload marks the boundary of a single shot — we stop counting ticks/damage here.
# Note: A_ReFire is NOT a terminator — it conditionally loops back if fire button is held,
# but execution continues past it when the button is released (used in charge weapons).
def is_fire_cycle_terminator(line : String) : Bool
  lc = line.downcase
  return true if lc.includes?("a_checkforreload")
  false
end

# ── Tick Counting ─────────────────────────────────────────────────────────────

# Count total ticks in a Fire state text block.
# Each DECORATE state line: SPRT FRAMES DURATION [action]
# Multi-frame shorthand: SPRT ABCDE 3 = 5 frames × 3 ticks = 15 ticks
# Stops counting at Goto, Loop, Stop, or a new label definition.
# When actor_states is provided, follows jump targets (A_JumpIfInventory, etc.)
# into referenced states and includes their ticks.
# visited_states prevents infinite loops from circular jump references.
# Returns 0 if parsing fails.
def count_fire_state_ticks(fire_state_text : String,
                           actor_states : Hash(String, String)? = nil,
                           visited_states : Set(String)? = nil) : Int32
  total_ticks = 0
  last_goto_target : String? = nil  # Track last Goto target to follow after loop

  fire_state_text.each_line do |raw_line|
    line = raw_line.strip
    next if line.empty?
    next if line.starts_with?("//")  # Skip comments

    lc = line.downcase

    # Stop at flow control (loop/stop/wait end the sequence)
    break if lc.starts_with?("loop")
    break if lc.starts_with?("stop")
    break if lc.starts_with?("wait")
    # New label definition (word followed by colon at start of line)
    break if line =~ /^[a-zA-Z_]\w*\s*:/

    # Goto — record the target but skip over it. Intermediate Gotos (on conditional
    # failure paths like "goto Reload" after A_JumpIfInventory) are not the main path.
    # Only the LAST Goto encountered is followed after the loop ends.
    if lc.starts_with?("goto ")
      last_goto_target = lc.sub("goto ", "").strip.downcase
      next
    end

    # Stop at fire cycle terminators (A_CheckForReload)
    break if is_fire_cycle_terminator(line)

    # Check for jump functions — follow the target state for ticks.
    # Conditional jumps (A_Jump, A_JumpIfInventory, etc.) may not fire,
    # so we follow the target but continue processing this state.
    # A_GunFlash runs on the overlay layer — no ticks added, execution continues.
    if actor_states
      jump_target = extract_jump_target(line)
      if jump_target
        # Track visited states to prevent infinite loops
        visited = visited_states || Set(String).new
        unless visited.includes?(jump_target)
          visited.add(jump_target)
          target_text = actor_states[jump_target]? || ""
          if !target_text.empty?
            jump_ticks = count_fire_state_ticks(target_text, actor_states, visited)
            total_ticks += jump_ticks
            log(3, "  [DmgCalc] Tick count: jump to \"#{jump_target}\" — added #{jump_ticks} ticks")
          end
        end
      end
    end
    # A_GunFlash: overlay layer — no ticks to add, execution continues on main layer

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

  # Follow the last Goto target (the terminal one — the main execution path)
  if last_goto_target && actor_states
    unless last_goto_target == "ready" || last_goto_target == "select" || last_goto_target == "deselect" || last_goto_target == "lightdone"
      visited = visited_states || Set(String).new
      unless visited.includes?(last_goto_target)
        visited.add(last_goto_target)
        target_text = actor_states[last_goto_target]? || ""
        if !target_text.empty?
          goto_ticks = count_fire_state_ticks(target_text, actor_states, visited)
          total_ticks += goto_ticks
          log(3, "  [DmgCalc] Tick count: goto \"#{last_goto_target}\" — added #{goto_ticks} ticks")
        end
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

# Calculate fire rate including fall-through states (Fire → next label → ...).
# Follows the same chain logic as calculate_weapon_damage: when Fire has no
# flow control, it falls through to the next state label in source order.
# Returns 0.0 if ticks can't be determined.
def calculate_fire_rate_with_fallthrough(actor : Actor) : Float64
  fire_text = actor.states["fire"]? || ""
  total_ticks = count_fire_state_ticks(fire_text, actor.states)

  # Follow the fall-through chain for ticks too
  if state_has_no_flow_control(fire_text)
    state_keys = actor.states.keys
    fire_idx = state_keys.index("fire")
    if fire_idx
      next_idx = fire_idx + 1
      while next_idx < state_keys.size
        next_key = state_keys[next_idx]
        next_text = actor.states[next_key]? || ""
        break if next_text.empty?

        total_ticks += count_fire_state_ticks(next_text, actor.states)
        break unless state_has_no_flow_control(next_text)
        next_idx += 1
      end
    end
  end

  return 0.0 if total_ticks <= 0
  DOOM_TICS_PER_SECOND / total_ticks.to_f64
end

# ── Projectile Damage Lookup ─────────────────────────────────────────────────

# Look up a projectile actor by name in the actordb and return its damage.
# Checks the actor's "damage" property, "explosion_damage" property,
# A_Explode calls in the Spawn state, and A_SpawnItem sub-projectile damage.
# Returns 0.0 if the projectile can't be found.
def lookup_projectile_damage(projectile_name : String, actordb : Array(Actor)) : Float64
  return 0.0 if projectile_name.empty?

  # Strip quotes from projectile name
  clean_name = projectile_name.strip.strip('"').strip('\'')
  return 0.0 if clean_name.empty?

  # Search actordb for the projectile (case-insensitive)
  target_lc = clean_name.downcase
  proj_actor = actordb.find { |a| a.name.downcase == target_lc }
  if proj_actor.nil?
    log(3, "  [DmgCalc] Projectile lookup: \"#{clean_name}\" not found in actordb (#{actordb.size} actors)")
    return 0.0
  end

  # Parse the projectile's damage property, fall back to DamageFunction if Damage is 0
  raw_damage = proj_actor.damage
  damage = parse_damage_expression(raw_damage)
  if damage <= 0 && proj_actor.damage_function != "UNDEFINED"
    raw_damage = proj_actor.damage_function
    damage = parse_damage_expression(raw_damage)
    log(3, "  [DmgCalc] Projectile lookup: \"#{clean_name}\" found — DamageFunction=\"#{raw_damage}\", parsed=#{damage.round(1)}")
  else
    log(3, "  [DmgCalc] Projectile lookup: \"#{clean_name}\" found — raw damage=\"#{raw_damage}\", parsed=#{damage.round(1)}")
  end

  # Scan Spawn and Death states for A_Explode and A_SpawnItem sub-projectile damage.
  # A_Explode with no args or -1 uses the actor's ExplosionDamage property (default 128).
  # Spawn: ripper projectiles that explode/spawn damage actors while traveling.
  # Death: standard projectiles that explode on impact.
  {"spawn", "death"}.each do |state_key|
    state_text = proj_actor.states[state_key]? || ""
    if !state_text.empty?
      state_extra = scan_projectile_spawn_damage(state_text, clean_name, actordb, proj_actor.explosion_damage)
      if state_extra > 0
        damage += state_extra
        log(3, "  [DmgCalc] Projectile lookup: \"#{clean_name}\" +#{state_key}_state_damage=#{state_extra.round(1)}, total=#{damage.round(1)}")
      end
    end
  end

  damage
end

# Scan a projectile's Spawn/Death state for additional damage sources:
#   - A_Explode(damage, radius, ...) — inline explosion damage
#   - A_SpawnItem("SubProjectile") / A_SpawnItemEx("SubProjectile") — sub-projectile damage
# actor_explosion_damage: the actor's ExplosionDamage property value (-1 = not set).
#   When A_Explode has no args or first arg is -1, it uses ExplosionDamage (default 128).
# Returns the additional damage found (0.0 if none).
def scan_projectile_spawn_damage(spawn_text : String, proj_name : String, actordb : Array(Actor),
                                  actor_explosion_damage : Int32 = -1) : Float64
  extra_damage = 0.0

  spawn_text.each_line do |raw_line|
    line = raw_line.strip
    next if line.empty?
    next if line.starts_with?("//")
    lc = line.downcase

    # ── A_Explode(damage, radius, ...) ──────────────────────────────
    # No args or first arg <= 0: uses actor's ExplosionDamage property (default 128)
    if lc.includes?("a_explode")
      explode_dmg = 0.0
      args_str = extract_action_args(line, "A_Explode")
      if args_str
        args = split_action_args(args_str)
        if args.size >= 1
          explode_dmg = parse_damage_expression(args[0])
        end
      end
      # A_Explode with no args, empty args, or damage <= 0 means use ExplosionDamage
      if explode_dmg <= 0
        explode_dmg = actor_explosion_damage > 0 ? actor_explosion_damage.to_f64 : 128.0
        log(3, "  [DmgCalc] Projectile \"#{proj_name}\": A_Explode (no/default args) — using ExplosionDamage=#{explode_dmg.round(1)}")
      else
        log(3, "  [DmgCalc] Projectile \"#{proj_name}\": A_Explode — damage=#{explode_dmg.round(1)}")
      end
      extra_damage += explode_dmg
    end

    # ── A_SpawnItem("SubProjectile") — look up sub-projectile damage ──
    if lc.includes?("a_spawnitem") && !lc.includes?("a_spawnitemex")
      args_str = extract_action_args(line, "A_SpawnItem")
      if args_str
        args = split_action_args(args_str)
        if args.size >= 1
          sub_name = args[0].strip.strip('"').strip('\'')
          # Avoid infinite recursion — don't look up self
          if sub_name.downcase != proj_name.downcase
            sub_dmg = lookup_sub_projectile_damage(sub_name, actordb)
            if sub_dmg > 0
              extra_damage += sub_dmg
              log(3, "  [DmgCalc] Projectile \"#{proj_name}\" Spawn: A_SpawnItem(\"#{sub_name}\") — sub-projectile damage=#{sub_dmg.round(1)}")
            end
          end
        end
      end
    end

    # ── A_SpawnItemEx("SubProjectile", ...) ───────────────────────────
    if lc.includes?("a_spawnitemex")
      args_str = extract_action_args(line, "A_SpawnItemEx")
      if args_str
        args = split_action_args(args_str)
        if args.size >= 1
          sub_name = args[0].strip.strip('"').strip('\'')
          if sub_name.downcase != proj_name.downcase
            sub_dmg = lookup_sub_projectile_damage(sub_name, actordb)
            if sub_dmg > 0
              extra_damage += sub_dmg
              log(3, "  [DmgCalc] Projectile \"#{proj_name}\" Spawn: A_SpawnItemEx(\"#{sub_name}\") — sub-projectile damage=#{sub_dmg.round(1)}")
            end
          end
        end
      end
    end
  end

  extra_damage
end

# Look up a sub-projectile's damage.
# Checks Damage/DamageFunction/ExplosionDamage properties AND scans Spawn/Death
# states for A_Explode calls, but does NOT recurse into further A_SpawnItem calls
# to prevent infinite loops from circular references.
def lookup_sub_projectile_damage(sub_name : String, actordb : Array(Actor)) : Float64
  return 0.0 if sub_name.empty?
  target_lc = sub_name.downcase
  sub_actor = actordb.find { |a| a.name.downcase == target_lc }
  return 0.0 if sub_actor.nil?

  damage = parse_damage_expression(sub_actor.damage)

  # Fall back to DamageFunction if Damage is 0
  if damage <= 0 && sub_actor.damage_function != "UNDEFINED"
    damage = parse_damage_expression(sub_actor.damage_function)
  end

  # Scan Spawn and Death states for A_Explode (but NOT A_SpawnItem to avoid recursion).
  # A_Explode with no args or -1 uses the actor's ExplosionDamage property (default 128).
  {"spawn", "death"}.each do |state_key|
    state_text = sub_actor.states[state_key]? || ""
    next if state_text.empty?

    state_text.each_line do |raw_line|
      line = raw_line.strip
      next if line.empty?
      next if line.starts_with?("//")
      lc = line.downcase

      if lc.includes?("a_explode")
        explode_dmg = 0.0
        args_str = extract_action_args(line, "A_Explode")
        if args_str
          args = split_action_args(args_str)
          if args.size >= 1
            explode_dmg = parse_damage_expression(args[0])
          end
        end
        # A_Explode with no args, empty args, or damage <= 0 means use ExplosionDamage
        if explode_dmg <= 0
          explode_dmg = sub_actor.explosion_damage > 0 ? sub_actor.explosion_damage.to_f64 : 128.0
          log(3, "  [DmgCalc] Sub-projectile \"#{sub_name}\" #{state_key}: A_Explode (no/default args) — using ExplosionDamage=#{explode_dmg.round(1)}")
        else
          log(3, "  [DmgCalc] Sub-projectile \"#{sub_name}\" #{state_key}: A_Explode — damage=#{explode_dmg.round(1)}")
        end
        damage += explode_dmg
      end
    end
  end

  log(3, "  [DmgCalc] Sub-projectile lookup: \"#{sub_name}\" — total damage=#{damage.round(1)}")
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
# When Fire has no flow control (goto/loop/stop/wait), it falls through to the
# next state label — which could be Hold, or any custom label like OneRocket.
# Follows the fall-through chain until damage is found or a flow control is hit.
# Checks AltFire as fallback if Fire chain yields nothing.
# Returns 0.0 if damage can't be determined (triggers tier-based fallback).
def calculate_weapon_damage(actor : Actor, actordb : Array(Actor)) : Float64
  damage = 0.0

  # Parse Fire state (pass actor.states so jumps can be followed)
  fire_text = actor.states["fire"]? || ""
  damage = parse_fire_state_for_damage(fire_text, actordb, actor.name_with_case, "Fire", actor.states)

  # If Fire has no flow control, follow the fall-through chain into subsequent states.
  # In DECORATE, when a state has no goto/loop/stop/wait, execution continues into
  # the next state label (e.g. Fire: → OneRocket:, or Fire: → Hold:).
  if state_has_no_flow_control(fire_text)
    state_keys = actor.states.keys
    fire_idx = state_keys.index("fire")
    if fire_idx
      # Walk subsequent states as long as they contribute damage and have no flow control
      next_idx = fire_idx + 1
      while next_idx < state_keys.size
        next_key = state_keys[next_idx]
        next_text = actor.states[next_key]? || ""
        break if next_text.empty?

        next_damage = parse_fire_state_for_damage(next_text, actordb, actor.name_with_case, next_key, actor.states)
        if next_damage > 0.0
          damage += next_damage
          log(3, "  [DmgCalc] #{actor.name_with_case}: Fire falls through to #{next_key} — added damage #{next_damage.round(1)}, combined = #{damage.round(1)}")
        end

        # Stop following the chain if this state ends with flow control
        break unless state_has_no_flow_control(next_text)
        next_idx += 1
      end
    end
  end

  # If Fire chain yielded no damage, try AltFire
  if damage <= 0.0
    altfire_text = actor.states["altfire"]? || ""
    damage = parse_fire_state_for_damage(altfire_text, actordb, actor.name_with_case, "AltFire", actor.states)
    if damage > 0.0
      log(3, "  [DmgCalc] #{actor.name_with_case}: Fire chain had no damage, used AltFire instead")
    end
  end

  if damage <= 0.0
    log(3, "  [DmgCalc] #{actor.name_with_case}: No damage found in Fire chain or AltFire states — will use tier fallback")
  else
    log(3, "  [DmgCalc] #{actor.name_with_case}: Final calculated damage = #{damage.round(1)}")
  end

  damage
end

# Check if a state text block has no flow control at the end (no goto/loop/stop/wait).
# When a state has no flow control, DECORATE execution falls through to the next
# state label in source order. Returns true if the state falls through.
def state_has_no_flow_control(state_text : String) : Bool
  return false if state_text.empty?

  # Find the last meaningful line in the state
  last_line = ""
  state_text.each_line do |raw_line|
    line = raw_line.strip
    next if line.empty?
    next if line.starts_with?("//")
    last_line = line
  end

  return false if last_line.empty?

  lc = last_line.downcase
  # If the state ends with a flow control keyword, it does NOT fall through
  return false if lc.starts_with?("goto ")
  return false if lc.starts_with?("loop")
  return false if lc.starts_with?("stop")
  return false if lc.starts_with?("wait")

  # No flow control at the end — state falls through to the next label
  true
end

# Parse a single state block (Fire or AltFire) for damage-dealing actions.
# When actor_states is provided, follows jump targets (A_JumpIfInventory, etc.)
# into referenced states and includes their damage.
# visited_states prevents infinite loops from circular jump references.
# Returns the total damage per firing cycle.
def parse_fire_state_for_damage(state_text : String, actordb : Array(Actor),
                                 actor_name : String = "", state_name : String = "Fire",
                                 actor_states : Hash(String, String)? = nil,
                                 visited_states : Set(String)? = nil) : Float64
  return 0.0 if state_text.empty?

  total_damage = 0.0
  last_goto_target : String? = nil  # Track last Goto target to follow after loop
  log_prefix = "  [DmgCalc] #{actor_name} (#{state_name})"

  state_text.each_line do |raw_line|
    line = raw_line.strip
    next if line.empty?
    next if line.starts_with?("//")

    lc = line.downcase

    # Stop at flow control (loop/stop/wait end the sequence)
    break if lc.starts_with?("loop")
    break if lc.starts_with?("stop")
    break if lc.starts_with?("wait")
    break if line =~ /^[a-zA-Z_]\w*\s*:/

    # Goto — record the target but skip over it. Intermediate Gotos (on conditional
    # failure paths like "goto Reload" after A_JumpIfInventory) are not the main path.
    # Only the LAST Goto encountered is followed after the loop ends.
    if lc.starts_with?("goto ")
      last_goto_target = lc.sub("goto ", "").strip.downcase
      next
    end

    # Stop at fire cycle terminators (A_CheckForReload)
    break if is_fire_cycle_terminator(line)

    # Check for transfer jumps (A_Jump, A_JumpIfInventory, etc.) — execution transfers
    # to the target state, so we follow it for damage and stop processing this state.
    if actor_states
      jump_target = extract_jump_target(line)
      if jump_target
        visited = visited_states || Set(String).new
        unless visited.includes?(jump_target)
          visited.add(jump_target)
          target_text = actor_states[jump_target]? || ""
          if !target_text.empty?
            jump_dmg = parse_fire_state_for_damage(target_text, actordb, actor_name, jump_target, actor_states, visited)
            if jump_dmg > 0
              total_damage += jump_dmg
              log(3, "#{log_prefix}: Jump to \"#{jump_target}\" — added damage #{jump_dmg.round(1)}")
            end
          end
        end
        # Don't break — conditional jumps (A_JumpIfInventory, A_Jump, etc.) may not
        # fire. Continue processing the current state for damage functions that follow.
        # visited_states prevents double-counting if the same target state is referenced
        # by multiple jumps (e.g. M60's fire1-fire5 all going to Flash).
      end
    end

    # Check for A_GunFlash — runs Flash (or custom) state on overlay layer for damage,
    # but execution continues on the main layer (don't break).
    if actor_states
      flash_target = extract_gunflash_target(line)
      if flash_target
        visited = visited_states || Set(String).new
        unless visited.includes?(flash_target)
          visited.add(flash_target)
          target_text = actor_states[flash_target]? || ""
          if !target_text.empty?
            flash_dmg = parse_fire_state_for_damage(target_text, actordb, actor_name, flash_target, actor_states, visited)
            if flash_dmg > 0
              total_damage += flash_dmg
              log(3, "#{log_prefix}: A_GunFlash(\"#{flash_target}\") — overlay damage #{flash_dmg.round(1)}")
            end
          end
        end
        # Don't break — main state execution continues after A_GunFlash
      end
    end

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
          bullet_dmg = num_bullets * damage_per * 2.0
          total_damage += bullet_dmg
          log(3, "#{log_prefix}: A_FireBullets — #{num_bullets.round(0)} bullets × #{damage_per.round(1)} dmg × 2 (median) = #{bullet_dmg.round(1)}")
        else
          log(3, "#{log_prefix}: A_FireBullets — not enough args (#{args.size}), need 4+")
        end
      else
        log(3, "#{log_prefix}: A_FireBullets — could not extract args from: #{line.strip}")
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
          log(3, "#{log_prefix}: A_CustomPunch — damage=#{dmg.round(1)} norandom=#{norandom}")
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
          melee_dmg = parse_damage_expression(args[0])
          total_damage += melee_dmg
          log(3, "#{log_prefix}: A_CustomMeleeAttack — damage=#{melee_dmg.round(1)}")
        end
      else
        total_damage += 10.0  # Default melee
        log(3, "#{log_prefix}: A_CustomMeleeAttack — no args, using default 10.0")
      end
      next
    end

    # ── A_MeleeAttack ────────────────────────────────────────────────
    if lc.includes?("a_meleeattack") && !lc.includes?("a_custommeleeattack")
      total_damage += 10.0  # Default melee damage
      log(3, "#{log_prefix}: A_MeleeAttack — using default 10.0")
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
            if proj_dmg > 0
              log(3, "#{log_prefix}: #{display_name}(\"#{proj_name}\") — projectile damage=#{proj_dmg.round(1)}")
            else
              log(3, "#{log_prefix}: #{display_name}(\"#{proj_name}\") — projectile found but damage=0 (may use A_Explode or sub-projectiles)")
            end
          end
        else
          log(3, "#{log_prefix}: #{display_name} — could not extract args from: #{line.strip}")
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
          rail_dmg = parse_damage_expression(args[0])
          total_damage += rail_dmg
          log(3, "#{log_prefix}: A_RailAttack — damage=#{rail_dmg.round(1)}")
        end
      else
        total_damage += 150.0
        log(3, "#{log_prefix}: A_RailAttack — no args, using default 150.0")
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
            log(3, "#{log_prefix}: #{func_lc} (vanilla hardcoded) — damage=#{dmg.round(1)}")
            break  # Only count one vanilla function per line
          end
        end
      end
    end
  end

  # Follow the last Goto target (the terminal one — the main execution path)
  if last_goto_target && actor_states
    unless last_goto_target == "ready" || last_goto_target == "select" || last_goto_target == "deselect" || last_goto_target == "lightdone"
      visited = visited_states || Set(String).new
      unless visited.includes?(last_goto_target)
        visited.add(last_goto_target)
        target_text = actor_states[last_goto_target]? || ""
        if !target_text.empty?
          goto_dmg = parse_fire_state_for_damage(target_text, actordb, actor_name, last_goto_target, actor_states, visited)
          if goto_dmg > 0
            total_damage += goto_dmg
            log(3, "#{log_prefix}: Goto \"#{last_goto_target}\" — added damage #{goto_dmg.round(1)}")
          end
        end
      end
    end
  end

  if total_damage > 0
    log(3, "#{log_prefix}: Total damage for #{state_name} state = #{total_damage.round(1)}")
  end

  total_damage
end
