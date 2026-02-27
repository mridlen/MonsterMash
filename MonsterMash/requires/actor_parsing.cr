###############################################################################
# actor_parsing.cr — DECORATE/ZSCRIPT actor property and flag parsing
#
# Contains the data-driven dispatch tables for setting boolean flags and
# properties on Actor objects from parsed DECORATE/ZSCRIPT text.
###############################################################################

# Sets a boolean flag on an actor by name. Returns true if the flag was recognized.
def set_actor_flag(actor : Actor, flag_name : String, value : Bool) : Bool
  # Actor-level flags (direct properties)
  case flag_name
  when "interpolateangles"    then actor.interpolateangles = value
  when "flatsprite"           then actor.flatsprite = value
  when "rollsprite"           then actor.rollsprite = value
  when "wallsprite"           then actor.wallsprite = value
  when "rollcenter"           then actor.rollcenter = value
  when "spriteangle"          then actor.spriteangle = value
  when "spriteflip"           then actor.spriteflip = value
  when "xflip"                then actor.xflip = value
  when "yflip"                then actor.yflip = value
  when "maskrotation"         then actor.maskrotation = value
  when "absmaskangle"         then actor.absmaskangle = value
  when "absmaskpitch"         then actor.absmaskpitch = value
  when "dontinterpolate"      then actor.dontinterpolate = value
  when "zdoomtrans"           then actor.zdoomtrans = value
  when "absviewangles"        then actor.absviewangles = value
  when "castspriteshadow"     then actor.castspriteshadow = value
  when "nospriteshadow"       then actor.nospriteshadow = value
  when "masternosee"          then actor.masternosee = value
  when "addlightlevel"        then actor.addlightlevel = value
  when "invisibleinmirrors"   then actor.invisibleinmirrors = value
  when "onlyvisibleinmirrors" then actor.onlyvisibleinmirrors = value
  when "solid"                then actor.solid = value
  when "shootable"            then actor.shootable = value
  when "float"                then actor.float = value
  when "nogravity"            then actor.nogravity = value
  when "windthrust"           then actor.windthrust = value
  when "pushable"             then actor.pushable = value
  when "dontfall"             then actor.dontfall = value
  when "canpass"              then actor.canpass = value
  when "actlikebridge"        then actor.actlikebridge = value
  when "noblockmap"           then actor.noblockmap = value
  when "movewithsector"       then actor.movewithsector = value
  when "relativetofloor"      then actor.relativetofloor = value
  when "noliftdrop"           then actor.noliftdrop = value
  when "slidesonwalls"        then actor.slidesonwalls = value
  when "nodropoff"            then actor.nodropoff = value
  when "noforwardfall"        then actor.noforwardfall = value
  when "notrigger"            then actor.notrigger = value
  when "blockedbysolidactors" then actor.blockedbysolidactors = value
  when "blockasplayer"        then actor.blockasplayer = value
  when "nofriction"           then actor.nofriction = value
  when "nofrictionbounce"     then actor.nofrictionbounce = value
  when "falldamage"           then actor.falldamage = value
  when "allowthrubits"        then actor.allowthrubits = value
  when "crosslinecheck"       then actor.crosslinecheck = value
  when "alwaysrespawn"        then actor.alwaysrespawn = value
  when "ambush"               then actor.ambush = value
  when "avoidmelee"           then actor.avoidmelee = value
  when "boss"                 then actor.boss = value
  when "dontcorpse"           then actor.dontcorpse = value
  when "dontfacetalker"       then actor.dontfacetalker = value
  when "dormant"              then actor.dormant = value
  when "friendly"             then actor.friendly = value
  when "jumpdown"             then actor.jumpdown = value
  when "lookallaround"        then actor.lookallaround = value
  when "missileevenmore"      then actor.missileevenmore = value
  when "missilemore"          then actor.missilemore = value
  when "neverrespawn"         then actor.neverrespawn = value
  when "nosplashalert"        then actor.nosplashalert = value
  when "notargetswitch"       then actor.notargetswitch = value
  when "noverticalmeleerange" then actor.noverticalmeleerange = value
  when "quicktoretaliate"     then actor.quicktoretaliate = value
  when "standstill"           then actor.standstill = value
  when "avoidhazards"         then actor.avoidhazards = value
  when "stayonlift"           then actor.stayonlift = value
  when "dontfollowplayers"    then actor.dontfollowplayers = value
  when "seefriendlymonsters"  then actor.seefriendlymonsters = value
  when "cannotpush"           then actor.cannotpush = value
  when "noteleport"           then actor.noteleport = value
  when "activateimpact"       then actor.activateimpact = value
  when "canpushwalls"         then actor.canpushwalls = value
  when "canusewalls"          then actor.canusewalls = value
  when "activatemcross"       then actor.activatemcross = value
  when "activatepcross"       then actor.activatepcross = value
  when "cantleavefloorpic"    then actor.cantleavefloorpic = value
  when "telestomp"            then actor.telestomp = value
  when "notelestomp"          then actor.notelestomp = value
  when "staymorphed"          then actor.staymorphed = value
  when "canblast"             then actor.canblast = value
  when "noblockmonst"         then actor.noblockmonst = value
  when "allowthruflags"       then actor.allowthruflags = value
  when "thrughost"            then actor.thrughost = value
  when "thruactors"           then actor.thruactors = value
  when "thruspecies"          then actor.thruspecies = value
  when "mthruspecies"         then actor.mthruspecies = value
  when "spectral"             then actor.spectral = value
  when "frightened"           then actor.frightened = value
  when "frightening"          then actor.frightening = value
  when "notarget"             then actor.notarget = value
  when "nevertarget"          then actor.nevertarget = value
  when "noinfightspecies"     then actor.noinfightspecies = value
  when "forceinfighting"      then actor.forceinfighting = value
  when "noinfighting"         then actor.noinfighting = value
  when "notimefreeze"         then actor.notimefreeze = value
  when "nofear"               then actor.nofear = value
  when "cantseek"             then actor.cantseek = value
  when "seeinvisible"         then actor.seeinvisible = value
  when "dontthrust"           then actor.dontthrust = value
  when "allowpain"            then actor.allowpain = value
  when "usekillscripts"       then actor.usekillscripts = value
  when "nokillscripts"        then actor.nokillscripts = value
  when "stoprails"            then actor.stoprails = value
  when "minvisible"           then actor.minvisible = value
  when "mvisblocked"          then actor.mvisblocked = value
  when "shadowaim"            then actor.shadowaim = value
  when "doshadowblock"        then actor.doshadowblock = value
  when "shadowaimvert"        then actor.shadowaimvert = value
  when "invulnerable"         then actor.invulnerable = value
  when "buddha"               then actor.buddha = value
  when "reflective"           then actor.reflective = value
  when "shieldreflect"        then actor.shieldreflect = value
  when "deflect"              then actor.deflect = value
  when "mirrorreflect"        then actor.mirrorreflect = value
  when "aimreflect"           then actor.aimreflect = value
  when "thrureflect"          then actor.thrureflect = value
  when "noradiusdmg"          then actor.noradiusdmg = value
  when "dontblast"            then actor.dontblast = value
  when "shadow"               then actor.shadow = value
  when "ghost"                then actor.ghost = value
  when "dontmorph"            then actor.dontmorph = value
  when "dontsquash"           then actor.dontsquash = value
  when "noteleother"          then actor.noteleother = value
  when "harmfriends"          then actor.harmfriends = value
  when "dontdrain"            then actor.dontdrain = value
  when "dontrip"              then actor.dontrip = value
  when "bright"               then actor.bright = value
  when "invisible"            then actor.invisible = value
  when "noblood"              then actor.noblood = value
  when "noblooddecals"        then actor.noblooddecals = value
  when "stealth"              then actor.stealth = value
  when "floorclip"            then actor.floorclip = value
  when "spawnfloat"           then actor.spawnfloat = value
  when "spawnceiling"         then actor.spawnceiling = value
  when "floatbob"             then actor.floatbob = value
  when "noicedeath"           then actor.noicedeath = value
  when "dontgib"              then actor.dontgib = value
  when "dontsplash"           then actor.dontsplash = value
  when "dontoverlap"          then actor.dontoverlap = value
  when "randomize"            then actor.randomize = value
  when "fixmapthingpos"       then actor.fixmapthingpos = value
  when "fullvolactive"        then actor.fullvolactive = value
  when "fullvoldeath"         then actor.fullvoldeath = value
  when "fullvolsee"           then actor.fullvolsee = value
  when "nowallbouncesnd"      then actor.nowallbouncesnd = value
  when "visibilitypulse"      then actor.visibilitypulse = value
  when "rockettrail"          then actor.rockettrail = value
  when "grenadetrail"         then actor.grenadetrail = value
  when "nobouncesound"        then actor.nobouncesound = value
  when "noskin"               then actor.noskin = value
  when "donttranslate"        then actor.donttranslate = value
  when "nopain"               then actor.nopain = value
  when "forceybillboard"      then actor.forceybillboard = value
  when "forcexybillboard"     then actor.forcexybillboard = value
  when "missile"              then actor.missile = value
  when "ripper"               then actor.ripper = value
  when "nobossrip"            then actor.nobossrip = value
  when "nodamagethrust"       then actor.nodamagethrust = value
  when "dontreflect"          then actor.dontreflect = value
  when "noshieldreflect"      then actor.noshieldreflect = value
  when "floorhugger"          then actor.floorhugger = value
  when "ceilinghugger"        then actor.ceilinghugger = value
  when "bloodlessimpact"      then actor.bloodlessimpact = value
  when "bloodsplatter"        then actor.bloodsplatter = value
  when "foilinvul"            then actor.foilinvul = value
  when "foilbuddha"           then actor.foilbuddha = value
  when "seekermissile"        then actor.seekermissile = value
  when "screenseeker"         then actor.screenseeker = value
  when "skyexplode"           then actor.skyexplode = value
  when "noexplodefloor"       then actor.noexplodefloor = value
  when "strifedamage"         then actor.strifedamage = value
  when "extremedeath"         then actor.extremedeath = value
  when "noextremedeath"       then actor.noextremedeath = value
  when "dehexplosion"         then actor.dehexplosion = value
  when "piercearmor"          then actor.piercearmor = value
  when "forceradiusdmg"       then actor.forceradiusdmg = value
  when "forcezeroradiusdmg"   then actor.forcezeroradiusdmg = value
  when "spawnsoundsource"     then actor.spawnsoundsource = value
  when "painless"             then actor.painless = value
  when "forcepain"            then actor.forcepain = value
  when "causepain"            then actor.causepain = value
  when "dontseekinvisible"    then actor.dontseekinvisible = value
  when "stepmissile"          then actor.stepmissile = value
  when "additivepoisondamage"    then actor.additivepoisondamage = value
  when "additivepoisonduration"  then actor.additivepoisonduration = value
  when "poisonalways"         then actor.poisonalways = value
  when "hittarget"            then actor.hittarget = value
  when "hitmaster"            then actor.hitmaster = value
  when "hittracer"            then actor.hittracer = value
  when "hitowner"             then actor.hitowner = value
  when "bounceonwalls"        then actor.bounceonwalls = value
  when "bounceonfloors"       then actor.bounceonfloors = value
  when "bounceonceilings"     then actor.bounceonceilings = value
  when "allowbounceonactors"  then actor.allowbounceonactors = value
  when "bounceautooff"        then actor.bounceautooff = value
  when "bounceautooffflooronly" then actor.bounceautooffflooronly = value
  when "bouncelikeheretic"    then actor.bouncelikeheretic = value
  when "bounceonactors"       then actor.bounceonactors = value
  when "bounceonunrippables"  then actor.bounceonunrippables = value
  when "explodeonwater"       then actor.explodeonwater = value
  when "canbouncewater"       then actor.canbouncewater = value
  when "mbfbouncer"           then actor.mbfbouncer = value
  when "usebouncestate"       then actor.usebouncestate = value
  when "dontbounceonshootables" then actor.dontbounceonshootables = value
  when "dontbounceonsky"      then actor.dontbounceonsky = value
  when "iceshatter"           then actor.iceshatter = value
  when "dropped"              then actor.dropped = value
  when "ismonster"            then actor.ismonster = value
  when "corpse"               then actor.corpse = value
  when "countitem"            then actor.countitem = value
  when "countkill"            then actor.countkill = value
  when "countsecret"          then actor.countsecret = value
  when "notdmatch"            then actor.notdmatch = value
  when "nonshootable"         then actor.nonshootable = value
  when "dropoff"              then actor.dropoff = value
  when "puffonactors"         then actor.puffonactors = value
  when "allowparticles"       then actor.allowparticles = value
  when "alwayspuff"           then actor.alwayspuff = value
  when "puffgetsowner"        then actor.puffgetsowner = value
  when "forcedecal"           then actor.forcedecal = value
  when "nodecal"              then actor.nodecal = value
  when "synchronized"         then actor.synchronized = value
  when "alwaysfast"           then actor.alwaysfast = value
  when "neverfast"            then actor.neverfast = value
  when "oldradiusdmg"         then actor.oldradiusdmg = value
  when "usespecial"           then actor.usespecial = value
  when "bumpspecial"          then actor.bumpspecial = value
  when "bossdeath"            then actor.bossdeath = value
  when "nointeraction"        then actor.nointeraction = value
  when "notautoaimed"         then actor.notautoaimed = value
  when "nomenu"               then actor.nomenu = value
  when "pickup"               then actor.pickup = value
  when "touchy"               then actor.touchy = value
  when "vulnerable"           then actor.vulnerable = value
  when "notonautomap"         then actor.notonautomap = value
  when "weaponspawn"          then actor.weaponspawn = value
  when "getowner"             then actor.getowner = value
  when "seesdaggers"          then actor.seesdaggers = value
  when "incombat"             then actor.incombat = value
  when "noclip"               then actor.noclip = value
  when "nosector"             then actor.nosector = value
  when "icecorpse"            then actor.icecorpse = value
  when "justhit"              then actor.justhit = value
  when "justattacked"         then actor.justattacked = value
  when "teleport"             then actor.teleport = value
  when "e1m8boss"             then actor.e1m8boss = value
  when "e2m8boss"             then actor.e2m8boss = value
  when "e3m8boss"             then actor.e3m8boss = value
  when "e4m6boss"             then actor.e4m6boss = value
  when "e4m8boss"             then actor.e4m8boss = value
  when "inchase"              then actor.inchase = value
  when "unmorphed"            then actor.unmorphed = value
  when "fly"                  then actor.fly = value
  when "onmobj"               then actor.onmobj = value
  when "argsdefined"          then actor.argsdefined = value
  when "nosightcheck"         then actor.nosightcheck = value
  when "crashed"              then actor.crashed = value
  when "warnbot"              then actor.warnbot = value
  when "huntplayers"          then actor.huntplayers = value
  when "nohateplayers"        then actor.nohateplayers = value
  when "scrollmove"           then actor.scrollmove = value
  when "vfriction"            then actor.vfriction = value
  when "bossspawned"          then actor.bossspawned = value
  when "avoidingdropoff"      then actor.avoidingdropoff = value
  when "chasegoal"            then actor.chasegoal = value
  when "inconversation"       then actor.inconversation = value
  when "armed"                then actor.armed = value
  when "falling"              then actor.falling = value
  when "linedone"             then actor.linedone = value
  when "shattering"           then actor.shattering = value
  when "killed"               then actor.killed = value
  when "bosscube"             then actor.bosscube = value
  when "intrymove"            then actor.intrymove = value
  when "handlenodelay"        then actor.handlenodelay = value
  when "flycheat"             then actor.flycheat = value
  when "respawninvul"         then actor.respawninvul = value
  when "lowgravity"           then actor.lowgravity = value
  when "quartergravity"       then actor.quartergravity = value
  when "longmeleerange"       then actor.longmeleerange = value
  when "shortmissilerange"    then actor.shortmissilerange = value
  when "highermprob"          then actor.highermprob = value
  when "fireresist"           then actor.fireresist = value
  when "donthurtspecies"      then actor.donthurtspecies = value
  when "firedamage"           then actor.firedamage = value
  when "icedamage"            then actor.icedamage = value
  when "hereticbounce"        then actor.hereticbounce = value
  when "hexenbounce"          then actor.hexenbounce = value
  when "doombounce"           then actor.doombounce = value
  when "faster"               then actor.faster = value
  when "fastmelee"            then actor.fastmelee = value
  when "explodeondeath"       then actor.explodeondeath = value
  when "allowclientspawn"     then actor.allowclientspawn = value
  when "clientsideonly"       then actor.clientsideonly = value
  when "nonetid"              then actor.nonetid = value
  when "dontidentifytarget"   then actor.dontidentifytarget = value
  when "scorepillar"          then actor.scorepillar = value
  when "serversideonly"       then actor.serversideonly = value
  when "blueteam"             then actor.blueteam = value
  when "redteam"              then actor.redteam = value
  when "node"                 then actor.node = value
  when "basehealth"           then actor.basehealth = value
  when "superhealth"          then actor.superhealth = value
  when "basearmor"            then actor.basearmor = value
  when "superarmor"           then actor.superarmor = value
  # Sub-object flags (inventory, weapon, etc.)
  when "inventory.quiet"               then actor.inventory.quiet = value
  when "inventory.autoactivate"        then actor.inventory.autoactivate = value
  when "inventory.undroppable", "undroppable"  then actor.inventory.undroppable = value
  when "inventory.unclearable"         then actor.inventory.unclearable = value
  when "inventory.invbar", "invbar"    then actor.inventory.invbar = value
  when "inventory.hubpower"            then actor.inventory.hubpower = value
  when "inventory.persistentpower"     then actor.inventory.persistentpower = value
  when "inventory.interhubstrip"       then actor.inventory.interhubstrip = value
  # Note: inventory.pickupflash is a String property (actor name), not a Bool flag.
  # The +INVENTORY.PICKUPFLASH flag form is extremely rare and handled via property.
  when "inventory.alwayspickup"        then actor.inventory.alwayspickup = value
  when "inventory.fancypickupsound", "fancypickupsound" then actor.inventory.fancypickupsound = value
  when "inventory.noattenpickupsound"  then actor.inventory.noattenpickupsound = value
  when "inventory.bigpowerup"          then actor.inventory.bigpowerup = value
  when "inventory.neverrespawn"        then actor.inventory.neverrespawn = value
  when "inventory.keepdepleted"        then actor.inventory.keepdepleted = value
  when "inventory.ignoreskill"         then actor.inventory.ignoreskill = value
  when "inventory.additivetime"        then actor.inventory.additivetime = value
  when "inventory.untossable"          then actor.inventory.untossable = value
  when "inventory.restrictabsolutely"  then actor.inventory.restrictabsolutely = value
  when "inventory.noscreenflash"       then actor.inventory.noscreenflash = value
  when "inventory.tossed"              then actor.inventory.tossed = value
  when "inventory.alwaysrespawn"       then actor.inventory.alwaysrespawn = value
  when "inventory.transfer"            then actor.inventory.transfer = value
  when "inventory.noteleportfreeze"    then actor.inventory.noteleportfreeze = value
  when "inventory.noscreenblink"       then actor.inventory.noscreenblink = value
  when "inventory.ishealth"            then actor.inventory.ishealth = value
  when "inventory.isarmor"             then actor.inventory.isarmor = value
  when "inventory.forcerespawninsurvival" then actor.inventory.forcerespawninsurvival = value
  when "weapon.noautofire"             then actor.weapon.noautofire = value
  when "weapon.readysndhalf"           then actor.weapon.readysndhalf = value
  when "weapon.dontbob"                then actor.weapon.dontbob = value
  when "weapon.axeblood"               then actor.weapon.axeblood = value
  when "weapon.noalert"                then actor.weapon.noalert = value
  when "weapon.ammo_optional"          then actor.weapon.ammo_optional = value
  when "weapon.alt_ammo_optional"      then actor.weapon.alt_ammo_optional = value
  when "weapon.ammo_checkboth"         then actor.weapon.ammo_checkboth = value
  when "weapon.primary_uses_both"      then actor.weapon.primary_uses_both = value
  when "weapon.alt_uses_both"          then actor.weapon.alt_uses_both = value
  when "weapon.wimpy_weapon", "wimpy_weapon"   then actor.weapon.wimpy_weapon = value
  when "weapon.powered_up", "powered_up"       then actor.weapon.powered_up = value
  when "weapon.staff2_kickback"        then actor.weapon.staff2_kickback = value
  when "weapon.explosive"              then actor.weapon.explosive = value
  when "weapon.meleeweapon", "meleeweapon"     then actor.weapon.meleeweapon = value
  when "weapon.bfg"                    then actor.weapon.bfg = value
  when "weapon.cheatnotweapon"         then actor.weapon.cheatnotweapon = value
  when "weapon.noautoswitchto"         then actor.weapon.noautoswitchto = value
  when "weapon.noautoaim"              then actor.weapon.noautoaim = value
  when "weapon.nodeathdeselect"        then actor.weapon.nodeathdeselect = value
  when "weapon.nodeathinput"           then actor.weapon.nodeathinput = value
  when "weapon.allow_with_respawn_invul" then actor.weapon.allow_with_respawn_invul = value
  when "weapon.nolms"                  then actor.weapon.nolms = value
  when "powerspeed.notrail"            then actor.powerspeed.notrail = value
  when "playerpawn.nothrustwheninvul", "nothrustwheninvul"  then actor.player.nothrustwheninvul = value
  when "playerpawn.cansupermorph", "cansupermorph"          then actor.player.cansupermorph = value
  when "playerpawn.crouchablemorph"    then actor.player.crouchablemorph = value
  when "playerpawn.weaponlevel2ended"  then actor.player.weaponlevel2ended = value
  else
    return false
  end
  true
end

# Sets a property value on an actor. Returns true if recognized.
def set_actor_property(actor : Actor, prop_name : String, line : String) : Bool
  # Strip trailing semicolons — ZSCRIPT uses them as line terminators
  clean_line = line.rstrip.rstrip(';').rstrip
  words = clean_line.split
  val1 = words[1]?
  rest = words[1..]?.try(&.join(' ')) || ""

  begin
    case prop_name
    when "health"
      # Avoid collision with the "Health" actor name
      return false if actor.name.downcase.strip == "health"
      # Clamp to Int32 range — some mods use absurdly large values
      health_val = val1.not_nil!.to_i64?
      if health_val
        actor.health = health_val.clamp(Int32::MIN.to_i64, Int32::MAX.to_i64).to_i32
      else
        log(1, "Cannot parse health value: #{val1}")
      end
    when "gibhealth"         then actor.gib_health = val1.not_nil!.to_i
    when "woundhealth"       then actor.wound_health = val1.not_nil!.to_i
    when "reactiontime"      then actor.reaction_time = val1.not_nil!.to_i
    when "painchance"        then actor.pain_chance = "#{val1},#{words[2]?}"
    when "painthreshold"     then actor.pain_threshold = val1.not_nil!.to_i
    when "damagefactor"      then actor.damage_factor = rest
    when "selfdamagefactor"  then actor.self_damage_factor = val1.not_nil!.to_f
    when "damagemultiply"    then actor.damage_multiply = val1.not_nil!.to_f
    when "damage"            then actor.damage = val1.to_s
    when "poisondamage"      then actor.poison_damage = rest
    when "poisondamagetype"  then actor.poison_damage_type = rest
    when "radiusdamagefactor" then actor.radius_damage_factor = val1.not_nil!.to_f
    when "ripperlevel"       then actor.ripper_level = val1.not_nil!.to_i
    when "riplevelmin"       then actor.rip_level_min = val1.not_nil!.to_i
    when "riplevelmax"       then actor.rip_level_max = val1.not_nil!.to_i
    when "designatedteam"    then actor.designated_team = val1.not_nil!.to_i
    when "speed"             then actor.speed = val1.not_nil!.to_f
    when "vspeed"            then actor.v_speed = val1.not_nil!.to_f
    when "fastspeed"         then actor.fast_speed = val1.not_nil!.to_i
    when "floatspeed"        then actor.float_speed = val1.not_nil!.to_i
    when "species"           then actor.species = val1.to_s
    when "accuracy"          then actor.accuracy = val1.not_nil!.to_i
    when "stamina"           then actor.stamina = val1.not_nil!.to_i
    when "activation"        then actor.activation = rest
    when "telefogsourcetype"  then actor.tele_fog_source_type = val1.to_s
    when "telefogdesttype"   then actor.tele_fog_dest_type = val1.to_s
    when "threshold"         then actor.threshold = val1.not_nil!.to_i
    when "defthreshold"      then actor.def_threshold = val1.not_nil!.to_i
    when "friendlyseeblocks" then actor.friendly_see_blocks = val1.not_nil!.to_i
    when "shadowaimfactor"   then actor.shadow_aim_factor = val1.not_nil!.to_f
    when "shadowpenaltyfactor" then actor.shadow_penalty_factor = val1.not_nil!.to_f
    when "radius"            then actor.radius = val1.not_nil!.to_f
    when "height"            then actor.height = val1.not_nil!.to_i
    when "deathheight"       then actor.death_height = val1.not_nil!.to_i
    when "burnheight"        then actor.burn_height = val1.not_nil!.to_i
    when "projectilepassheight" then actor.projectile_pass_height = val1.not_nil!.to_i
    when "gravity"           then actor.gravity = val1.not_nil!.to_f
    when "friction"          then actor.friction = val1.not_nil!.to_f
    when "mass"              then actor.mass = val1.to_s
    when "maxstepheight"     then actor.max_step_height = val1.not_nil!.to_i
    when "maxdropoffheight"  then actor.max_drop_off_height = val1.not_nil!.to_i
    when "maxslopesteepness" then actor.max_slope_steepness = val1.not_nil!.to_f
    when "bouncetype"        then actor.bounce_type = val1.to_s
    when "bouncefactor"      then actor.bounce_factor = val1.not_nil!.to_f
    when "wallbouncefactor"  then actor.wall_bounce_factor = val1.not_nil!.to_f
    when "bouncecount"       then actor.bounce_count = val1.not_nil!.to_i
    when "projectilekickback" then actor.projectile_kick_back = val1.not_nil!.to_i
    when "pushfactor"        then actor.push_factor = val1.not_nil!.to_f
    when "weaveindexxy"      then actor.weave_index_xy = val1.not_nil!.to_i
    when "weaveindexz"       then actor.weave_index_z = val1.not_nil!.to_i
    when "thrubits"          then actor.thru_bits = val1.not_nil!.to_i
    when "activesound"       then actor.active_sound = val1.to_s
    when "attacksound"       then actor.attack_sound = val1.to_s
    when "bouncesound"       then actor.bounce_sound = val1.to_s
    when "crushpainsound"    then actor.crush_pain_sound = val1.to_s
    when "deathsound"        then actor.death_sound = val1.to_s
    when "howlsound"         then actor.howl_sound = val1.to_s
    when "painsound"         then actor.pain_sound = val1.to_s
    when "ripsound"          then actor.rip_sound = val1.to_s
    when "seesound"          then actor.see_sound = val1.to_s
    when "wallbouncesound"   then actor.wall_bounce_sound = val1.to_s
    when "pushsound"         then actor.push_sound = val1.to_s
    when "renderstyle"       then actor.render_style = val1.to_s
    when "alpha"             then actor.alpha = val1.not_nil!.to_f
    when "defaultalpha"      then actor.default_alpha = true
    when "stealthalpha"      then actor.stealth_alpha = val1.not_nil!.to_f
    when "xscale"            then actor.x_scale = val1.not_nil!.to_f
    when "yscale"            then actor.y_scale = val1.not_nil!.to_f
    when "scale"             then actor.scale = val1.not_nil!.to_f
    when "lightlevel"        then actor.light_level = val1.not_nil!.to_i
    when "translation"       then actor.translation = rest
    when "bloodcolor"        then actor.blood_color = rest
    when "bloodtype"         then actor.blood_type = rest
    when "decal"             then actor.decal = val1.to_s
    when "stencilcolor"      then actor.stencil_color = val1.to_s
    when "floatbobphase"     then actor.float_bob_phase = val1.not_nil!.to_i
    when "floatbobstrength"  then actor.float_bob_strength = val1.not_nil!.to_i
    when "distancecheck"     then actor.distance_check = val1.to_s
    when "spriteangle"       then actor.sprite_angle = val1.not_nil!.to_i
    when "spriterotation"    then actor.sprite_rotation = val1.not_nil!.to_i
    when "visibleangles"     then actor.visible_angles = rest
    when "visiblepitch"      then actor.visible_pitch = rest
    when "renderradius"      then actor.render_radius = val1.not_nil!.to_f
    when "cameraheight"      then actor.camera_height = val1.not_nil!.to_i
    when "camerafov"         then actor.camera_fov = val1.not_nil!.to_f
    when "hitobituary"       then actor.hit_obituary = val1.to_s
    when "obituary"          then actor.obituary = val1.to_s
    when "minmissilechance"  then actor.min_missile_chance = val1.not_nil!.to_i
    when "damagetype"        then actor.damage_type = val1.to_s
    when "deathtype"         then actor.death_type = val1.to_s
    when "meleethreshold"    then actor.melee_threshold = val1.not_nil!.to_i
    when "meleerange"        then actor.melee_range = val1.not_nil!.to_i
    when "maxtargetrange"    then actor.max_target_range = val1.not_nil!.to_i
    when "meleedamage"       then actor.melee_damage = val1.not_nil!.to_i
    when "meleesound"        then actor.melee_sound = val1.to_s
    when "missileheight"     then actor.missile_height = val1.not_nil!.to_i
    when "missiletype"       then actor.missile_type = val1.to_s
    when "explosionradius"   then actor.explosion_radius = val1.not_nil!.to_i
    when "explosiondamage"   then actor.explosion_damage = val1.not_nil!.to_i
    when "donthurtshooter"   then actor.dont_hurt_shooter = true
    when "paintype"          then actor.pain_type = val1.to_s
    when "projectile"        then actor.projectile = true
    when "game"              then actor.game = val1.to_s
    when "spawnid"           then actor.spawn_id = val1.not_nil!.to_i
    when "conversationid"    then actor.conversation_id = rest
    when "tag"               then actor.tag = rest
    when "args"              then actor.args = rest
    when "clearflags"        then actor.clear_flags = true
    when "dropitem"          then actor.drop_item = rest
    when "skip_super"        then actor.skip_super = true
    when "visibletoteam"     then actor.visible_to_team = val1.not_nil!.to_i
    # Inventory properties
    when "inventory.amount"           then actor.inventory.amount = val1.not_nil!.to_i
    when "inventory.defmaxamount"     then actor.inventory.defmaxamount = true
    when "inventory.maxamount"        then actor.inventory.maxamount = val1.to_s.gsub("\"", "")
    when "inventory.interhubamount"   then actor.inventory.interhubamount = val1.not_nil!.to_i
    when "inventory.icon"             then actor.inventory.icon = val1.to_s
    when "inventory.althudicon"       then actor.inventory.althudicon = val1.to_s
    when "inventory.pickupmessage"    then actor.inventory.pickupmessage = rest
    when "inventory.pickupsound"      then actor.inventory.pickupsound = val1.to_s
    when "inventory.pickupflash"      then actor.inventory.pickupflash = val1.to_s
    when "inventory.usesound"         then actor.inventory.usesound = val1.to_s
    when "inventory.respawntics"      then actor.inventory.respawntics = val1.not_nil!.to_i
    when "inventory.givequest"        then actor.inventory.givequest = val1.not_nil!.to_i
    when "inventory.forbiddento"      then actor.inventory.forbiddento = val1.to_s
    when "inventory.restrictedto"     then actor.inventory.restrictedto = val1.to_s
    # Weapon properties
    when "weapon.ammogive", "weapon.ammogive1"  then actor.weapon.ammogive = val1.not_nil!.to_i
    when "weapon.ammogive2"           then actor.weapon.ammogive2 = val1.not_nil!.to_i
    when "weapon.ammotype", "weapon.ammotype1"  then actor.weapon.ammotype = val1.to_s
    when "weapon.ammotype2"           then actor.weapon.ammotype2 = val1.to_s
    when "weapon.ammouse", "weapon.ammouse1"    then actor.weapon.ammouse = val1.not_nil!.to_i
    when "weapon.ammouse2"            then actor.weapon.ammouse2 = val1.not_nil!.to_i
    when "weapon.minselectionammo1"   then actor.weapon.minselectionammo1 = val1.not_nil!.to_i
    when "weapon.minselectionammo2"   then actor.weapon.minselectionammo2 = val1.not_nil!.to_i
    when "weapon.bobpivot3d"          then actor.weapon.bobpivot3d = rest
    when "weapon.bobrangex"           then actor.weapon.bobrangex = val1.not_nil!.to_f
    when "weapon.bobrangey"           then actor.weapon.bobrangey = val1.not_nil!.to_f
    when "weapon.bobspeed"            then actor.weapon.bobspeed = val1.not_nil!.to_f
    when "weapon.bobstyle"            then actor.weapon.bobstyle = rest
    when "weapon.kickback"            then actor.weapon.kickback = val1.not_nil!.to_i
    when "weapon.defaultkickback"     then actor.weapon.defaultkickback = true
    when "weapon.readysound"          then actor.weapon.readysound = rest
    when "weapon.selectionorder"      then actor.weapon.selectionorder = val1.not_nil!.to_i
    when "weapon.sisterweapon"        then actor.weapon.sisterweapon = rest
    when "weapon.slotnumber"          then actor.weapon.slotnumber = val1.not_nil!.to_i
    when "weapon.slotpriority"        then actor.weapon.slotpriority = val1.not_nil!.to_f
    when "weapon.upsound"             then actor.weapon.upsound = rest
    when "weapon.weaponscalex"        then actor.weapon.weaponscalex = val1.not_nil!.to_f
    when "weapon.weaponscaley"        then actor.weapon.weaponscaley = val1.not_nil!.to_f
    when "weapon.yadjust"             then actor.weapon.yadjust = val1.not_nil!.to_i
    when "weapon.lookscale"           then actor.weapon.lookscale = val1.not_nil!.to_f
    # Ammo
    when "ammo.backpackamount"        then actor.ammo.backpackamount = val1.not_nil!.to_i
    when "ammo.backpackmaxamount"     then actor.ammo.backpackmaxamount = val1.not_nil!.to_i
    when "ammo.dropamount"            then actor.ammo.dropamount = val1.not_nil!.to_i
    # Armor
    when "armor.saveamount"           then actor.armor.saveamount = val1.not_nil!.to_i
    when "armor.savepercent"          then actor.armor.savepercent = val1.not_nil!.to_f
    # WeaponPiece
    when "weaponpiece.number"         then actor.weaponpiece.number = val1.not_nil!.to_i
    when "weaponpiece.weapon"         then actor.weaponpiece.weapon = rest
    # Health class
    when "health.lowmessage"          then actor.healthclass.lowmessage = rest
    # PuzzleItem
    when "puzzleitem.number"          then actor.puzzleitem.number = val1.not_nil!.to_i
    when "puzzleitem.failmessage"     then actor.puzzleitem.failmessage = rest
    when "puzzleitem.failsound"       then actor.puzzleitem.failsound = val1.to_s
    # PlayerPawn
    when "player.aircapacity"         then actor.player.aircapacity = val1.not_nil!.to_f
    when "player.attackzoffset"       then actor.player.attackzoffset = val1.not_nil!.to_i
    when "player.clearcolorset"       then actor.player.clearcolorset = val1.not_nil!.to_i
    when "player.colorrange"          then actor.player.colorrange = rest
    when "player.colorset"            then actor.player.colorset = val1.to_s
    when "player.colorsetfile"        then actor.player.colorsetfile = rest
    when "player.crouchsprite"        then actor.player.crouchsprite = val1.to_s
    when "player.damagescreencolor"   then actor.player.damagescreencolor = rest
    when "player.displayname"         then actor.player.displayname = val1.to_s
    when "player.face"                then actor.player.face = val1.to_s
    when "player.fallingscreamspeed"  then actor.player.fallingscreamspeed = rest
    when "player.flechettetype"       then actor.player.flechettetype = val1.to_s
    when "player.flybob"              then actor.player.flybob = val1.not_nil!.to_f
    when "player.forwardmove"         then actor.player.forwardmove = rest
    when "player.gruntspeed"          then actor.player.gruntspeed = val1.not_nil!.to_f
    when "player.healradiustype"      then actor.player.healradiustype = val1.to_s
    when "player.hexenarmor"          then actor.player.hexenarmor = val1.to_s
    when "player.invulnerabilitymode" then actor.player.invulnerabilitymode = val1.to_s
    when "player.jumpz"              then actor.player.jumpz = val1.not_nil!.to_f
    when "player.maxhealth"          then actor.player.maxhealth = val1.not_nil!.to_i
    when "player.morphweapon"        then actor.player.morphweapon = val1.to_s
    when "player.mugshotmaxhealth"   then actor.player.mugshotmaxhealth = val1.not_nil!.to_i
    when "player.runhealth"          then actor.player.runhealth = val1.not_nil!.to_i
    when "player.scoreicon"          then actor.player.scoreicon = val1.to_s
    when "player.sidemove"           then actor.player.sidemove = rest
    when "player.soundclass"         then actor.player.soundclass = val1.to_s
    when "player.spawnclass"         then actor.player.spawnclass = val1.to_s
    when "player.startitem"          then actor.player.startitem = rest
    when "player.viewbob"            then actor.player.viewbob = val1.not_nil!.to_f
    when "player.viewheight"         then actor.player.viewheight = val1.not_nil!.to_i
    when "player.waterclimbspeed"    then actor.player.waterclimbspeed = val1.not_nil!.to_f
    when "player.weaponslot"         then actor.player.weaponslot = rest
    # Powerup
    when "powerup.color"             then actor.powerup.color = rest
    when "powerup.colormap"          then actor.powerup.colormap = rest
    when "powerup.duration"          then actor.powerup.duration = val1.to_s
    when "powerup.mode"              then actor.powerup.mode = val1.to_s
    when "powerup.strength"          then actor.powerup.strength = val1.not_nil!.to_f
    when "powerup.type"              then actor.powerup.type = val1.to_s
    # HealthPickup
    when "healthpickup.autouse"      then actor.healthpickup.autouse = val1.not_nil!.to_i
    # MorphProjectile
    when "morphprojectile.playerclass"    then actor.morphprojectile.playerclass = val1.to_s
    when "morphprojectile.monsterclass"   then actor.morphprojectile.monsterclass = val1.to_s
    when "morphprojectile.duration"       then actor.morphprojectile.duration = val1.not_nil!.to_i
    when "morphprojectile.morphstyle"     then actor.morphprojectile.morphstyle = rest
    when "morphprojectile.morphflash"     then actor.morphprojectile.morphflash = rest
    when "morphprojectile.unmorphflash"   then actor.morphprojectile.unmorphflash = rest
    else
      return false
    end
  rescue ex
    log(1, "Failed to parse property '#{prop_name}' from line: #{line} (#{ex.message})")
    return false
  end
  true
end

###############################################################################
# MAIN PARSING LOOP — Parse all DECORATE/ZSCRIPT files into actordb
###############################################################################

# Result container for parse_all_actors
record ParseResult,
  actordb : Array(Actor),
  missing_property_names : Hash(String, Array(String)),
  missing_actor_flags : Hash(String, Array(String))

# Parse all DECORATE/ZSCRIPT actor definitions from the given file list.
# Returns a ParseResult with the populated actordb and missing property/flag tracking.
def parse_all_actors(full_dir_list : Array(String), no_touchy : Hash(String, Bool)) : ParseResult
  log(2, "Starting DECORATE/ZSCRIPT processing...")

  actordb = Array(Actor).new
  missing_property_names = Hash(String, Array(String)).new
  missing_actor_flags = Hash(String, Array(String)).new

  full_dir_list.each do |file_path|
    is_built_in = (no_touchy[file_path] == true)

    # Determine wad folder name and source file
    path_parts = file_path.split("/")
    if is_built_in
      wad_folder_name = path_parts[2]? || "unknown"
      decorate_source_file = path_parts[3]? || "unknown"
    else
      wad_folder_name = path_parts[2]? || "unknown"
      decorate_source_file = path_parts[4]? || "unknown"
    end

    log(3, "Processing: #{wad_folder_name} (#{file_path})")

    unless is_built_in
      # [BUGFIX] V1 had include file handling that used Ruby's $1 syntax.
      # Now we properly resolve includes and add them to the processing queue.
      input_file = safe_read(file_path)
      input_file.each_line do |line|
        if line.strip =~ /^#include/i
          if md = line.match(/"([^"]+)"/i)
            include_name = md[1].upcase
            new_path = File.join(File.dirname(file_path), "#{include_name}.raw")
            unless full_dir_list.includes?(new_path)
              full_dir_list << new_path
              no_touchy[new_path] = false
            end
          end
        end
      end
    end

    # Read and clean the file
    input_text = safe_read(file_path)
    next if input_text.empty?

    # Strip leading whitespace per line
    input_text = input_text.gsub(/^\s*/, "")

    # Preserve //#MonsterMash directives before stripping comments
    # Convert to a non-comment token so they survive comment removal
    input_text = input_text.gsub(/\/\/#MonsterMash\s+(\S+)/i, "MONSTERMASH_DIRECTIVE_\\1")

    # Remove // comments
    input_text = input_text.gsub(%r{//[^\n]*}, "")

    # Remove /* ... */ block comments (non-greedy)
    input_text = input_text.gsub(/\/\*[\s\S]*?\*\//m, "")

    # Put braces on their own lines
    input_text = input_text.gsub('{', "\n{\n")
    input_text = input_text.gsub('}', "\n}\n")

    # Clean up: strip each line, remove blank lines
    input_text = input_text.split("\n").map(&.strip).reject(&.empty?).join("\n")

    # Split on actor/class definitions (DECORATE uses "actor", ZScript uses "class")
    input_text = input_text.gsub(/^actor\s+/im, "SPECIALDELIMITER__actor ")
    input_text = input_text.gsub(/^class\s+/im, "SPECIALDELIMITER__class ")
    actors = input_text.split("SPECIALDELIMITER__")
    actors.reject!(&.strip.empty?)

    actors.each_with_index do |actor_text, actor_index|
      # Extract states before processing
      states_text = extract_states_text(actor_text)
      states = parse_states(states_text)
      actor_no_states = remove_states_block(actor_text)

      # Get case-sensitive version
      lines_with_case = actor_no_states.lines.map(&.strip).reject(&.empty?)
      next if lines_with_case.empty?
      first_line_with_case = lines_with_case.first

      # [BUGFIX] Normalize colon-glued tokens like "RiflePuff:Bulletpuff" into
      # "RiflePuff : Bulletpuff" so the word-count parser handles inheritance
      # correctly and the actor name doesn't include a trailing colon.
      first_line_with_case = first_line_with_case.gsub(/([A-Za-z0-9_]):([A-Za-z])/, "\\1 : \\2")
      first_line_with_case = first_line_with_case.gsub(/([A-Za-z0-9_]):\s/, "\\1 : ")

      name_with_case = first_line_with_case.split[1]?
      next unless name_with_case

      # Lowercase version for parsing
      lines = actor_no_states.lines.map { |l| l.strip.downcase }.reject(&.empty?)
      next if lines.empty?

      first_line = lines.first
      # Apply same colon normalization to lowercase line
      first_line = first_line.gsub(/([a-z0-9_]):([a-z])/, "\\1 : \\2")
      first_line = first_line.gsub(/([a-z0-9_]):\s/, "\\1 : ")
      words = first_line.split

      # Remove "native" keyword from actor line if present
      native = false
      native_idx = words.index("native")
      if native_idx
        native = true
        words = words[0...native_idx]
      end

      num_words = words.size
      log(3, "Actor: \"#{words[1]?}\" from #{file_path}")

      # Create new actor
      new_actor = Actor.new("#{words[1]?}", actor_index)
      new_actor.name_with_case = name_with_case
      new_actor.source_wad_folder = wad_folder_name
      new_actor.source_file = decorate_source_file
      new_actor.file_path = file_path
      new_actor.native = native
      new_actor.states = states
      new_actor.actor_text = actor_no_states
      new_actor.full_actor_text = actor_text
      new_actor.built_in = is_built_in

      # Parse actor line: actor name [: parent] [replaces target] [doomednum]
      parse_actor_definition_line(new_actor, words, num_words, first_line)

      # Parse each property/flag line
      parse_actor_body_lines(new_actor, lines, missing_property_names, missing_actor_flags)

      actordb << new_actor
    end
  end

  log(2, "Parsing complete. Total actors loaded: #{actordb.size}")

  # Report missing properties/flags
  if Config.log_level >= 2
    unless missing_property_names.empty?
      log(2, "=== Missing Properties ===")
      missing_property_names.each { |k, v| log(2, "  #{k}: #{v.uniq.join(", ")}") }
    end
    unless missing_actor_flags.empty?
      log(2, "=== Missing Flags ===")
      missing_actor_flags.each { |k, v| log(2, "  #{k}: #{v.uniq.join(", ")}") }
    end
  end

  ParseResult.new(actordb, missing_property_names, missing_actor_flags)
end

###############################################################################
# ACTOR DEFINITION LINE PARSER
# Parses: actor name [: parent] [replaces target] [doomednum]
###############################################################################

def parse_actor_definition_line(actor : Actor, words : Array(String), num_words : Int32, first_line : String)
  # Possible forms:
  #   actor name                                    (2 words)
  #   actor name doomednum                          (3 words)
  #   actor name : parent                           (4 words)
  #   actor name replaces target                    (4 words)
  #   actor name : parent doomednum                 (5 words)
  #   actor name replaces target doomednum          (5 words)
  #   actor name : parent replaces target           (6 words)
  #   actor name : parent replaces target doomednum (7 words)
  #
  # [BUGFIX] V1 had wrong field indices for 6/7 word forms

  case num_words
  when 3
    actor.doomednum = words[2].to_i? || -1
  when 4
    if words[2] == ":"
      actor.inherits = words[3]
    elsif words[2] == "replaces"
      actor.replaces = words[3]
    else
      log(1, "Unexpected word '#{words[2]}' in actor line: #{first_line}")
    end
  when 5
    if words[2] == ":"
      actor.inherits = words[3]
      actor.doomednum = words[4].to_i? || -1
    elsif words[2] == "replaces"
      actor.replaces = words[3]
      actor.doomednum = words[4].to_i? || -1
    end
  when 6
    # actor name : parent replaces target
    actor.inherits = words[3] if words[2] == ":"
    actor.replaces = words[5] if words[4] == "replaces"
  when 7
    # actor name : parent replaces target doomednum
    actor.inherits = words[3] if words[2] == ":"
    actor.replaces = words[5] if words[4] == "replaces"
    actor.doomednum = words[6].to_i? || -1
  end
end

###############################################################################
# ACTOR BODY LINE PARSER
# Parses property/flag lines from actor body text
###############################################################################

def parse_actor_body_lines(actor : Actor, lines : Array(String),
                           missing_property_names : Hash(String, Array(String)),
                           missing_actor_flags : Hash(String, Array(String)))
  lines.each_with_index do |line, index|
    next if index.zero? # skip actor definition line

    property_name = line.split[0]?.to_s.downcase
    next if property_name.empty?

    # Handle MonsterMash special directives (preserved from //#MonsterMash comments)
    if property_name.starts_with?("monstermash_directive_")
      directive = property_name.sub("monstermash_directive_", "")
      case directive
      when "sliderzero"
        actor.slider_zero = true
        log(2, "  MonsterMash directive: SliderZero for #{actor.name_with_case}")
      when "disable"
        actor.mm_disabled = true
        log(2, "  MonsterMash directive: Disable for #{actor.name_with_case}")
      else
        log(1, "  Unknown MonsterMash directive: #{directive} for #{actor.name_with_case}")
      end
      next
    end

    # Track applied properties/flags
    if property_name =~ /^[\+\-]/
      line.split.each { |flag| actor.flags_applied << flag }
    elsif !%w[{ } action const var #include].includes?(property_name)
      actor.properties_applied << property_name
    end

    # Handle special keywords
    if property_name == "action" || property_name == "const"
      log(3, "  - #{property_name}: #{line}")
      next
    end

    # Handle variable declarations
    if property_name == "var"
      var_type = line.split[1]?.to_s
      var_name = line.split[2]?.to_s
      actor.user_vars[var_name] = var_type
      next
    end

    # Handle "monster" keyword (which also enables ISMONSTER flag and more)
    if property_name =~ /^monster/
      actor.monster = true
      # Handle flags concatenated after "monster" (e.g., "monster+boss")
      remaining = line.lchop("monster").lstrip
      if !remaining.empty?
        # Process remaining flags by re-normalizing
        remaining = remaining.gsub(/\+\s*/, " +").gsub(/\-\s*/, " -").lstrip
        remaining.split.each do |flag|
          # [BUGFIX] V1 used == instead of = for flag_boolean = false
          flag_val = (flag[0] == '+')
          fname = flag.lchop
          unless set_actor_flag(actor, fname, flag_val)
            log(3, "  Unrecognized flag after monster: #{fname}")
          end
        end
      end
      next
    end

    # Handle boolean flags (+FLAG / -FLAG)
    if property_name =~ /^[\+\-]/
      # Normalize spacing: "+FLAG -FLAG2" etc.
      normalized = line.gsub(/\+\s*/, " +").gsub(/\-\s*/, " -").lstrip
      normalized.split.each do |flag|
        # [BUGFIX] V1: `flag_boolean == false` was comparison, not assignment
        flag_val = (flag[0] == '+')
        fname = flag.lchop.downcase

        unless set_actor_flag(actor, fname, flag_val)
          # Track missing flags
          missing_actor_flags[fname] ||= Array(String).new
          missing_actor_flags[fname] << actor.source_wad_folder
          missing_actor_flags[fname].uniq!
        end
      end
      next
    end

    # Handle "+ismonster" as a property name (special case)
    if property_name == "+ismonster"
      actor.ismonster = true
      next
    end

    # Skip structural tokens
    next if property_name == "{" || property_name == "}" || property_name == "#include"

    # Try setting as a known property
    unless set_actor_property(actor, property_name, line)
      # Track missing properties
      missing_property_names[property_name] ||= Array(String).new
      missing_property_names[property_name] << actor.source_wad_folder
    end
  end
end

###############################################################################
# SPAWN STATE VISIBILITY CHECK
###############################################################################

# Check if an actor has a visible spawn state (not TNT1-only)
def has_visible_spawn_state(actor : Actor) : Bool
  spawn_text = actor.states["spawn"]?
  return false if spawn_text.nil? || spawn_text.strip.empty?

  spawn_text.each_line do |line|
    stripped = line.strip
    next if stripped.empty?
    next if stripped.starts_with?("//")
    # First token of a state line is the sprite prefix
    sprite = stripped.split(/\s+/).first?
    next unless sprite
    # Skip directives
    next if sprite.downcase.in?("goto", "stop", "loop", "wait")
    # The sprite is valid if it's not TNT1
    prefix = sprite.size >= 4 ? sprite[0, 4].upcase : sprite.upcase
    return prefix != "TNT1"
  end
  false
end
