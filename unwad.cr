puts "START"

puts "Requires..."
require "file"
require "file_utils"
require "regex"

jeutoolexe = ""

puts "Assigning jeutool..."
# Specify which executable to use for jeutool
# The rest of the code will be written in Crystal
{% if flag?(:linux) %}
  jeutoolexe = "jeutool-linux"
{% elsif flag?(:darwin) %}
  jeutoolexe = "jeutool-macos"
{% elsif flag?(:win32) %}
  jeutoolexe = "jeutool.exe"
{% end %}
puts "Jeutool assigned: #{jeutoolexe}"

##########################################
# DATA STRUCTURES
##########################################

puts "Defining classes to track duplicate entries..."
# we will use an array of this to track duplicate actor names
class DupedActorName
  # name is the Actor name
  property name : String
  property wad_name : String
  property duped_wad_name : String
 
  def initialize(@name : String, @wad_name : String, @duped_wad_name : String)
  end
end

# graphic prefix collisions
class DupedGraphics
  # name is the 4 letter prefix
  property name : String
  property wad_name : String
  property duped_wad_name : String

  def initialize(@name : String, @wad_name : String, @duped_wad_name : String)
  end
end

# doomednum duplicates
class DupedDoomednums
  property name : String
  property doomednum : Int32
  property wad_name : String
  property duped_wad_name : String
  property built_in : Bool = false

  def initialize(@name : String, @doomednum : Int32, @wad_name : String, @duped_wad_name : String, @built_in : Bool)
  end
end

puts "Defining Actor Class..."
class Actor
  # we need a unique index id, because actor names might conflict at first
  property index : Int32 = -1

  # these first few are defined on the actor line
  property name : String = "UNDEFINED"
  property inherits : String = "UNDEFINED"
  property replaces : String = "UNDEFINED"
  # -1 will mean undefined
  property doomednum : Int32 = -1
  # this is rare but sometimes pops up and might be useful later
  property native : Bool = false

  # sub classes?
  property inventory : Inventory

  # these next few are things that are not part of the decorate specifications
  # but they are information I will need to collect for logistical purposes
  #
  # sprite prefixes will be comma separated list of 4 character graphic prefixes
  # e.g. "PAIN,BLAH,BORK"
  property sprite_prefixes : String = "UNDEFINED"
  # File Path: e.g. "./Processing/Actor/defs/DECORATE.raw"
  property file_path : String = "UNDEFINED"
  # e.g. Blah.wad -> "Blah"
  property source_wad_folder : String = "UNDEFINED"
  # This will be "DECORATE.raw.nocomments2" or "OTHERFILE.raw"
  property source_file : String = "UNDEFINED"
  # Built In == part of some actor inherent in the doom source code
  property built_in : Bool = false

  # States will be stored in a hash
  property states : Hash(String, String) = Hash(String, String).new
  
  # and here we go with the properties inside the DECORATE...
  property game : String = "Doom"
  property spawn_id : Int32 = 0
  property conversation_id : String = "UNDEFINED"
  property tag : String = "UNDEFINED"
  property health : Int32 = 1000
  property gib_health : Int32 = -1000
  property wound_health : Int32 = 6
  property reaction_time : Int32 = 8
  # painchance is a string of comma key value pairs separated by semicolon
  # e.g. "PainChance,0;Fire,10;Something,24"
  # PainChance is the main one that is used that is not per damage type
  property pain_chance : String = "PainChance,0"
  property pain_threshold : Int32 = 0
  # damagefactor is key value like painchance
  property damage_factor : String = "DamageFactor,1.0"
  property self_damage_factor : Float64 = 1.0
  property damage_multiply : Float64 = 1.0
  # damage can be a mathematical expression which might cause problems
  # we will leave default as String "0"
  property damage : String = "0"
  # this is ZScript specific
  property damage_function : String = "UNDEFINED"
  # PoisonDamage is "value,[duration,[period]]"
  property poison_damage : String = "0"
  property poison_damage_type : String = "UNDEFINED"
  property radius_damage_factor : Float64 = 1.0
  property ripper_level : Int32 = 0
  property rip_level_min : Int32 = 0
  property rip_level_max : Int32 = 0
  property designated_team : Int32 = 0
  property speed : Float64 = 0
  property v_speed : Float64 = 0.0
  property fast_speed : Int32 = 0
  property float_speed : Int32 = 0
  property species : String = "UNDEFINED"
  property accuracy : Int32 = 100
  property stamina : Int32 = 100
  # flags separated by pipes
  # e.g. "THINGSPEC_Default | THINGSPEC_ThingTargets"
  property activation : String = "UNDEFINED"
  property tele_fog_source_type : String = "TeleportFog"
  property tele_fog_dest_type : String = "TeleportFog"
  property threshold : Int32 = 0
  property def_threshold : Int32 = 0
  property friendly_see_blocks : Int32 = 10
  property shadow_aim_factor : Float64 = 1.0
  property shadow_penalty_factor : Float64 = 1.0
  property radius : Float64 = 20.0
  property height : Int32 = 16
  # Death/Burn Height is default 1/4 height, so we might need to fix that later
  property death_height : Int32 = 4
  property burn_height : Int32 = 4
  # default of 0 here means "use the actor's height"
  property projectile_pass_height : Int32 = 0
  property gravity : Float64 = 1.0
  property friction : Float64 = 1.0
  # apparently mass can be int or hexadecimal, so we import the value as string
  property mass : String = "100"
  property max_step_height : Int32 = 24
  property max_drop_off_height : Int32 = 24
  # this is a non-exact approximation of 46342/65535
  # property max_slope_steepness : Float64 = 0.707122
  property max_slope_steepness : Float64 = (46342 / 65535)
  property bounce_type : String = "None"
  property bounce_factor : Float64 = 0.7
  property wall_bounce_factor : Float64 = 0.75
  # default is 0 if bounce_type is "None" which is also default
  property bounce_count : Int32 = 0
  # I have no idea what type of default value this has
  property projectile_kick_back : Int32 = 0
  property push_factor : Float64 = 0.25
  # values allowed for weave are 0-63 but I don't know if that's a float or int
  # I'm assuming 6-bit int for values of 0-63
  property weave_index_xy : Int32 = 0
  property weave_index_z : Int32 = 0
  # again not sure if int or float
  property thru_bits : Int32 = 0
  property active_sound : String = "UNDEFINED"
  property attack_sound : String = "UNDEFINED"
  property bounce_sound : String = "UNDEFINED"
  property crush_pain_sound : String = "UNDEFINED"
  property death_sound : String = "UNDEFINED"
  property howl_sound : String = "UNDEFINED"
  property pain_sound : String = "UNDEFINED"
  property rip_sound : String = "UNDEFINED"
  property see_sound : String = "UNDEFINED"
  property wall_bounce_sound : String = "UNDEFINED"
  property push_sound : String = "UNDEFINED"
  property render_style : String = "Normal"
  property alpha : Float64 = 1.0
  # heretic uses 0.4, everything else is 0.6
  property default_alpha : Float64 = 0.6
  property stealth_alpha : Float64 = 0
  property x_scale : Float64 = 1.0
  property y_scale : Float64 = 1.0
  property scale : Float64 = 1.0
  # Values allowed are 0-255 or -1
  # default -1 means the actor uses sectors light level
  property light_level : Int32 = -1
  # translation can be one of the following:
  # > value (0-2)
  # > string "112:127=208:223"
  # > translation variable "TranslationBlah"
  # > Translation Ice # This is a custom variable that uses unique colors
  property translation : String = "UNDEFINED"
  property blood_color : String = "UNDEFINED"
  # Can have multiple comma separated fields
  property blood_type : String = "UNDEFINED"
  property decal : String = "UNDEFINED"
  property stencil_color : String = "UNDEFINED"
  property float_bob_phase : Int32 = -1
  property float_bob_strength : Float64 = 1.0
  property distance_check : String = "UNDEFINED"
  # 180 = actors front - read the Zdoom wiki
  property sprite_angle : Int32 = 180
  property sprite_rotation : Int32 = 0
  # will take two comma separated values
  property visible_angles : String = "UNDEFINED"
  property visible_pitch : String = "UNDEFINED"
  property render_radius : Float64 = 0.0
  # Having trouble finding a default here, but I think it is 32
  property camera_height : Int32 = 32
  property camera_fov : Float64 = 90.0
  property hit_obituary : String = "UNDEFINED"
  property obituary : String = "UNDEFINED"
  property min_missile_chance : Int32 = 200
  property damage_type : String = "UNDEFINED"
  property death_type : String = "UNDEFINED"
  # no idea what the default is, so we'll do -1 to disable
  property melee_threshold : Int32 = -1
  property melee_range : Int32 = 44
  # no idea what the default is, so we'll do -1 to disable
  property max_target_range : Int32 = -1
  # these next 4 are deprecated so I'll assign a -1 to them to disable
  property melee_damage : Int32 = -1
  property melee_sound : Int32 = -1
  property missile_height : Int32 = -1
  property missile_type : Int32 = -1
  # default A_Explode is -1, so I'll go with that
  property explosion_radius : Int32 = -1
  property explosion_damage : Int32 = -1
  # deprecated = -1
  property dont_hurt_shooter : Int32 = -1
  property pain_type : String = "UNDEFINED"
  property args : String = "UNDEFINED"
  # This might be useful in cases of inheritance. Clear flags clears all flags.
  property clear_flags : Bool = false
  # String "classname[, probability [, amount]]"
  property drop_item : String = "UNDEFINED"

  # deprecated properties that we should throw a warning about
  # deprecated because of "goto" keyword
  property spawn : Int32 = -1
  property see : Int32 = -1
  property melee : Int32 = -1
  property missile : Int32 = -1
  property pain : Int32 = -1
  property death : Int32 = -1
  property x_death : Int32 = -1
  property burn : Int32 = -1
  property ice : Int32 = -1
  property disintegrate : Int32 = -1
  property raise : Int32 = -1
  property crash : Int32 = -1
  property wound : Int32 = -1
  property crush : Int32 = -1
  property heal : Int32 = -1

  # Reinitializes the actor as if it has no parent. This can be used to have access to the parent's states without inheriting its attributes.
  property skip_super : Bool = false
  property visible_to_team : Int32 = 0
  # Comma separated player classes
  property visible_to_player_class : String = "UNDEFINED"

  # flag combos that are technically properties
  property monster : Bool = false
  property projectile : Bool = false

  def initialize(@name : String, @index : Int32)
    @inventory = Inventory.new
  end

  # this function generates a dynamic list of property names
  # which is useful for doing iteration when doing inheritance
  def property_list : Array
    list_of_properties = Array(String).new
    {% for name in Actor.instance_vars %}
      list_of_properties << "#{ {{ name.id.symbolize }} }"
    {% end %}
    list_of_properties
  end
end

class Inventory
  property index : Int32 = 0
  property name : String = "UNDEFINED"

  property amount : Int32 = -1
  property def_max_amount : Int32 = 25
  property max_amount : Int32 = -1
  property inter_hub_amount : Int32 = -1
  property icon : String = "UNDEFINED"
  property alt_hud_icon : String = "UNDEFINED"
  property pickup_message : String = "UNDEFINED"
  property pickup_sound : String = "UNDEFINED"
  property pickup_flash : String = "UNDEFINED"
  property use_sound : String = "UNDEFINED"
  property respawn_tics : Int32 = -1
  property give_quest : Int32 = -1
  property forbidden_to : String = "UNDEFINED"
  property restricted_to : String = "UNDEFINED"

  property quiet : Bool = false
  property auto_active : Bool = false
  property undroppable : Bool = false
  property unclearable : Bool = false
  property inv_bar : Bool = false
  property hubpower : Bool = false
  property persistent_power : Bool = false
  property inter_hub_strip : Bool = false
  property pickup_flash_flag : Bool = false
  property always_pickup : Bool = false
  property fancy_pickup_sound : Bool = false
  property no_atten_pickup_sound : Bool = false
  property big_powerup : Bool = false
  property ignore_skill : Bool = false
  property additive_time : Bool = false
  property untossable : Bool = false
  property restrict_absolutely : Bool = false
  property no_screen_flash : Bool = false
  property tossed : Bool = false
  property always_respawn : Bool = false
  property transfer : Bool = false
  property no_teleport_freeze : Bool = false
  property no_screen_blank : Bool = false
  property is_health : Bool = false
  property is_armor : Bool = false

  #def initialize
  #  @amount = 0
  #end

  def property_list : Array
    list_of_properties = Inventory(String).new
    {% for name in Inventory.instance_vars %}
      list_of_properties << "#{ {{ name.id.symbolize }} }"
    {% end %}
    list_of_properties
  end
end

class FakeInventory
  property respawns : Bool = false
end

class Armor
  property save_amount : Int32 = -1
  property save_percent : Float64 = -1
  property max_full_absorb : Int32 = -1
  property max_absorb : Int32 = -1
  property max_save_amount : Int32 = -1
  property max_bonus : Int32 = -1
  property max_bonus_max : Int32 = -1
end

class Weapon
  property ammo_give : Int32 = -1
  property ammo_give_1 : Int32 = -1
  property ammo_give_2 : Int32 = -1
  property ammo_type : String = "UNDEFINED"
  property ammo_type_1 : String = "UNDEFINED"
  property ammo_type_2 : String = "UNDEFINED"
  property ammo_use : Int32 = -1
  property ammo_use_1 : Int32 = -1
  property ammo_use_2 : Int32 = -1
  property min_selection_ammo_1 : Int32 = -1
  property min_selection_ammo_2 : Int32 = -1
  # this is ZScript only
  property bob_pivot_3d : String = "UNDEFINED"
  property bob_range_x : Float64 = 1.0
  property bob_range_y : Float64 = 1.0
  property bob_speed : Float64 = 1.0
  property bob_style : String = "UNDEFINED"
  property kick_back : Int32 = -1
  property default_kick_back : Int32 = -1
  property ready_sound : String = "UNDEFINED"
  property selection_order : Int32 = -1
  property sister_weapon : String = "UNDEFINED"
  property slot_number : Int32 = -1
  property slot_priority : Float64 = 0.0
  property up_sound : String = "UNDEFINED"
  property weapon_scale_x : Float64 = 1.0
  property weapon_scale_y : Float64 = 1.2
  # vertial adjustment
  # I think 0 means don't do anything, there is no "safe" undefined value
  property y_adjust : Int32 = 0
  # I think this is float, most multipliers are float
  property look_scale : Float64 = 0.0
end

class Ammo
  property backpack_amount : Int32 = -1
  property backpack_max_amount : Int32 = -1
  property drop_amount : Int32 = -1
end

class WeaponPiece
  property number : Int32 = -1
  property weapon : String = "UNDEFINED"
end

class Health
  # this is in format: "value, message" so we will just grab the string
  property low_message : String = "UNDEFINED"
end

class PuzzleItem
  property number : Int32 = -1
  property fail_message : String = "UNDEFINED"
  property fail_sound : String = "UNDEFINED"
end

class PlayerPawn
  property air_capacity : Float64 = 1.0
  property attack_z_offset : Int32 = 8
  property clear_color_set : Int32 = -1
  # this is a range like "0, 0" so we will grab as a string
  property color_range : String = "UNDEFINED"
  # format: number, name, start, end, color [...] - we will do string
  property color_set : String = "UNDEFINED"
  # format: number, name, table, color - we will do string
  property color_set_file : String = "UNDEFINED"
  property crouch_sprite : String = "UNDEFINED"
  # format: color[, intensity[, damagetype]]
  property damage_screen_color : String = "UNDEFINED"
  property display_name : String = "UNDEFINED"
  property face : String = "UNDEFINED"
  # format: value min, value max
  property failing_scream_speed : String = "UNDEFINED"
  property flechette_type : String = "UNDEFINED"
  property fly_type : Float64 = 1.0
  # format: run, value-run. Default is: 1, 1
  property forward_move : String = "1, 1"
  property grunt_speed : Float64 = 12.0
  property heal_radius_type : String = "UNDEFINED"
  # format: base value, value armor, value sheild, value helm, value amulet
  # we use string
  property hexen_armor : String = "UNDEFINED"
  property invulnerability_mode : String = "UNDEFINED"
  property jump_z : Float64 = 8.0
  property max_health : Int32 = 100
  property morph_weapon : String = "UNDEFINED"
  property mug_shot_max_health : Int32 = -1
  property portrait : String = "UNDEFINED"
  property run_health : Int32 = 0
  property score_icon : String = "UNDEFINED"
  # format: value [value-run]
  property side_move : String = "UNDEFINED"
  property sound_class : String = "UNDEFINED"
  property spawn_class : String = "UNDEFINED"
  # format: classname [amount]
  property start_item : String = "UNDEFINED"
  property teleport_freeze_time : Int32 = 18
  property use_range : Float64 = 64.0
  property view_bob : Float64 = 1.0
  property view_bob_speed : Float64 = 20.0
  property view_height : Float64 = 41.0
  property water_climb_speed : Float64 = 3.5
  # format: slot, weapon1[, weapon2, weapon3, ...]
  property weapon_slot : String = "UNDEFINED"
end

class Powerup
  # can be numeric or string
  property color : String = "UNDEFINED"
  # format [sourcecolor, ]destcolor
  property colormap : String = "UNDEFINED"
  # format: probably usually int value but could be hex like 0x7FFFFFFD
  property duration : String = "UNDEFINED"
  property mode : String = "UNDEFINED"
  property strength : Int32 = 0

  # technically from PowerupGiver class, which only addes this property
  property type : String = "UNDEFINED"
end

class PowerSpeed
  property no_trail : Bool = 0
end

class HealthPickup
  # this probably doesn't pertain much to Doom
  property auto_use : Int32 = 0
end

class MorphProjectile
  property player_class : String = "UNDEFINED"
end
##########################################
# CREATE ACTORS DATABASE
##########################################

# this will download most if not all of the actor content into a format
# that will be readable in Crystal
actordb = Array(Actor).new

# these will track duplicates
duped_names_db = Array(DupedActorName).new
duped_graphics_db = Array(DupedGraphics).new
duped_doomednum_db = Array(DupedDoomednums).new

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

##########################################
# CREATE DIRECTORIES
##########################################

puts "Creating Processing directory..."
Dir.mkdir_p("./Processing/")
puts "Creating Source directory..."
Dir.mkdir_p("./Source/")
puts "Creating Completed directory..."
Dir.mkdir_p("./Completed/")

##########################################
# PRE RUN CLEANUP OPERATION
##########################################

# Clear out the Processing folder prior to copying in the files
# Anything in Processing is fair game for deletion at any time
puts "Deleting all files under Processing directory..."
FileUtils.rm_rf("./Processing/*")
puts "Deleting all files under Completed directory..."
FileUtils.rm_rf("./Completed/*")
puts "Deletion completed."

#########################################
# RUN EXTRACTION PROCESS
#########################################
puts "Extraction process starting..."
# Extract each wad in Source to it's own subdirectory
Dir.each_child("./Source") do |file_name|
  file_path = "./Source/#{file_name}"
  if File.file?(file_path)
    puts "Processing file: #{file_path}"
    system "./#{jeutoolexe} extract \"#{file_path}\" -r"
  end
end
puts "Extraction process complete."

puts "Starting the copy process from Source to Processing..."
# Copy the directories in Source to Processing for processing
# Only the directories are copied
Dir.glob("./Source/*/").each do |path|
  dest_path = File.join("./Processing/", File.basename(path))
  completed_path = File.join("./Completed/", File.basename(path))
  if Dir.exists?(dest_path)
    FileUtils.rm_rf(dest_path)
  end

  FileUtils.cp_r(path, completed_path)
  FileUtils.mv(path, dest_path)
end
puts "Copy from Source to Processing completed."

##########################################
# POST EXTRACTION PROCESSING
##########################################

puts "Starting Processing procedure..."


# Evaluate ZSCRIPT includes
# TBD!!!!!!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1
puts "ZSCRIPT includes: TBD"

puts "DECORATE includes: TBD"

# Build a list of Processing and Built_In_Actors, and a flag to tell it
# not to touch the built in actors
processing_files = Dir.glob("./Processing/*/defs/DECORATE.raw")
built_in_actors = Dir.glob("./Built_In_Actors/*/*.txt")

# String: Dir name, Bool: true = no touchy, false = touchy
no_touchy = Hash(String, Bool).new
processing_files.each do |file_path|
  no_touchy[file_path] = false
end
built_in_actors.each do |file_path|
  no_touchy[file_path] = true
end

# concatenate the two file arrays - built in goes first to avoid getting flagged as dupe
full_dir_list = built_in_actors + processing_files

puts full_dir_list

puts "Removing comments from DECORATE.raw files into DECORATE.nocomments files"
# Remove DECORATE comments
full_dir_list.each do |file_path|
  if no_touchy[file_path] == false
    # puts "Source file (comment removal): #{file_path}"
    # grabbing the wad file source folder name - split on "/" and grab element 2
    # which is essentially the wad name without ".wad" at the end
    wad_folder_name = file_path.split(/\//)[2]
    decorate_source_file = file_path.split(/\//)[4]
    puts "#{wad_folder_name}"
    #dest_path_one = File.dirname(file_path) + "/" + File.basename(file_path) + ".nocomments1"
    #puts "Output file 1 (comment removal): #{dest_path_one}"
    #dest_path_two = File.dirname(file_path) + "/" + File.basename(file_path) + ".nocomments2"
    #puts "Output file 2 (comment removal): #{dest_path_two}"
      
    # Remove block quotes - globally to the entire file
    # puts "Removing block quotes..."
    # input_string = File.read(file_path)
    # output_string = input_string.gsub(%r{/\*.*?\*/}m, "")
    # File.write(dest_path_one, output_string)

    input_file = File.read(file_path)
    #output_file = File.open(dest_path_two, "w")
    
    # Per line processing
    puts "Per line processing..."
    input_file.each_line do |line|
      # Remove comments that start with "//"
      # line = line.gsub(/\/\/.*$/, "")
      # Only perform processing on the line if it is not empty - to save on CPU
      # cycles
      if !line.strip.empty?
        if line =~ /^\s*#include/i
          puts "Include file: " + line
	  # replace line with the full text of the included file
          # Going to try to add it to the end of the array and SEE WHAT HAPPENS!
	  include_file = line.gsub(/#include\s+"(\w+)"/i) { $1.upcase }
          # line = File.read(File.dirname(file_path) + "/" + include_file + ".raw")
          new_directory = File.dirname(file_path) + "/" + include_file + ".raw"
          full_dir_list << new_directory
          no_touchy[new_directory] = false
        end
        
        # put curly braces on their own line
        #line = line.gsub(/.+(\{|\})/) do |match|
        #  "\n#{match}"
        #end
        
        #output_file.puts(line)
        # This block is deprecated but I might need to refer to this code later
        # if line =~ /^\s*actor/i # insert a line break prior to the first
        # opening curly brace "{" # line = line.gsub(/\{/, "\n{") # print the
        # actor (the part before the first line break) #puts "Actor: " +
        # line.gsub(/\n.+$/, "")
        #end
        
      end
    end

    #input_file.close
    #output_file.close

    # reopen the *.nocomments2 file
    input_text = File.read(file_path)
    input_text = input_text.gsub(/^\s*/, "")
  else
    # no_touchy == true
    # no touchy means we skip all that and just open the file for reading
    input_text = File.read(file_path)

    # strip leading whitespace
    input_text = input_text.gsub(/^\s*/, "")
    # file paths are a little different...
    # wad_folder_name
    wad_folder_name = file_path.split(/\//)[2]
    decorate_source_file = file_path.split(/\//)[3]
  end

  # remove "//" comments
  #input_text = input_text.gsub(/\/\/.*$/m, "")
  input_text = input_text.gsub(%r{//[^\n]*}, "")

  # remove /* through */ comments
  input_text = input_text.gsub(/\/\*[\s\S]*\*\//m, "")

  # put curly braces on their own line
  # Add a newline before opening curly braces on their own line
  input_text = input_text.gsub('{', "\n{\n")
  input_text = input_text.gsub('}', "\n}\n")

  # removing any leading or trailing spaces on each line - cleanup
  input_text = input_text.split("\n").map { |line| line.lstrip.strip }.join("\n")

  # remove any blank lines
  input_text = input_text.split("\n").reject { |line| line.strip.empty? }.join("\n")

  # actors = input_text.scan(/^\s*actor\s+.*{(?:[^{}]+|(?R))*?}/mi) actors =
  # input_text.split(/^\s*actor\s+/i)
  #actors = input_text.split(/(^|\n)\s*actor/i)
  # split on "actor" preserving the word "actor" in the text
  input_text = input_text.gsub(/^actor\s+/im, "SPECIALDELIMITERactor ")
  actors = input_text.split("SPECIALDELIMITER")

  # Remove empty strings from the resulting array
  actors.reject! { |actor| actor.strip.empty? }
  
  #actors.compact!

  puts "File Path: #{file_path}"
  puts "Actors:"
 
  actors.each_with_index do |actor, actor_index|
    puts "Actor (#{actor_index}):"
    puts "-----------"
    puts actor
    puts "-----------"
  end

  actors.each_with_index do |actor, actor_index|
    # parse the actor's states, if any
    states_raw = actor.gsub(/^states\n/im, "SPECIALDELIMITERstates\n")

    states_raw_split = states_raw.split("SPECIALDELIMITER")
    states = Hash(String, String).new
    if states_raw_split.size > 1
      states_unformatted = states_raw_split[1]
      
      unless states_unformatted.nil?
        states_unformatted = states_unformatted.split("{")[1]
        states_unformatted = states_unformatted.split("}")[0]
        states_text = states_unformatted.lstrip
      else
        states_text = nil
      end
    else
      states_text = nil
    end
    # now we will split out each state into an array
    unless states_text.nil?
      states_array = states_text.split(/^(\S*)\:/m)
      # delete blank first element
      states_array.delete_at(0)
    end
    # now we turn states_array into states hash
    unless states_array.nil?
      (0..states_array.size - 1).step(2) do |i|
        key = states_array[i].downcase
        j = i + 1
        value = states_array[j]
        states[key] = value
      end
    end
    
    puts "States before:"
    puts states_text
    puts "States after:"
    puts states

    puts "======================="
    # there are a few options here and we need to account for all of them
    # 0 1    2   3        4        5       6       7
    # actor blah
    # actor blah 1234
    # actor blah replaces oldblah
    # actor blah replaces oldblah 1234
    # actor blah :        oldblah
    # actor blah :        oldblah 1234
    # actor blah :        oldblah replaces oldblah
    # actor blah :        oldblah replaces oldblah 1234
  
    # strip leading and trailing whitespace on each line
    lines = actor.lines
    lines.map! { |line| line.lstrip.strip }
    lines.reject! { |line| line.empty? }
    lines.compact!
    actor = lines.join("\n")

    first_line = lines.first
    words = first_line.downcase.split(/\s+/)
    # parse partial comments on the actor line and remove
    partial_comment = -1
    native = false

    # if the last field of the "actor" line is "native" we need to parse that out and note the actor property
    words.each_with_index do |value, word_index|
      if value.downcase.strip == "native"
        native = true
        # partial comment will be set to the lowest word number because all the
        # words after it are a comment as well
        if partial_comment < 0
          partial_comment = word_index
        end
      end
    end

    if partial_comment > 0
      words = words[0..partial_comment - 1]
      puts "Partial comment detected. Updated words array:"
      words.each do |word|
        puts word
      end
    end

    number_of_words = words.size
    puts "Actor: \"#{words[1].downcase}\""
    puts "File: \"#{file_path}\""

    # Create new actor object and populate the information we already collected
    new_actor = Actor.new("#{words[1].downcase}", actor_index)
    new_actor.source_wad_folder = wad_folder_name
    new_actor.source_file = decorate_source_file
    new_actor.file_path = file_path
    new_actor.native = native
    new_actor.states = states

    # number of words == 3 means that word[2] == a number
    if number_of_words == 3
      new_actor.doomednum = words[2].to_i
    end

    # there are 2 possibilities: colon (inheritance), or replaces
    if number_of_words == 4 || number_of_words == 5
      if words[2] =~ /^\s*:\s*/
        new_actor.inherits = words[3].downcase
      elsif words[2].downcase =~ /^\s*replaces\s*/
        new_actor.replaces = words[3].downcase
      else
        puts "Error: word: #{words[2]} is not a colon, or 'replaces'"
      end

      # if there are 4 words, the last must be doomednum
      if number_of_words == 5
        puts words
        new_actor.doomednum = words[4].to_i
      end
    end

    # if there are 5-6 words, it means inherit and replace, and 6 is doomednum
    if number_of_words == 6 || number_of_words == 7
      new_actor.inherits = words[4].downcase
      new_actor.replaces = words[6].downcase
      if number_of_words == 7
        new_actor.doomednum = words[7].to_i
      end
    end

    actor.each_line.with_index do |line, index|
      # ignore first line - we already read it above
      next if index.zero?
      # flag the built in actors
      if no_touchy[file_path] == true
        new_actor.built_in = true
      end

      ##############################################
      # PROPERTY DEFINITIONS
      ##############################################
      # I realize that these are not alphabetical.
      # This is because I am keeping them in the order
      # of the ZDoom wiki. It will make things easier
      # doing it this way.
      ##############################################

      if line =~ /^\s*game\s+/i
        puts "  - Game: " + line.split[1]?.to_s
        new_actor.game = line.split[1]?.to_s
      end

      if line =~ /^\s*spawnid\s+/i
        puts "  - SpawnID: " + line.split[1]?.to_s
        new_actor.spawn_id = line.split[1].to_i
      end

      if line =~ /^\s*conversationid\s+/i
        puts "  - ConversationID: " + line.split[1..-1].join(' ')
        new_actor.conversation_id = line.split[1..-1].join(' ')
      end

      if line =~ /^\s*tag\s+/i
        puts "  - Tag: " + line.split[1..-1].join(' ')
        new_actor.tag = line.split[1..-1].join(' ')
      end

      if line =~ /^\s*health\s+/i && new_actor.name.downcase.strip != "health"
        puts "  - Health: " + line.split[1]?.to_s
        new_actor.health = line.split[1].to_i
      end

      if line =~ /^\s*gibhealth\s+/i
        puts "  - GibHealth: " + line.split[1]?.to_s
        new_actor.gib_health = line.split[1].to_i
      end

      if line =~ /^\s*woundhealth\s+/i
        puts "  - WoundHealth: " + line.split[1]?.to_s
        new_actor.wound_health = line.split[1].to_i
      end

      if line =~ /^\s*reactiontime\s+/i
        puts "  - ReactionTime: " + line.split[1]?.to_s
        new_actor.reaction_time = line.split[1].to_i
      end

      if line =~ /^\s*painchance\s+/i
        puts "  - PainChance: " + line.split[1]?.to_s
        new_actor.pain_chance = "#{line.split[1]?.to_s},#{line.split[2]?.to_s}"
      end

      if line =~ /^\s*painthreshold\s+/i
        puts "  - PainThreshold: " + line.split[1]?.to_s
        new_actor.pain_threshold = line.split[1].to_i
      end

      if line =~ /^\s*damagefactor\s+/i
        puts "  - DamageFactor: " + line.split[1..-1].join(' ')
        new_actor.damage_factor = line.split[1..-1].join(' ')
      end

      if line =~ /^\s*selfdamagefactor\s+/i
        puts "  - SelfDamageFactor: " + line.split[1]?.to_s
        new_actor.self_damage_factor = line.split[1].to_f
      end

      if line =~ /^\s*damagemultiply\s+/i
        puts "  - DamageMultiply: " + line.split[1]?.to_s
        new_actor.damage_multiply = line.split[1].to_f
      end

      if line =~ /^\s*damage\s+/i
        puts "  - Damage: " + line.split[1]?.to_s
        new_actor.damage = line.split[1]?.to_s
      end

      # DamageFunction goes here but it is ZScript specific

      if line =~ /^\s*poisondamage\s+/i
        puts "  - PoisonDamage: " + line.split[1..-1].join(' ')
        new_actor.poison_damage = line.split[1..-1].join(' ')
      end

      if line =~ /^\s*poisondamagetype\s+/i
        puts "  - PoisonDamageType: " + line.split[1..-1].join(' ')
        new_actor.poison_damage_type = line.split[1..-1].join(' ')
      end

      if line =~ /^\s*radiusdamagefactor\s+/i
        puts "  - RadiusDamageFactor: " + line.split[1]?.to_s
        new_actor.radius_damage_factor = line.split[1].to_f
      end

      if line =~ /^\s*ripperlevel\s+/i
        puts "  - RipperLevel: " + line.split[1]?.to_s
        new_actor.ripper_level = line.split[1].to_i
      end

      if line =~ /^\s*riplevelmin\s+/i
        puts "  - RipLevelMin: " + line.split[1]?.to_s
        new_actor.rip_level_min = line.split[1].to_i
      end

      if line =~ /^\s*riplevelmax\s+/i
        puts "  - RipLevelMax: " + line.split[1]?.to_s
        new_actor.rip_level_max = line.split[1].to_i
      end

      if line =~ /^\s*designatedteam\s+/i
        puts "  - DesignatedTeam: " + line.split[1]?.to_s
        new_actor.designated_team = line.split[1].to_i
      end

      if line=~ /^\s*speed\s+/i
        puts "  - Speed: " + line.split[1]?.to_s
        new_actor.speed = line.split[1].to_f
      end

      if line =~ /^\s*vspeed\s+/i
        puts "  - VSpeed: " + line.split[1]?.to_s
        new_actor.v_speed = line.split[1].to_f
      end

      if line=~ /^\s*fastspeed\s+/i
        puts "  - FastSpeed: " + line.split[1]?.to_s
        new_actor.fast_speed = line.split[1].to_i
      end

      if line=~ /^\s*floatspeed\s+/i
        puts "  - FloatSpeed: " + line.split[1]?.to_s
        new_actor.float_speed = line.split[1].to_i
      end

      if line=~ /^\s*species\s+/i
        puts "  - Species: " + line.split[1]?.to_s
        new_actor.species = line.split[1].to_s
      end

      if line=~ /^\s*accuracy\s+/i
        puts "  - Accuracy: " + line.split[1]?.to_s
        new_actor.accuracy = line.split[1].to_i
      end

      if line=~ /^\s*stamina\s+/i
        puts "  - Stamina: " + line.split[1]?.to_s
        new_actor.stamina = line.split[1].to_i
      end

      if line=~ /^\s*activation\s+/i
        puts "  - Activation: " + line.split[1..-1].join(' ')
        new_actor.activation = line.split[1..-1].join(' ')
      end

      if line=~ /^\s*telefogsourcetype\s+/i
        puts "  - TeleFogSourceType: " + line.split[1]?.to_s
        new_actor.tele_fog_source_type = line.split[1].to_s
      end

      if line=~ /^\s*telefogdesttype\s+/i
        puts "  - TeleFogDestType: " + line.split[1]?.to_s
        new_actor.tele_fog_dest_type = line.split[1].to_s
      end

      if line=~ /^\s*threshold\s+/i
        puts "  - Threshold: " + line.split[1]?.to_s
        new_actor.threshold = line.split[1].to_i
      end

      if line=~ /^\s*defthreshold\s+/i
        puts "  - DefThreshold: " + line.split[1]?.to_s
        new_actor.def_threshold = line.split[1].to_i
      end

      if line=~ /^\s*friendlyseeblocks\s+/i
        puts "  - FriendlySeeBlocks: " + line.split[1]?.to_s
        new_actor.friendly_see_blocks = line.split[1].to_i
      end

      if line=~ /^\s*shadowaimfactor\s+/i
        puts "  - ShadowAimFactor: " + line.split[1]?.to_s
        new_actor.shadow_aim_factor = line.split[1].to_f
      end

      if line=~ /^\s*shadowpenaltyfactor\s+/i
        puts "  - ShadowPenaltyFactor: " + line.split[1]?.to_s
        new_actor.shadow_penalty_factor = line.split[1].to_f
      end

      if line =~ /^\s*radius\s+/i
        puts "  - Radius: " + line.split[1]?.to_s
        new_actor.radius = line.split[1].to_f
      end

      if line =~ /^\s*height\s+/i
        puts "  - Height: " + line.split[1]?.to_s
        new_actor.height = line.split[1].to_i
      end

      if line =~ /^\s*deathheight\s+/i
        puts "  - DeathHeight: " + line.split[1]?.to_s
        new_actor.death_height = line.split[1].to_i
      end

      if line =~ /^\s*burnheight\s+/i
        puts "  - BurnHeight: " + line.split[1]?.to_s
        new_actor.burn_height = line.split[1].to_i
      end

      if line =~ /^\s*projectilepassheight\s+/i
        puts "  - ProjectilePassHeight: " + line.split[1]?.to_s
        new_actor.projectile_pass_height = line.split[1].to_i
      end

      if line =~ /^\s*gravity\s+/i
        puts "  - Gravity: " + line.split[1]?.to_s
        new_actor.gravity = line.split[1].to_f
      end

      if line =~ /^\s*friction\s+/i
        puts "  - Height: " + line.split[1]?.to_s
        new_actor.friction = line.split[1].to_f
      end

      if line =~ /^\s*mass\s+/i
        puts "  - Mass: " + line.split[1]?.to_s
        new_actor.mass = line.split[1].to_s
      end

      if line =~ /^\s*maxstepheight\s+/i
        puts "  - MaxStepHeight: " + line.split[1]?.to_s
        new_actor.max_step_height = line.split[1].to_i
      end

      if line =~ /^\s*maxdropoffheight\s+/i
        puts "  - MaxDropOffHeight: " + line.split[1]?.to_s
        new_actor.max_drop_off_height = line.split[1].to_i
      end

      if line =~ /^\s*maxslopesteepness\s+/i
        puts "  - MaxSlopeSteepness: " + line.split[1]?.to_s
        new_actor.max_slope_steepness = line.split[1].to_f
      end

      if line =~ /^\s*bouncetype\s+/i
        puts "  - BounceType: " + line.split[1]?.to_s
        new_actor.bounce_type = line.split[1].to_s
      end

      if line =~ /^\s*bouncefactor\s+/i
        puts "  - BounceFactor: " + line.split[1]?.to_s
        new_actor.bounce_factor = line.split[1].to_f
      end

      if line =~ /^\s*wallbouncefactor\s+/i
        puts "  - WallBounceFactor: " + line.split[1]?.to_s
        new_actor.wall_bounce_factor = line.split[1].to_f
      end

      if line =~ /^\s*bouncecount\s+/i
        puts "  - BounceCount: " + line.split[1]?.to_s
        new_actor.bounce_count = line.split[1].to_i
      end

      if line =~ /^\s*projectilekickback\s+/i
        puts "  - ProjectileKickBack: " + line.split[1]?.to_s
        new_actor.projectile_kick_back = line.split[1].to_i
      end

      if line =~ /^\s*pushfactor\s+/i
        puts "  - PushFactor: " + line.split[1]?.to_s
        new_actor.push_factor = line.split[1].to_f
      end

      if line =~ /^\s*weaveindexxy\s+/i
        puts "  - WeaveIndexXY: " + line.split[1]?.to_s
        new_actor.weave_index_xy = line.split[1].to_i
      end

      if line =~ /^\s*weaveindexz\s+/i
        puts "  - WeaveIndexZ: " + line.split[1]?.to_s
        new_actor.weave_index_z = line.split[1].to_i
      end

      if line =~ /^\s*thrubits\s+/i
        puts "  - ThruBits: " + line.split[1]?.to_s
        new_actor.thru_bits = line.split[1].to_i
      end

      if line =~ /^\s*activesound\s+/i
        puts "  - ActiveSound: " + line.split[1]?.to_s
        new_actor.active_sound = line.split[1].to_s
      end

      if line =~ /^\s*attacksound\s+/i
        puts "  - AttackSound: " + line.split[1]?.to_s
        new_actor.attack_sound = line.split[1].to_s
      end

      if line =~ /^\s*bouncesound\s+/i
        puts "  - BounceSound: " + line.split[1]?.to_s
        new_actor.bounce_sound = line.split[1].to_s
      end

      if line =~ /^\s*crushpainsound\s+/i
        puts "  - CrushPainSound: " + line.split[1]?.to_s
        new_actor.crush_pain_sound = line.split[1].to_s
      end

      if line =~ /^\s*deathsound\s+/i
        puts "  - DeathSound: " + line.split[1]?.to_s
        new_actor.death_sound = line.split[1].to_s
      end

      if line =~ /^\s*howlsound\s+/i
        puts "  - HowlSound: " + line.split[1]?.to_s
        new_actor.howl_sound = line.split[1].to_s
      end

      if line =~ /^\s*painsound\s+/i
        puts "  - PainSound: " + line.split[1]?.to_s
        new_actor.pain_sound = line.split[1].to_s
      end

      if line =~ /^\s*ripsound\s+/i
        puts "  - RipSound: " + line.split[1]?.to_s
        new_actor.rip_sound = line.split[1].to_s
      end

      if line =~ /^\s*seesound\s+/i
        puts "  - SeeSound: " + line.split[1]?.to_s
        new_actor.see_sound = line.split[1].to_s
      end

      if line =~ /^\s*wallbouncesound\s+/i
        puts "  - WallBounceSound: " + line.split[1]?.to_s
        new_actor.wall_bounce_sound = line.split[1].to_s
      end

      if line =~ /^\s*pushsound\s+/i
        puts "  - PushSound: " + line.split[1]?.to_s
        new_actor.push_sound = line.split[1].to_s
      end

      if line =~ /^\s*renderstyle\s+/i
        puts "  - RenderStyle: " + line.split[1]?.to_s
        new_actor.render_style = line.split[1].to_s
      end

      if line =~ /^\s*alpha\s+/i
        puts "  - Alpha: " + line.split[1]?.to_s
        new_actor.alpha = line.split[1].to_f
      end

      if line =~ /^\s*defaultalpha\s+/i
        puts "  - DefaultAlpha: " + line.split[1]?.to_s
        new_actor.default_alpha = line.split[1].to_f
      end

      if line =~ /^\s*stealthalpha\s+/i
        puts "  - StealthAlpha: " + line.split[1]?.to_s
        new_actor.stealth_alpha = line.split[1].to_f
      end

      if line =~ /^\s*xscale\s+/i
        puts "  - XScale: " + line.split[1]?.to_s
        new_actor.x_scale = line.split[1].to_f
      end

      if line =~ /^\s*yscale\s+/i
        puts "  - YScale: " + line.split[1]?.to_s
        new_actor.y_scale = line.split[1].to_f
      end

      if line =~ /^\s*scale\s+/i
        puts "  - Scale: " + line.split[1]?.to_s
        new_actor.scale = line.split[1].to_f
      end

      if line =~ /^\s*lightlevel\s+/i
        puts "  - LightLevel: " + line.split[1]?.to_s
        new_actor.light_level = line.split[1].to_i
      end

      if line =~ /^\s*translation\s+/i
        puts "  - Translation: " + line.split[1..-1].join(' ')
        new_actor.translation = line.split[1..-1].join(' ')
      end

      if line =~ /^\s*bloodcolor\s+/i
        puts "  - BloodColor: " + line.split[1..-1].join(' ')
        new_actor.blood_color = line.split[1..-1].join(' ')
      end

      if line =~ /^\s*bloodtype\s+/i
        puts "  - BloodType: " + line.split[1..-1].join(' ')
        new_actor.blood_type = line.split[1..-1].join(' ')
      end

      if line =~ /^\s*decal\s+/i
        puts "  - Decal: " + line.split[1]?.to_s
        new_actor.decal = line.split[1].to_s
      end

      if line =~ /^\s*stencilcolor\s+/i
        puts "  - StencilColor: " + line.split[1]?.to_s
        new_actor.stencil_color = line.split[1].to_s
      end

      if line =~ /^\s*floatbobphase\s+/i
        puts "  - FloatBobPhase: " + line.split[1]?.to_s
        new_actor.float_bob_phase = line.split[1].to_i
      end

      if line =~ /^\s*floatbobstrength\s+/i
        puts "  - FloatBobStrength: " + line.split[1]?.to_s
        new_actor.float_bob_strength = line.split[1].to_i
      end

      if line =~ /^\s*distancecheck\s+/i
        puts "  - DistanceCheck: " + line.split[1]?.to_s
        new_actor.distance_check = line.split[1]?.to_s
      end

      if line =~ /^\s*spriteangle\s+/i
        puts "  - SpriteAngle: " + line.split[1]?.to_s
        new_actor.sprite_angle = line.split[1].to_i
      end

      if line =~ /^\s*spriterotation\s+/i
        puts "  - SpriteRotation: " + line.split[1]?.to_s
        new_actor.sprite_rotation = line.split[1].to_i
      end

      if line =~ /^\s*visibleangles\s+/i
        puts "  - VisibleAngles: " + line.split[1..-1].join(' ')
        new_actor.visible_angles = line.split[1..-1].join(' ')
      end

      if line =~ /^\s*visiblepitch\s+/i
        puts "  - VisiblePitch: " + line.split[1..-1].join(' ')
        new_actor.visible_pitch = line.split[1..-1].join(' ')
      end

      if line =~ /^\s*renderradius\s+/i
        puts "  - RenderRadius: " + line.split[1]?.to_s
        new_actor.render_radius = line.split[1].to_f
      end

      if line =~ /^\s*cameraheight\s+/i
        puts "  - CameraHeight: " + line.split[1]?.to_s
        new_actor.camera_height = line.split[1].to_i
      end

      if line =~ /^\s*camerafov\s+/i
        puts "  - CameraFOV: " + line.split[1]?.to_s
        new_actor.camera_fov = line.split[1].to_f
      end

      if line =~ /^\s*hitobituary\s+/i
        puts "  - HitObituary: " + line.split[1]?.to_s
        new_actor.hit_obituary = line.split[1].to_s
      end

      if line =~ /^\s*obituary\s+/i
        puts "  - Obituary: " + line.split[1]?.to_s
        new_actor.obituary = line.split[1].to_s
      end

      if line =~/^\s*projectile\s*$/i
        puts "  - Projectile"
        new_actor.projectile = true
      end

      if line =~ /^\s*monster\s*/i
        puts "  - Monster"
        new_actor.monster = true
      end

      if line =~ /^\s*\+ismonster\s*/i
        puts "  - Monster"
        new_actor.monster = true
      end

      if line =~ /^\s*inventory\s*$/i
        puts "  - Inventory"
      end

      if line =~/^\s*weapon\s*$/i
        puts "  - Weapon"
      end

    end

    # Process the Actor's States states =
    #pattern = /^\s*states\s*{([^{}]+|(R))*?}/mi
    #
    #begin
    #  states = pattern.match(actor)
    #  if states
    #    puts "States:"
    #    puts "====="
    #    puts "#{states[1]}"
    #    puts "====="
    #  end
    #rescue e : Regex::Error
    #  puts "Regex match error: #{e.message}"
    #end

    actordb << new_actor

    puts "======================="
  end
end

exit(0)

puts "=========================="
puts "END FILE READING"
puts "=========================="
puts "CHECKING DUPLICATES"
puts "=========================="

# Experiments with a new duplicate detection method...
# We are sorting by the different fields that we want to query by...
# e.g. actors_by_name["doomimp"] will return an array of Actors that are named "doomimp"
actors_by_name = actordb.reduce(Hash(String, Array(Actor)).new) do |acc, actor|
  if acc.fetch(actor.name, nil)
    iteration_array = acc[actor.name]
  else
    iteration_array = Array(Actor).new
  end
  iteration_array << actor
  acc[actor.name] = iteration_array

  acc
end

# the same but with inherited actors
actors_by_inherits = actordb.reduce(Hash(String, Array(Actor)).new) do |acc, actor|
  if acc.fetch(actor.inherits, nil)
    iteration_array = acc[actor.inherits]
  else
    iteration_array = Array(Actor).new
  end
  iteration_array << actor
  acc[actor.inherits] = iteration_array

  acc
end

# the same but with replaced actors
actors_by_replaces = actordb.reduce(Hash(String, Array(Actor)).new) do |acc, actor|
  if acc.fetch(actor.replaces, nil)
    iteration_array = acc[actor.replaces]
  else
    iteration_array = Array(Actor).new
  end
  iteration_array << actor
  acc[actor.replaces] = iteration_array

  acc
end

puts "==================================="
puts "Actor Dupe Count"
puts "==================================="
actors_by_name.each_key do |key|
  puts "Actor Name: #{key}"
  puts "Actor Count: #{actors_by_name[key].size}"
  if actors_by_inherits.fetch(key, nil)
    puts "Inherit Count: #{actors_by_inherits[key].size}"
  end
  if actors_by_replaces.fetch(key, nil)
    puts "Replace Count: #{actors_by_replaces[key].size}"
  end
  puts "----------------------------------"
end

exit(0)

# Check for duplicate names
name_info = Hash(String, Tuple(Int32, Int32)).new

actordb.each_with_index do |actor, actor_index|
  if name_info.fetch(actor.name, nil)
    puts "Duplicate name found:"
    puts "  Name: #{actor.name}"
    puts "  Index 1: #{name_info[actor.name][0]}"
    puts "  Index 2: #{actor_index}"
    puts "  Source: #{actordb[actor_index].source_wad_folder}"
    puts "  Source: #{actordb[name_info[actor.name][0]].source_wad_folder}"

    new_dupe_name = DupedActorName.new(actor.name, actor.source_wad_folder, actordb[name_info[actor.name][0]].source_wad_folder)
    duped_names_db << new_dupe_name
  else
    name_info[actor.name.downcase] = {actor_index, actor.index}
  end
end

# Check for duplicate doomednums
# doomednum_info = Hash(Int32, Tuple(Int32, Int32)).new

actordb.each_with_index do |actor, actor_index|
  if doomednum_info.fetch(actor.doomednum, nil) && actor.doomednum != -1
    puts "Duplicate doomednum found:"
    puts "  Name: #{actor.name}"
    puts "  Doomednum: #{actor.doomednum}"
    puts "  Index 1: #{doomednum_info[actor.doomednum][0]}"
    puts "  Index 2: #{actor_index}"
    puts "  Source: #{actordb[actor_index].source_wad_folder}"
    puts "  Source: #{actordb[doomednum_info[actor.doomednum][0]].source_wad_folder}"

    new_dupe_doomednum = DupedDoomednums.new(actor.name, actor.doomednum, actor.source_wad_folder, actordb[doomednum_info[actor.doomednum][0]].source_wad_folder, actor.built_in)
    duped_doomednum_db << new_dupe_doomednum
  else
    doomednum_info[actor.doomednum] = {actor_index, actor.index}
  end
end

# check duplicate graphic prefixes
graphics_info = Hash(String, String).new

# Specify the directory path
directory_path = "./Processing"

# Get a list of entries in the directory (files and subdirectories)
entries = Dir.entries(directory_path)

# Filter out only the directories (excluding "." and "..")
folders = entries.select { |entry| File.directory?(File.join(directory_path, entry)) && entry != "." && entry != ".." }

puts folders

# Iterate over each folder
folders.each_with_index do |folder, folder_index|
  puts "Processing folder: #{folder}"

  graphics_dir = folder + "/sprites"

  # this should skip this entry if the folder does not exist - it only exists
  # if there are graphics
  next if !File.directory?(File.join(directory_path, graphics_dir))

  # Perform your operations using the folder variable For example, you might
  # want to list files within each folder:
  files_in_folder = Dir.entries(File.join(directory_path, graphics_dir))

  files_in_folder_upcase = files_in_folder.map { |filename| filename.upcase }

  # Filter out "." and ".."
  files_in_folder_pruned = files_in_folder_upcase.select { |entry| entry != "." && entry != ".." }

  # Prune filenames to only the first 4 characters
  pruned_filenames = files_in_folder_pruned.map { |filename| filename[0, 4] }

  # Get unique filename prefixes
  unique_pruned_filenames = pruned_filenames.uniq

  puts unique_pruned_filenames

  unique_pruned_filenames.each do |prefix|
    if graphics_info.fetch(prefix, nil)
      puts "Duplicate graphic prefix found:"
      puts "  Prefix: #{prefix}"
      puts "Source: #{folder}"
      puts "  Source: #{graphics_info[prefix]}"
      new_dupe_graphics = DupedGraphics.new(prefix, folder, graphics_info[prefix])
      duped_graphics_db << new_dupe_graphics
    else
      graphics_info[prefix] = folder
    end
  end
end

puts "==============="
puts "Duped Names DB:"
puts duped_names_db
puts "Duped Doomednum DB:"
puts duped_doomednum_db
puts "Duped Graphics DB:"
puts duped_graphics_db

puts "=========================="
puts "Itemized File Actions"
puts "=========================="
# actor_counter is the UUID for renamed actors
# before: ZombieMan
# after: ZombieMan_MonsterMash_0
actor_counter = 0
# first step is evaluate the list of files that are in scope
# DECORATE.raw is always going to be in scope, but any include file
# is also going to be in scope
file_list = Array(String).new

# format is: filename, line number, replacement line
itemized_line_replacements = Array(Tuple(String, Int32, String)).new
duped_names_db.each_with_index do |duped_actor, duped_actor_index|
  puts "-------------------------------------"
  puts "Duped Actor Name: #{duped_actor.name}"
  puts "-------------------------------------"
  file_path = "./Completed/" + duped_actor.wad_name + "/defs/DECORATE.raw"
  puts " - File Path: #{file_path}"

  # this is the replacement text that we will use for the duration of this loop
  substitute_actor = "#{duped_actor.name}_MonsterMash_#{actor_counter}"

  file_list = Array(String).new
  file_list << file_path
  puts " - Includes:"
  File.open(file_path) do |file|
    file.each_line do |line|
      if line.starts_with?("#include")
        include_file_modified = line.strip.lchop("#include ").strip('"').upcase
        file_path = "./Completed/" + duped_actor.wad_name + "/defs/" + include_file_modified + ".raw"
        puts " - Include file: #{file_path}"
        file_list << file_path
      end
    end
  end

  file_list = file_list.uniq
  puts "File list: #{file_list}"
  puts "Line changes: "
  file_list.each do |file|
    puts "-------------"
    puts "File: #{file}"
    File.open(file) do |text|
      text.each_line.with_index do |line, line_number|
        if line.downcase.starts_with?("actor".downcase)
          if (parts = line.strip.split(" ")).size > 1 && parts[1].downcase == duped_actor.name.downcase
            puts "Actor Definition (#{line_number}): \"#{line}\""
            actor_regex = "#{line.strip.split(" ")[1]}"
            replacement_line = line.gsub(Regex.new(actor_regex), substitute_actor)
            puts "Replacement Actor Definition: \"#{replacement_line}\""
            itemized_line_replacement = {file, line_number + 1, replacement_line}
            itemized_line_replacements << itemized_line_replacement
          end
        elsif line.downcase.includes?("\"#{duped_actor.name.downcase}\"")
          puts "Line (#{line_number}) matches: #{line}"
          actor_regex = "#{duped_actor.name}"
          replacement_line = line.gsub(/#{actor_regex}/i, substitute_actor) 
          puts "Replacement Line: #{replacement_line}"
          itemized_line_replacement = {file, line_number + 1, replacement_line}
          itemized_line_replacements << itemized_line_replacement
        end
      end
    end
  end
  actor_counter += 1
  puts "------------------------"
end

# Doomednum conflicts
actor_counter = 0
doomednum_counter = 14166

# this will be used to check the actor line to see which field is the doomednum
def numeric?(str : String) : Bool
  str.to_i? != nil
end

duped_doomednum_db.each_with_index do |duped_doomednum, doomednum_index|
  next if duped_doomednum.built_in == true
  puts "-------------------------------------"
  puts "Duped Doomednum: #{duped_doomednum.doomednum}"
  puts "-------------------------------------"
  file_path = "./Completed/" + duped_doomednum.wad_name + "/defs/DECORATE.raw"
  puts " - File Path: #{file_path}"

  # this is the replacement text that we will use for the duration of this loop
  substitute_doomednum = -1
  # this is going to start counting at 14166 which should be a nice happy starting point based on ZDoom wiki
  while true
    if doomednum_info.fetch(doomednum_counter, nil)
      doomednum_counter += 1
    else
      substitute_doomednum = doomednum_counter
      doomednum_counter += 1
      puts "Substitute Doomednum Allocated: #{substitute_doomednum}"
      # I don't think we need to track the actor numbers in this code, but we already
      # have a database of numbers going, so pardon the jankey solution with -1, -1
      doomednum_info[substitute_doomednum] = {-1, -1}
      break
    end
  end

  file_list = Array(String).new
  file_list << file_path
  puts " - Includes:"
  File.open(file_path) do |file|
    file.each_line do |line|
      if line.starts_with?("#include")
        include_file_modified = line.strip.lchop("#include ").strip('"').upcase
        file_path = "./Completed/" + duped_doomednum.wad_name + "/defs/" + include_file_modified + ".raw"
        puts " - Include file: #{file_path}"
        file_list << file_path
      end
    end
  end

  file_list = file_list.uniq
  puts "File list: #{file_list}"
  puts "Line changes: "
  file_list.each do |file|
    puts "-------------"
    puts "File: #{file}"
    File.open(file) do |text|
      text.each_line.with_index do |line, line_number|
        if line.downcase.starts_with?("actor".downcase)
          puts "Actor Line: #{line}"
          parts = line.strip.split(/\s+/)
          # find the doomednum in actor line - it will be the first number
          doomednum_field = -1
          parts.each_with_index do |part, part_index|
            if numeric?(part)
              doomednum_field = part_index
              break
            end
          end
          next if doomednum_field == -1

          puts "Parts[doomednum_field] = #{parts[doomednum_field]}"
          if parts[doomednum_field].to_i == duped_doomednum.doomednum
            puts "Actor Definition (#{line_number}): \"#{line}\""
            doomednum_regex = "#{line.strip.split(" ")[doomednum_field]}"
            replacement_line = line.gsub(Regex.new(doomednum_regex), substitute_doomednum)
            puts "Replacement Actor Definition: \"#{replacement_line}\""
            itemized_line_replacement = {file, line_number + 1, replacement_line}
            itemized_line_replacements << itemized_line_replacement
          end
        end
      end
    end
  end
end

######################
# Evaluate Inheritance
######################
# 1) we need to compile a list of inherited actors and inheritance depth
# 2) working backwards from highest inheritance depth, we need to replace the monster and then rewrite the inheritance property
#    e.g. actor1 : actor2, actor2 : actor3, actor 3: actor4
#    so in this example we do
#      set actor3 to actor4, then overwrite inherits, and any defined properties
#      set actor2 to actor3, then overwrite inherits, and any defined properties
#      set actor1 to actor2, then overwrite inherits, and any defined properties

puts "#################################"
puts "# Evaluating Inheritance"
puts "#################################"

# creating a default actor to do some property math (sort of as a mask, if that makes sense)
default_actor = Actor.new("default", 1)

property_list = default_actor.property_list

actordb.each_with_index do |actor, actor_index|
  # inheritance depth, actor
  inheritance_info = Hash(Int32, String).new
  inherited_actor_name = actor.inherits
  inheritance_depth = 0
  puts "-----------------"
  puts "Actor: #{actor.name}"
  while inherited_actor_name != "UNDEFINED"
    puts "Inherits: #{inherited_actor_name}" 
    sleep 20.milliseconds
    inheritance_info[inheritance_depth] = inherited_actor_name
    inheritance_depth += 1
    if name_info.fetch(inherited_actor_name, nil)
      if actors_by_name[inherited_actor_name].size == 1
        inherited_actor_name = actors_by_name[inherited_actor_name][0].inherits
      elsif actors_by_name[inherited_actor_name].size > 1
        # we need to determine if there are more than one wad that has this actor name
        wad_dupe_counter = 0
        actors_by_name[inherited_actor_name].each_with_index do |actor_by_name, actor_by_name_index|
          if actor_by_name.built_in == false
            wad_dupe_counter += 1
            inherited_actor_name = actor_by_name.inherits
          end
          if wad_dupe_counter == 2
            puts "Fatal Error: inherited actor name is duplicated:"
            puts actor_by_name.name
            exit(1)
          end
        end
      end
    else
      puts "Error: inherited actor #{inherited_actor_name} is not present in source wads"
      break
    end    
  end
end

# Monsters without IDs
puts "==================================="
puts "Monsters Without IDs"
puts "==================================="
actordb.each_with_index do |actor, actor_index|
  if actor.monster == true && actor.doomednum == -1
    puts "======================================"
    puts "Actor with no doomednum:"
    puts "Actor: #{actor.name}"
    puts "Wad: #{actor.source_wad_folder}"

    # evaluate includes
    file_path = "./Completed/" + actor.source_wad_folder + "/defs/DECORATE.raw"
    file_list = Array(String).new
    file_list << file_path
    File.open(file_path) do |file|
      file.each_line do |line|
        if line.starts_with?("#include")
          include_file_modified = line.strip.lchop("#include ").strip('"').upcase
          file_path = "./Completed/" + actor.source_wad_folder + "/defs/" + include_file_modified + ".raw"
          file_list << file_path
        end
      end
    end
    
    file_list = file_list.uniq

    puts "File list: #{file_list}"
    puts "Line changes: "
    file_list.each do |file|
      puts "-------------"
      puts "File: #{file}"
      File.open(file) do |text|
        text.each_line.with_index do |line, line_number|
          actor_parts = line.strip.split(/\s+/)
          if line.downcase.starts_with?("actor".downcase) && actor_parts[1].downcase == actor.name
            puts "ACTOR DETECTED: #{line}"
            parts = line.strip.split(/\s+/)
            puts "ACTOR: #{parts[1]}"
             

            # doomednum goes at the end, so we just need to evaluate if there is
            # any comments
            last_index = -1
            parts.each_with_index do |part, part_index|
              if part =~ /^\/\//
                break
              end
              last_index = part_index
            end

            parts[last_index] = parts[last_index] + " #{doomednum_counter}"
            doomednum_counter += 1
            replacement_line = parts.join(" ")
            puts "Actor Definition (#{line_number}): \"#{line}\""
            puts "Replacement Actor Definition: \"#{replacement_line}\""
            itemized_line_replacement = {file, line_number + 1, replacement_line}
            itemized_line_replacements << itemized_line_replacement
          end
        end
      end
    end
  end
end

puts "Itemized line replacements: #{itemized_line_replacements}"

puts "ACTOR LIST:"
actordb.each do |actor|
  puts "-------------------------"
  puts "Actor index: #{actor.index}"
  puts "Actor name: #{actor.name}"
  puts "Actor source_wad_folder: #{actor.source_wad_folder}"
  puts "Actor source_file: #{actor.source_file}"
  puts "Actor doomednum: #{actor.doomednum}"
  puts "Actor inherits: #{actor.inherits}"
  puts "Actor replaces: #{actor.replaces}"
  puts "-------------------------"
end

puts "SCRIPT ENDED SUCCESSFULLY"
