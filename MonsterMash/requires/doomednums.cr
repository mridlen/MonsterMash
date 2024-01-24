##########################################
# Obsidian Reserved Doomednums
##########################################
# It is necessary to define these doomednums since we will be handing out unique IDs to all
# monsters that have conflicting IDs, as well as assigning new IDs to monsters that don't have one
##########################################

# Hash definition
doomednum_info = Hash(Int32, Tuple(Int32, Int32)).new

#992 - WADFAB_REACHABLE - this force Obsidian to generate enclosed or closed sectors.
doomednum_info[992] = {-1, -1}
# 995 - this marks this sector as a MOVER (lift), and forces bottoms of sidedefs to be unpegged. (The lines composing the affected sector need the 991 action. It can also be used to force the generator into unpegging some surface the genny refuse to do itself!)
doomednum_info[995] = {-1, -1}
# 996 - this marks this sector as a DOOR, and forces the tops of sidedefs to be unpegged. (The lines composing the affected sector need the 991 action. It can also be used to force the generator into unpegging some surface the genny refuse to do itself!)
doomednum_info[996] = {-1, -1}
# 997 - WADFAB_DELTA - this combined with delta = X, in the prefab's lua will allow obsidian to lower sectors by the defined number under floor height 0 (otherwise sectors under height of 0 simply get booted back up to 0 and cleaned up).
doomednum_info[997] = {-1, -1}
# 987 - WADFAB_LIGHT_BRUSH - even if this sector is marked _NOTHING on the floor and ceiling, Obsidian will adopt the sector's brightness setting
doomednum_info[987] = {-1, -1}

# Reserved Thing IDs
# 8166 - spot for a big item to pickup (Weapon, Key, Armor, Power-up). Can be influenced with item_kind field to limit what item this should be.
doomednum_info[8166] = {-1, -1}
# 8151 - spot for small pickups like armor and health bonus or small ammo drops.
doomednum_info[8151] = {-1, -1}

# Regular Monsters
# 8102 - spot for a monster with a radius of 20 or less(Imps, Zombies, Revenants, Lost Souls, Archviles)
doomednum_info[8102] = {-1, -1}
# 8103 - same as above, but for monsters below a maximum radius of 32 or less(Pinkies, Cacodemons, Hell Knights, Barons, Pain Elementals)
doomednum_info[8102] = {-1, -1}
# 8104 - same as above, but for monsters below a maximum radius of 48 or less(Mancubi, Cyberdemons)
doomednum_info[8104] = {-1, -1}
# 8106 - same as above, but for monsters below a maximum radius of 64 or less(Arachnotrons)
doomednum_info[8106] = {-1, -1}
# 8108 - same as above, but for monsters below a maximum radius of 128 or less (Masterminds)
doomednum_info[8108] = {-1, -1}

# Flying Monsters
# 8112,8113,8114,8116,8118 - same template pattern as regular monsters, but capable of flight
doomednum_info[8112] = {-1, -1}
doomednum_info[8113] = {-1, -1}
doomednum_info[8114] = {-1, -1}
doomednum_info[8116] = {-1, -1}
doomednum_info[8118] = {-1, -1}

# Caged Monsters
# 8122,8123,8124,8126,8128 - same template pattern as regular monsters, but spawn in cages and have projectile/missile attacks
doomednum_info[8122] = {-1, -1}
doomednum_info[8123] = {-1, -1}
doomednum_info[8124] = {-1, -1}
doomednum_info[8126] = {-1, -1}
doomednum_info[8128] = {-1, -1}

# Closet / Trap Monsters
# 8132,8133,8134,8136,8138 - same template pattern as regular monsters, but spawn in monster closets or traps
doomednum_info[8132] = {-1, -1}
doomednum_info[8133] = {-1, -1}
doomednum_info[8134] = {-1, -1}
doomednum_info[8136] = {-1, -1}
doomednum_info[8138] = {-1, -1}

# Lights
# 14999 White
doomednum_info[14999] = {-1, -1}
# 14998 Red
doomednum_info[14998] = {-1, -1}
# 14997 Orange
doomednum_info[14997] = {-1, -1}
# 14996 Yellow
doomednum_info[14996] = {-1, -1}
# 14995 Blue
doomednum_info[14995] = {-1, -1}
# 14994 Green
doomednum_info[14994] = {-1, -1}
# 14993 Beige
doomednum_info[14993] = {-1, -1}
# 14992 Purple
doomednum_info[14992] = {-1, -1}

# Custom decorations
# 27000 Hospital blood pack
doomednum_info[27000] = {-1, -1}
# 27001 Fire
doomednum_info[27001] = {-1, -1}
# 27002 Fire with debris
doomednum_info[27002] = {-1, -1}

# Reserved Linedefs
# 888 - this linedef will be used as a switch for quest generation in Obsidian e.g. this switch can open some other switched door in the level.
doomednum_info[888] = {-1, -1}

# Fauna Module
# ScurryRat
doomednum_info[30100] = {-1, -1}
# SpringyFly
doomednum_info[30000] = {-1, -1}

# Ranges for Frozsoul's Ambient Sounds
# We don't technically need to avoid all of them, there are only 26 sounds.
# But since we are only losing 26 IDs per 2000, there are plenty of IDs to be had.
# 20000-20025, 22000-22025, 24000-24025, 26000-26025, 28000-28025, 30000-30025
ranges = [
  20000..20025,
  22000..22025,
  24000..24025,
  26000..26025,
  28000..28025,
  30000..30025
]

ranges.each do |range|
  range.each do |id|
    doomednum_info[id] = {-1, -1}
  end
end

puts "Reserved Doomednums Loaded:"
puts doomednum_info
