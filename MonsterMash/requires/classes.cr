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
  property duped_wad_file_path : String

  def initialize(@name : String, @wad_name : String, @duped_wad_name : String, @duped_wad_file_path : String)
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


class Inventory
  property index : Int32 = 0
  property name : String = "UNDEFINED"

  property amount : Int32 = -1
  property def_max_amount : Bool = false
  # this can be a hex value like 0x... so String is good
  property max_amount : String = "UNDEFINED"
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
  property autoactivate : Bool = false
  property undroppable : Bool = false
  property unclearable : Bool = false
  property invbar : Bool = false
  property hubpower : Bool = false
  property persistentpower : Bool = false
  property interhubstrip : Bool = false
  property pickupflash : Bool = false
  property alwayspickup : Bool = false
  property fancypickupsound : Bool = false
  property noattenpickupsound : Bool = false
  property bigpowerup : Bool = false
  property neverrespawn : Bool = false
  property keepdepleted : Bool = false
  property ignoreskill : Bool = false
  property additivetime : Bool = false
  property untossable : Bool = false
  property restrictabsolutely : Bool = false
  property noscreenflash : Bool = false
  property tossed : Bool = false
  property alwaysrespawn : Bool = false
  property transfer : Bool = false
  property noteleportfreeze : Bool = false
  property noscreenblink : Bool = false
  property ishealth : Bool = false
  property isarmor : Bool = false

  # Zandronum
  property forcerespawninsurvival : Bool = false

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
  property saveamount : Int32 = -1
  property savepercent : Float64 = -1
  property maxfullabsorb : Int32 = -1
  property maxabsorb : Int32 = -1
  property maxsaveamount : Int32 = -1
  property maxbonus : Int32 = -1
  property maxbonusmax : Int32 = -1
end

class Weapon
  property ammogive : Int32 = -1
  property ammogive1 : Int32 = -1
  property ammogive2 : Int32 = -1
  property ammotype : String = "UNDEFINED"
  property ammotype1 : String = "UNDEFINED"
  property ammotype2 : String = "UNDEFINED"
  property ammouse : Int32 = -1
  property ammouse1 : Int32 = -1
  property ammouse2 : Int32 = -1
  property minselectionammo1 : Int32 = -1
  property minselectionammo2 : Int32 = -1
  # this is ZScript only
  property bobpivot3d : String = "UNDEFINED"
  property bobrangex : Float64 = 1.0
  property bobrangey : Float64 = 1.0
  property bobspeed : Float64 = 1.0
  property bobstyle : String = "UNDEFINED"
  property kickback : Int32 = -1
  property defaultkickback : Bool = false
  property readysound : String = "UNDEFINED"
  property selectionorder : Int32 = -1
  property sisterweapon : String = "UNDEFINED"
  property slotnumber : Int32 = -1
  property slotpriority : Float64 = 0.0
  property upsound : String = "UNDEFINED"
  property weaponscalex : Float64 = 1.0
  property weaponscaley : Float64 = 1.2
  # vertial adjustment
  # I think 0 means don't do anything, there is no "safe" undefined value
  property yadjust : Int32 = 0
  # I think this is float, most multipliers are float
  property lookscale : Float64 = 0.0

  property noautofire : Bool = false
  property readysndhalf : Bool = false
  property dontbob : Bool = false
  property axeblood : Bool = false
  property noalert : Bool = false
  property ammo_optional : Bool = false
  property alt_ammo_optional : Bool = false
  property ammo_checkboth : Bool = false
  property primary_uses_both : Bool = false
  property alt_uses_both : Bool = false
  property wimpy_weapon : Bool = false
  property powered_up : Bool = false
  property staff2_kickback : Bool = false
  property explosive : Bool = false
  property meleeweapon : Bool = false
  property bfg : Bool = false
  property cheatnotweapon : Bool = false
  property noautoswitch : Bool = false
  property noautoswitchto : Bool = false
  property noautoaim : Bool = false
  property nodeathdeselect : Bool = false
  property nodeathinput : Bool = false

  # Zandronum
  property allow_with_respawn_invul : Bool = false
  property nolms : Bool = false

end

class Ammo
  property backpackamount : Int32 = -1
  property backpackmaxamount : Int32 = -1
  property dropamount : Int32 = -1
end

class WeaponPiece
  property number : Int32 = -1
  property weapon : String = "UNDEFINED"
end

class Health
  # this is in format: "value, message" so we will just grab the string
  property lowmessage : String = "UNDEFINED"
end

class PuzzleItem
  property number : Int32 = -1
  property failmessage : String = "UNDEFINED"
  property failsound : String = "UNDEFINED"
end

class PlayerPawn
  property aircapacity : Float64 = 1.0
  property attackzoffset : Int32 = 8
  property clearcolorset : Int32 = -1
  # this is a range like "0, 0" so we will grab as a string
  property colorrange : String = "UNDEFINED"
  # format: number, name, start, end, color [...] - we will do string
  property colorset : String = "UNDEFINED"
  # format: number, name, table, color - we will do string
  property colorsetfile : String = "UNDEFINED"
  property crouchsprite : String = "UNDEFINED"
  # format: color[, intensity[, damagetype]]
  property damagescreencolor : String = "UNDEFINED"
  property displayname : String = "UNDEFINED"
  property face : String = "UNDEFINED"
  # format: value min, value max
  property fallingscreamspeed : String = "UNDEFINED"
  property flechettetype : String = "UNDEFINED"
  property flybob : Float64 = 1.0
  # format: run, value-run. Default is: 1, 1
  property forwardmove : String = "1, 1"
  property gruntspeed : Float64 = 12.0
  property healradiustype : String = "UNDEFINED"
  # format: base value, value armor, value sheild, value helm, value amulet
  # we use string
  property hexenarmor : String = "UNDEFINED"
  property invulnerabilitymode : String = "UNDEFINED"
  property jumpz : Float64 = 8.0
  property maxhealth : Int32 = 100
  property morphweapon : String = "UNDEFINED"
  property mugshotmaxhealth : Int32 = -1
  property portrait : String = "UNDEFINED"
  property runhealth : Int32 = 0
  property scoreicon : String = "UNDEFINED"
  # format: value [value-run]
  property sidemove : String = "UNDEFINED"
  property soundclass : String = "UNDEFINED"
  property spawnclass : String = "UNDEFINED"
  # format: classname [amount]
  property startitem : String = "UNDEFINED"
  property teleportfreezetime : Int32 = 18
  property userange : Float64 = 64.0
  property viewbob : Float64 = 1.0
  property viewbobspeed : Float64 = 20.0
  property viewheight : Float64 = 41.0
  property waterclimbspeed : Float64 = 3.5
  # format: slot, weapon1[, weapon2, weapon3, ...]
  property weaponslot : String = "UNDEFINED"

  property nothrustwheninvul : Bool = false
  property cansupermorph : Bool = false
  property crouchablemorph : Bool = false
  property weaponlevel2ended : Bool = false
end

class Powerup
  # can be numeric or string
  property color : String = "UNDEFINED"
  # format [sourcecolor, ]destcolor
  property colormap : String = "UNDEFINED"
  # format: probably usually int value but could be hex like 0x7FFFFFFD
  property duration : String = "UNDEFINED"
  property mode : String = "UNDEFINED"
  property strength : Float64 = 0

  # technically from PowerupGiver class, which only addes this property
  property type : String = "UNDEFINED"
end

class PowerSpeed
  property notrail : Bool = false
end

class HealthPickup
  # this probably doesn't pertain much to Doom
  property autouse : Int32 = 0
end

class MorphProjectile
  property playerclass : String = "UNDEFINED"
  property monsterclass : String = "UNDEFINED"
  property duration : Int32 = -1
  # has a list of flags, we will capture in String
  property morphstyle : String = "UNDEFINED"
  property morphflash : String = "UNDEFINED"
  property unmorphflash : String = "UNDEFINED"
end

puts "Defining Actor Class..."
class Actor
  # we need a unique index id, because actor names might conflict at first
  property index : Int32 = -1

  # these first few are defined on the actor line
  property name : String = "UNDEFINED"
  property name_with_case : String = "UNDEFINED"
  property renamed : String = "UNDEFINED"
  property renamed_with_case : String = "UNDEFINED"
  property inherits : String = "UNDEFINED"
  property replaces : String = "UNDEFINED"
  # -1 will mean undefined
  property doomednum : Int32 = -1
  # this is rare but sometimes pops up and might be useful later
  property native : Bool = false

  # sub classes?
  property inventory : Inventory
  property morphprojectile : MorphProjectile
  property healthpickup : HealthPickup
  property powerspeed : PowerSpeed
  property powerup : Powerup
  property player : PlayerPawn
  property puzzleitem : PuzzleItem
  property healthclass : Health
  property weaponpiece : WeaponPiece
  property ammo : Ammo
  property weapon : Weapon
  property armor : Armor
  property fakeinventory : FakeInventory

  # user var tracking - we are just going to do a hash of name and type (int or float)
  property user_vars : Hash(String, String) = Hash(String, String).new

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

  # property list - for tracking which properties are set on an actor
  property properties_applied : Array(String) = Array(String).new

  # flag list - for tracking which flags are set on an actor
  property flags_applied : Array(String) = Array(String).new

  # this is used for ensuring that the base actor
  # is not removed during duplicate checks
  # For example, we find 3 duplicates of "ImpBomb"
  # then we mark the first one as primary
  property primary : Bool = false

  # Raw actor text
  # actor_text has comments and states removed
  property actor_text : String = "UNDEFINED"
  # full_actor_text has only comments removed
  property full_actor_text : String = "UNDEFINED"

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
  property default_alpha : Bool = false
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
  property melee_sound : String = "UNDEFINED"
  property missile_height : Int32 = -1
  property missile_type : String = "UNDEFINED"
  # default A_Explode is -1, so I'll go with that
  property explosion_radius : Int32 = -1
  property explosion_damage : Int32 = -1
  # deprecated = -1

  property dont_hurt_shooter : Bool = false
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
  #property missile : Int32 = -1
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

  # flags - these are boolean and look like this:
  # +FLAGNAME
  # A '+' indicates true, and '-' indicates false
  # we take them in as boolean
  property interpolateangles : Bool = false
  property flatsprite : Bool = false
  property rollsprite : Bool = false
  property wallsprite : Bool = false
  property rollcenter : Bool = false
  property spriteangle : Bool = false
  property spriteflip : Bool = false
  property xflip : Bool = false
  property yflip : Bool = false
  property maskrotation : Bool = false
  property absmaskangle : Bool = false
  property absmaskpitch : Bool = false
  property dontinterpolate : Bool = false
  property zdoomtrans : Bool = false
  property absviewangles : Bool = false
  property castspriteshadow : Bool = false
  property nospriteshadow : Bool = false
  property masternosee : Bool = false
  property addlightlevel : Bool = false
  property invisibleinmirrors : Bool = false
  property onlyvisibleinmirrors : Bool = false
  property solid : Bool = false
  property shootable : Bool = false
  property float : Bool = false
  property nogravity : Bool = false
  property windthrust : Bool = false
  property pushable : Bool = false
  property dontfall : Bool = false
  property canpass : Bool = false
  property actlikebridge : Bool = false
  property noblockmap : Bool = false
  property movewithsector : Bool = false
  property relativetofloor : Bool = false
  property noliftdrop : Bool = false
  property slidesonwalls : Bool = false
  property nodropoff : Bool = false
  property noforwardfall : Bool = false
  property notrigger : Bool = false
  property blockedbysolidactors : Bool = false
  property blockasplayer : Bool = false
  property nofriction : Bool = false
  property nofrictionbounce : Bool = false
  property falldamage : Bool = false
  property allowthrubits : Bool = false
  property crosslinecheck : Bool = false
  property alwaysrespawn : Bool = false
  property ambush : Bool = false
  property avoidmelee : Bool = false
  property boss : Bool = false
  property dontcorpse : Bool = false
  property dontfacetalker : Bool = false
  property dormant : Bool = false
  property friendly : Bool = false
  property jumpdown : Bool = false
  property lookallaround : Bool = false
  property missileevenmore : Bool = false
  property missilemore : Bool = false
  property neverrespawn : Bool = false
  property nosplashalert : Bool = false
  property notargetswitch : Bool = false
  property noverticalmeleerange : Bool = false
  property quicktoretaliate : Bool = false
  property standstill : Bool = false
  property avoidhazards : Bool = false
  property stayonlift : Bool = false
  property dontfollowplayers : Bool = false
  property seefriendlymonsters : Bool = false
  property cannotpush : Bool = false
  property noteleport : Bool = false
  property activateimpact : Bool = false
  property canpushwalls : Bool = false
  property canusewalls : Bool = false
  property activatemcross : Bool = false
  property activatepcross : Bool = false
  property cantleavefloorpic : Bool = false
  property telestomp : Bool = false
  property notelestomp : Bool = false
  property staymorphed : Bool = false
  property canblast : Bool = false
  property noblockmonst : Bool = false
  property allowthruflags : Bool = false
  property thrughost : Bool = false
  property thruactors : Bool = false
  property thruspecies : Bool = false
  property mthruspecies : Bool = false
  property spectral : Bool = false
  property frightened : Bool = false
  property frightening : Bool = false
  property notarget : Bool = false
  property nevertarget : Bool = false
  property noinfightspecies : Bool = false
  property forceinfighting : Bool = false
  property noinfighting : Bool = false
  property notimefreeze : Bool = false
  property nofear : Bool = false
  property cantseek : Bool = false
  property seeinvisible : Bool = false
  property dontthrust : Bool = false
  property allowpain : Bool = false
  property usekillscripts : Bool = false
  property nokillscripts : Bool = false
  property stoprails : Bool = false
  property minvisible : Bool = false
  property mvisblocked : Bool = false
  property shadowaim : Bool = false
  property doshadowblock : Bool = false
  property shadowaimvert : Bool = false
  property invulnerable : Bool = false
  property buddha : Bool = false
  property reflective : Bool = false
  property shieldreflect : Bool = false
  property deflect : Bool = false
  property mirrorreflect : Bool = false
  property aimreflect : Bool = false
  property thrureflect : Bool = false
  property noradiusdmg : Bool = false
  property dontblast : Bool = false
  property shadow : Bool = false
  property ghost : Bool = false
  property dontmorph : Bool = false
  property dontsquash : Bool = false
  property noteleother : Bool = false
  property harmfriends : Bool = false
  property doharmspecies : Bool = false
  property dontharmclass : Bool = false
  property dontharmspecies : Bool = false
  property nodamage : Bool = false
  property dontrip : Bool = false
  property notelefrag : Bool = false
  property alwaystelefrag : Bool = false
  property dontdrain : Bool = false
  property laxtelefragdmg : Bool = false
  property shadowblock : Bool = false
  property bright : Bool = false
  property invisible : Bool = false
  property noblood : Bool = false
  property noblooddecals : Bool = false
  property stealth : Bool = false
  property floorclip : Bool = false
  property spawnfloat : Bool = false
  property spawnceiling : Bool = false
  property floatbob : Bool = false
  property noicedeath : Bool = false
  property dontgib : Bool = false
  property dontsplash : Bool = false
  property dontoverlap : Bool = false
  property randomize : Bool = false
  property fixmapthingpos : Bool = false
  property fullvolactive : Bool = false
  property fullvoldeath : Bool = false
  property fullvolsee : Bool = false
  property nowallbouncesnd : Bool = false
  property visibilitypulse : Bool = false
  property rockettrail : Bool = false
  property grenadetrail : Bool = false
  property nobouncesound : Bool = false
  property noskin : Bool = false
  property donttranslate : Bool = false
  property nopain : Bool = false
  property forceybillboard : Bool = false
  property forcexybillboard : Bool = false
  property missile : Bool = false
  property ripper : Bool = false
  property nobossrip : Bool = false
  property nodamagethrust : Bool = false
  property dontreflect : Bool = false
  property noshieldreflect : Bool = false
  property floorhugger : Bool = false
  property ceilinghugger : Bool = false
  property bloodlessimpact : Bool = false
  property bloodsplatter : Bool = false
  property foilinvul : Bool = false
  property foilbuddha : Bool = false
  property seekermissile : Bool = false
  property screenseeker : Bool = false
  property skyexplode : Bool = false
  property noexplodefloor : Bool = false
  property strifedamage : Bool = false
  property extremedeath : Bool = false
  property noextremedeath : Bool = false
  property dehexplosion : Bool = false
  property piercearmor : Bool = false
  property forceradiusdmg : Bool = false
  property forcezeroradiusdmg : Bool = false
  property spawnsoundsource : Bool = false
  property painless : Bool = false
  property forcepain : Bool = false
  property causepain : Bool = false
  property dontseekinvisible : Bool = false
  property stepmissile : Bool = false
  property additivepoisondamage : Bool = false
  property additivepoisonduration : Bool = false
  property poisonalways : Bool = false
  property hittarget : Bool = false
  property hitmaster : Bool = false
  property hittracer : Bool = false
  property hitowner : Bool = false
  property bounceonwalls : Bool = false
  property bounceonfloors : Bool = false
  property bounceonceilings : Bool = false
  property allowbounceonactors : Bool = false
  property bounceautooff : Bool = false
  property bounceautooffflooronly : Bool = false
  property bouncelikeheretic : Bool = false
  property bounceonactors : Bool = false
  property bounceonunrippables : Bool = false
  property nowallbouncesnd : Bool = false
  property nobouncesound : Bool = false
  property explodeonwater : Bool = false
  property canbouncewater : Bool = false
  property mbfbouncer : Bool = false
  property usebouncestate : Bool = false
  property dontbounceonshootables : Bool = false
  property dontbounceonsky : Bool = false
  property iceshatter : Bool = false
  property dropped : Bool = false
  property ismonster : Bool = false
  property corpse : Bool = false
  property countitem : Bool = false
  property countkill : Bool = false
  property countsecret : Bool = false
  property notdmatch : Bool = false
  property nonshootable : Bool = false
  property dropoff : Bool = false
  property puffonactors : Bool = false
  property allowparticles : Bool = false
  property alwayspuff : Bool = false
  property puffgetsowner : Bool = false
  property forcedecal : Bool = false
  property nodecal : Bool = false
  property synchronized : Bool = false
  property alwaysfast : Bool = false
  property neverfast : Bool = false
  property oldradiusdmg : Bool = false
  property usespecial : Bool = false
  property bumpspecial : Bool = false
  property bossdeath : Bool = false
  property nointeraction : Bool = false
  property notautoaimed : Bool = false
  property nomenu : Bool = false
  property pickup : Bool = false
  property touchy : Bool = false
  property vulnerable : Bool = false
  property notonautomap : Bool = false
  property weaponspawn : Bool = false
  property getowner : Bool = false
  property seesdaggers : Bool = false
  property incombat : Bool = false
  property noclip : Bool = false
  property nosector : Bool = false
  property icecorpse : Bool = false
  property justhit : Bool = false
  property justattacked : Bool = false
  property teleport : Bool = false
  property blasted : Bool = false
  property explocount : Bool = false
  property skullfly : Bool = false
  property retargetafterslam : Bool = false
  property onlyslamsolid : Bool = false
  property specialfiredamage : Bool = false
  property specialfloorclip : Bool = false
  property summonedmonster : Bool = false
  property special : Bool = false
  property nosavegame : Bool = false
  property e1m8boss : Bool = false
  property e2m8boss : Bool = false
  property e3m8boss : Bool = false
  property e4m6boss : Bool = false
  property e4m8boss : Bool = false
  property map07boss1 : Bool = false
  property map07boss2 : Bool = false
  property inchase : Bool = false
  property unmorphed : Bool = false
  property fly : Bool = false
  property onmobj : Bool = false
  property argsdefined : Bool = false
  property nosightcheck : Bool = false
  property crashed : Bool = false
  property warnbot : Bool = false
  property huntplayers : Bool = false
  property nohateplayers : Bool = false
  property scrollmove : Bool = false
  property vfriction : Bool = false
  property bossspawned : Bool = false
  property avoidingdropoff : Bool = false
  property chasegoal : Bool = false
  property inconversation : Bool = false
  property armed : Bool = false
  property falling : Bool = false
  property linedone : Bool = false
  property shattering : Bool = false
  property killed : Bool = false
  property bosscube : Bool = false
  property intrymove : Bool = false
  property handlenodelay : Bool = false
  property flycheat : Bool = false
  property respawninvul : Bool = false
  property lowgravity : Bool = false
  property quartergravity : Bool = false
  property longmeleerange : Bool = false
  property shortmissilerange : Bool = false
  property highermprob : Bool = false
  property fireresist : Bool = false
  property donthurtspecies : Bool = false
  property firedamage : Bool = false
  property icedamage : Bool = false
  property hereticbounce : Bool = false
  property hexenbounce : Bool = false
  property doombounce : Bool = false
  property faster : Bool = false
  property fastmelee : Bool = false

  # zandronum
  property allowclientspawn : Bool = false
  property clientsideonly : Bool = false
  property nonetid : Bool = false
  property dontidentifytarget : Bool = false
  property scorepillar : Bool = false
  property serversideonly : Bool = false
  property piercearmor : Bool = false
  property blueteam : Bool = false
  property redteam : Bool = false
  property node : Bool = false
  property basehealth : Bool = false
  property superhealth : Bool = false
  property basearmor : Bool = false
  property superarmor : Bool = false
  property explodeondeath : Bool = false

  def initialize(@name : String, @index : Int32)
    @inventory = Inventory.new
    @morphprojectile = MorphProjectile.new
    @healthpickup = HealthPickup.new
    @powerup = Powerup.new
    @player = PlayerPawn.new
    @puzzleitem = PuzzleItem.new
    @healthclass = Health.new
    @weaponpiece = WeaponPiece.new
    @ammo = Ammo.new
    @weapon = Weapon.new
    @armor = Armor.new
    @fakeinventory = FakeInventory.new
    @powerspeed = PowerSpeed.new
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
