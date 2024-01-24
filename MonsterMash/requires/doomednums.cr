##########################################
# Obsidian Reserved Doomednums
##########################################
# It is necessary to define these doomednums since we will be handing out unique IDs to all
# monsters that have conflicting IDs, as well as assigning new IDs to monsters that don't have one
##########################################

# Hash definition
# = Hash(Int32, Tuple(Int32, Int32)).new
# File: id_module.cr
module DoomEdNums
  # Define a variable within the module
  @@id_numbers = {
    992 => {-1, -1},
    ###########################

    #992 - WADFAB_REACHABLE - this force Obsidian to generate enclosed or closed sectors.
    992 => {-1, -1},
    # 995 - this marks this sector as a MOVER (lift), and forces bottoms of sidedefs to be unpegged. (The lines composing the affected sector need the 991 action. It can also be used to force the generator into unpegging some surface the genny refuse to do itself!)
    995 => {-1, -1},
    # 996 - this marks this sector as a DOOR, and forces the tops of sidedefs to be unpegged. (The lines composing the affected sector need the 991 action. It can also be used to force the generator into unpegging some surface the genny refuse to do itself!)
    996 => {-1, -1},
    # 997 - WADFAB_DELTA - this combined with delta = X, in the prefab's lua will allow obsidian to lower sectors by the defined number under floor height 0 (otherwise sectors under height of 0 simply get booted back up to 0 and cleaned up).
    997 => {-1, -1},
    # 987 - WADFAB_LIGHT_BRUSH - even if this sector is marked _NOTHING on the floor and ceiling, Obsidian will adopt the sector's brightness setting
    987 => {-1, -1},

    # Reserved Thing IDs
    # 8166 - spot for a big item to pickup (Weapon, Key, Armor, Power-up). Can be influenced with item_kind field to limit what item this should be.
    8166 => {-1, -1},
    # 8151 - spot for small pickups like armor and health bonus or small ammo drops.
    8151 => {-1, -1},

    # Regular Monsters
    # 8102 - spot for a monster with a radius of 20 or less(Imps, Zombies, Revenants, Lost Souls, Archviles)
    8102 => {-1, -1},
    # 8103 - same as above, but for monsters below a maximum radius of 32 or less(Pinkies, Cacodemons, Hell Knights, Barons, Pain Elementals)
    8102 => {-1, -1},
    # 8104 - same as above, but for monsters below a maximum radius of 48 or less(Mancubi, Cyberdemons)
    8104 => {-1, -1},
    # 8106 - same as above, but for monsters below a maximum radius of 64 or less(Arachnotrons)
    8106 => {-1, -1},
    # 8108 - same as above, but for monsters below a maximum radius of 128 or less (Masterminds)
    8108 => {-1, -1},

    # Flying Monsters
    # 8112,8113,8114,8116,8118 - same template pattern as regular monsters, but capable of flight
    8112 => {-1, -1},
    8113 => {-1, -1},
    8114 => {-1, -1},
    8116 => {-1, -1},
    8118 => {-1, -1},

    # Caged Monsters
    # 8122,8123,8124,8126,8128 - same template pattern as regular monsters, but spawn in cages and have projectile/missile attacks
    8122 => {-1, -1},
    8123 => {-1, -1},
    8124 => {-1, -1},
    8126 => {-1, -1},
    8128 => {-1, -1},

    # Closet / Trap Monsters
    # 8132,8133,8134,8136,8138 - same template pattern as regular monsters, but spawn in monster closets or traps
    8132 => {-1, -1},
    8133 => {-1, -1},
    8134 => {-1, -1},
    8136 => {-1, -1},
    8138 => {-1, -1},

    # Lights
    # 14999 White
    14999 => {-1, -1},
    # 14998 Red
    14998 => {-1, -1},
    # 14997 Orange
    14997 => {-1, -1},
    # 14996 Yellow
    14996 => {-1, -1},
    # 14995 Blue
    14995 => {-1, -1},
    # 14994 Green
    14994 => {-1, -1},
    # 14993 Beige
    14993 => {-1, -1},
    # 14992 Purple
    14992 => {-1, -1},

    # Custom decorations
    # 27000 Hospital blood pack
    27000 => {-1, -1},
    # 27001 Fire
    27001 => {-1, -1},
    # 27002 Fire with debris
    27002 => {-1, -1},

    # Reserved Linedefs
    # 888 - this linedef will be used as a switch for quest generation in Obsidian e.g. this switch can open some other switched door in the level.
    888 => {-1, -1},

    # Fauna Module
    # ScurryRat
    30100 => {-1, -1},
    # SpringyFly
    30000 => {-1, -1},

    # Ranges for Frozsoul's Ambient Sounds
    # We don't technically need to avoid all of them, there are only 26 sounds.
    # But since we are only losing 26 IDs per 2000, there are plenty of IDs to be had.
    # 20000-20025, 22000-22025, 24000-24025, 26000-26025, 28000-28025, 30000-30025
      20000..20025 => {-1, -1},
      22000..22025 => {-1, -1},
      24000..24025 => {-1, -1},
      26000..26025 => {-1, -1},
      28000..28025 => {-1, -1},
      30000..30025 => {-1, -1},

    #####################3333
  }

  # Getter method to access the id_numbers variable
  def self.id_numbers
    @@id_numbers
  end
end
