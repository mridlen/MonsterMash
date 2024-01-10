puts "START"

puts "Requires..."
require "file"
require "file_utils"
require "regex"

# Other Code Specific To MonsterMash
require "./requires/classes.cr"

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

# < these have been moved to ./requires/classes.cr >

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

missing_property_names = Hash(String, Array(String)).new
missing_actor_flags = Hash(String, Array(String)).new

# Processing on each decorate file, and any included files are added to the end
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
 
  # I might revisit this method later, but for now this is not quite working... :-/
  # actors = input_text.split(/^actor\s+([^\{]*\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi, remove_empty: true)

  puts "Actors:"
  actors.each do |actor|
   puts actor
   puts "------"
  end

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

    #actor_no_states = actor.gsub(/states\s*{[^{}]*}/mi, "")
    actor_no_states = actor.gsub(/states\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi, "")
    #actor.actor_text = actor_no_states
    puts actor_no_states
    puts "==========="
  end
 
  actors.each_with_index do |actor, actor_index|
    # parse the actor's states, if any
    states_raw = actor.gsub(/^states\n/im, "SPECIALDELIMITERstates\n")

    states_raw_split = states_raw.split("SPECIALDELIMITER")
    states = Hash(String, String).new
    states_text = nil
    states_array = nil
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
 
    #actor_no_states = actor.gsub(/states\s*{[^{}]*}/mi, "") 
    actor_no_states = actor.gsub(/states\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi, "") 
    lines = actor_no_states.lines
    # strip leading whitespace, trailing whitespace, and downcase
    lines.map! { |line| line.lstrip.strip.downcase }
    lines.reject! { |line| line.empty? }
    lines.compact!
    actor = lines.join("\n")

    first_line = lines.first
    words = first_line.split
    # parse partial comments on the actor line and remove
    partial_comment = -1
    native = false

    # if the last field of the "actor" line is "native" we need to parse that out and note the actor property
    words.each_with_index do |value, word_index|
      if value == "native"
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
    puts "Actor: \"#{words[1]}\""
    puts "File: \"#{file_path}\""

    # Create new actor object and populate the information we already collected
    new_actor = Actor.new("#{words[1]}", actor_index)
    new_actor.source_wad_folder = wad_folder_name
    new_actor.source_file = decorate_source_file
    new_actor.file_path = file_path
    new_actor.native = native
    new_actor.states = states
    new_actor.actor_text = actor_no_states

    # number of words == 3 means that word[2] == a number
    if number_of_words == 3
      new_actor.doomednum = words[2].to_i
    end

    # there are 2 possibilities: colon (inheritance), or replaces
    if number_of_words == 4 || number_of_words == 5
      if words[2] =~ /^\s*:\s*/
        new_actor.inherits = words[3]
      elsif words[2] =~ /^\s*replaces\s*/
        new_actor.replaces = words[3]
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
      new_actor.inherits = words[4]
      new_actor.replaces = words[6]
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

      # this should give us the first word in the line, which is the property name
      property_name = line.split[0]?.to_s

      # action refers to a function definition in DECORATE or ZSCRIPT
      # we can probably just ignore these
      if property_name == "action"
        if line.split[1]?.to_s == "native"
          puts "  - Action Native: #{line.split[2..-1]?.to_s}"
        else
          puts "  - Action: #{line.split[1..-1]?.to_s}"
        end
      # const = constants, we might need to evaluate these in some rare cases but for now, ignore them
      elsif property_name == "const"
        puts "  - Const: #{line.split[1..-1]?.to_s}"
      # properties that start with '+' or '-' are boolean flags
      elsif property_name =~ /^\s*[\+|\-]/m
        # there may be many flags on one line, so we need to split and process
        # replace any '+' characters with space after them as '+' to remove the whitespace and put a leading space
        line = line.gsub(/\+\s*/, " +")
        # same with '-' characters
        line = line.gsub(/\-\s*/, " -")
        # strip the leading space, so the first character is a '+' or '-'
        line = line.lstrip
        puts "Flag Line (processed): #{line}"
        line.split.each do |flag|
          flag_boolean = false
          if flag.char_at(0) == '+'
            flag_boolean = true
          elsif flag.char_at(0) == '-'
            flag_boolean == false
          end
          flag_name = flag.lchop
          puts "  - Flag: #{flag_name} = #{flag_boolean}"

          # Renderer
          if flag_name == "interpolateangles"
          elsif flag_name == "flatsprite"
          elsif flag_name == "rollsprite"
          elsif flag_name == "wallsprite"
          elsif flag_name == "rollcenter"
          elsif flag_name == "spriteangle"
          elsif flag_name == "spriteflip"
          elsif flag_name == "xflip"
          elsif flag_name == "yflip"
          elsif flag_name == "maskrotation"
          elsif flag_name == "absmaskangle"
          elsif flag_name == "absmaskpitch"
          elsif flag_name == "dontinterpolate"
          elsif flag_name == "zdoomtrans"
          elsif flag_name == "absviewangles"
          elsif flag_name == "castspriteshadow"
          elsif flag_name == "nospriteshadow"
          elsif flag_name == "masternosee"
          elsif flag_name == "addlightlevel"
          elsif flag_name == "invisibleinmirrors"
          elsif flag_name == "onlyvisibleinmirrors"

          # Physics
          elsif flag_name == "solid"
          elsif flag_name == "shootable"
          elsif flag_name == "float"
          elsif flag_name == "nogravity"
          elsif flag_name == "windthrust"
          elsif flag_name == "pushable"
          elsif flag_name == "dontfall"
          elsif flag_name == "canpass"
          elsif flag_name == "actlikebridge"
          elsif flag_name == "noblockmap"
          elsif flag_name == "movewithsector"
          elsif flag_name == "relativetofloor"
          elsif flag_name == "noliftdrop"
          elsif flag_name == "slidesonwalls"
          elsif flag_name == "nodropoff"
          elsif flag_name == "noforwardfall"
          elsif flag_name == "notrigger"
          elsif flag_name == "blockedbysolidactors"
          elsif flag_name == "blockasplayer"
          elsif flag_name == "nofriction"
          elsif flag_name == "nofrictionbounce"
          elsif flag_name == "falldamage"
          elsif flag_name == "allowthrubits"
          elsif flag_name == "crosslinecheck"

          # Behavior"
          elsif flag_name == "alwaysrespawn"
          elsif flag_name == "ambush"
          elsif flag_name == "avoidmelee"
          elsif flag_name == "boss"
          elsif flag_name == "dontcorpse"
          elsif flag_name == "dontfacetalker"
          elsif flag_name == "dormant"
          elsif flag_name == "friendly"
          elsif flag_name == "jumpdown"
          elsif flag_name == "lookallaround"
          elsif flag_name == "missileevenmore"
          elsif flag_name == "missilemore"
          elsif flag_name == "neverrespawn"
          elsif flag_name == "nosplashalert"
          elsif flag_name == "notargetswitch"
          elsif flag_name == "noverticalmeleerange"
          elsif flag_name == "quicktoretaliate"
          elsif flag_name == "standstill"
          elsif flag_name == "avoidhazards"
          elsif flag_name == "stayonlift"
          elsif flag_name == "dontfollowplayers"
          elsif flag_name == "seefriendlymonsters"

          # (In)Abilities
          elsif flag_name == "cannotpush"
          elsif flag_name == "noteleport"
          elsif flag_name == "activateimpact"
          elsif flag_name == "canpushwalls"
          elsif flag_name == "canusewalls"
          elsif flag_name == "activatemcross"
          elsif flag_name == "activatepcross"
          elsif flag_name == "cantleavefloorpic"
          elsif flag_name == "telestomp"
          elsif flag_name == "notelestomp"
          elsif flag_name == "staymorphed"
          elsif flag_name == "canblast"
          elsif flag_name == "noblockmonst"
          elsif flag_name == "allowthruflags"
          elsif flag_name == "thrughost"
          elsif flag_name == "thruactors"
          elsif flag_name == "thruspecies"
          elsif flag_name == "mthruspecies"
          elsif flag_name == "spectral"
          elsif flag_name == "frightened"
          elsif flag_name == "frightening"
          elsif flag_name == "notarget"
          elsif flag_name == "nevertarget"
          elsif flag_name == "noinfightspecies"
          elsif flag_name == "forceinfighting"
          elsif flag_name == "noinfighting"
          elsif flag_name == "notimefreeze"
          elsif flag_name == "nofear"
          elsif flag_name == "cantseek"
          elsif flag_name == "seeinvisible"
          elsif flag_name == "dontthrust"
          elsif flag_name == "allowpain"
          elsif flag_name == "usekillscripts"
          elsif flag_name == "nokillscripts"
          elsif flag_name == "stoprails"
          elsif flag_name == "minvisible"
          elsif flag_name == "mvisblocked"
          elsif flag_name == "shadowaim"
          elsif flag_name == "doshadowblock"
          elsif flag_name == "shadowaimvert"

          # Defenses
          elsif flag_name == "invulnerable"
          elsif flag_name == "buddha"
          elsif flag_name == "reflective"
          elsif flag_name == "shieldreflect"
          elsif flag_name == "deflect"
          elsif flag_name == "mirrorreflect"
          elsif flag_name == "aimreflect"
          elsif flag_name == "thrureflect"
          elsif flag_name == "noradiusdmg"
          elsif flag_name == "dontblast"
          elsif flag_name == "shadow"
          elsif flag_name == "ghost"
          elsif flag_name == "dontmorph"
          elsif flag_name == "dontsquash"
          elsif flag_name == "noteleother"
          elsif flag_name == "harmfriends"
          elsif flag_name == "doharmspecies"
          elsif flag_name == "dontharmclass"
          elsif flag_name == "dontharmspecies"
          elsif flag_name == "nodamage"
          elsif flag_name == "dontrip"
          elsif flag_name == "notelefrag"
          elsif flag_name == "alwaystelefrag"
          elsif flag_name == "dontdrain"
          elsif flag_name == "laxtelefragdmg"
          elsif flag_name == "shadowblock"

          # Appearance and Sound
          elsif flag_name == "bright"
          elsif flag_name == "invisible"
          elsif flag_name == "noblood"
          elsif flag_name == "noblooddecals"
          elsif flag_name == "stealth"
          elsif flag_name == "floorclip"
          elsif flag_name == "spawnfloat"
          elsif flag_name == "spawnceiling"
          elsif flag_name == "floatbob"
          elsif flag_name == "noicedeath"
          elsif flag_name == "dontgib"
          elsif flag_name == "dontsplash"
          elsif flag_name == "dontoverlap"
          elsif flag_name == "randomize"
          elsif flag_name == "fixmapthingpos"
          elsif flag_name == "fullvolactive"
          elsif flag_name == "fullvoldeath"
          elsif flag_name == "fullvolsee"
          elsif flag_name == "nowallbouncesnd"
          elsif flag_name == "visibilitypulse"
          elsif flag_name == "rockettrail"
          elsif flag_name == "grenadetrail"
          elsif flag_name == "nobouncesound"
          elsif flag_name == "noskin"
          elsif flag_name == "donttranslate"
          elsif flag_name == "nopain"
          elsif flag_name == "forceybillboard"
          elsif flag_name == "forcexybillboard"

          # projectile flags
          elsif flag_name == "missile"
          elsif flag_name == "ripper"
          elsif flag_name == "nobossrip"
          elsif flag_name == "nodamagethrust"
          elsif flag_name == "dontreflect"
          elsif flag_name == "noshieldreflect"
          elsif flag_name == "nosheildreflect"
          elsif flag_name == "floorhugger"
          elsif flag_name == "ceilinghugger"
          elsif flag_name == "bloodlessimpact"
          elsif flag_name == "bloodsplatter"
          elsif flag_name == "foilinvul"
          elsif flag_name == "foilbuddha"
          elsif flag_name == "seekermissile"
          elsif flag_name == "screenseeker"
          elsif flag_name == "skyexplode"
          elsif flag_name == "noexplodefloor"
          elsif flag_name == "strifedamage"
          elsif flag_name == "extremedeath"
          elsif flag_name == "noextremedeath"
          elsif flag_name == "dehexplosion"
          elsif flag_name == "piercearmor"
          elsif flag_name == "forceradiusdmg"
          elsif flag_name == "forcezeroradiusdmg"
          elsif flag_name == "spawnsoundsource"
          elsif flag_name == "painless"
          elsif flag_name == "forcepain"
          elsif flag_name == "causepain"
          elsif flag_name == "dontseekinvisible"
          elsif flag_name == "stepmissile"
          elsif flag_name == "additivepoisondamage"
          elsif flag_name == "additivepoisonduration"
          elsif flag_name == "poisonalways"
          elsif flag_name == "hittarget"
          elsif flag_name == "hitmaster"
          elsif flag_name == "hittracer"
          elsif flag_name == "hitowner"

          # Bouncing
          elsif flag_name == "bounceonwalls"
          elsif flag_name == "bounceonfloors"
          elsif flag_name == "bounceonceilings"
          elsif flag_name == "allowbounceonactors"
          elsif flag_name == "bounceautooff"
          elsif flag_name == "bounceautooffflooronly"
          elsif flag_name == "bouncelikeheretic"
          elsif flag_name == "bounceonactors"
          elsif flag_name == "bounceonunrippables"
          elsif flag_name == "nowallbouncesnd"
          elsif flag_name == "nobouncesound"
          elsif flag_name == "explodeonwater"
          elsif flag_name == "canbouncewater"
          elsif flag_name == "mbfbouncer"
          elsif flag_name == "usebouncestate"
          elsif flag_name == "dontbounceonshootables"
          elsif flag_name == "dontbounceonsky"
          
          # Miscellaneous
          elsif flag_name == "iceshatter"
          elsif flag_name == "dropped"
          elsif flag_name == "ismonster"
          elsif flag_name == "corpse"
          elsif flag_name == "countitem"
          elsif flag_name == "countkill"
          elsif flag_name == "countsecret"
          elsif flag_name == "notdmatch"
          elsif flag_name == "nonshootable"
          elsif flag_name == "dropoff"
          elsif flag_name == "puffonactors"
          elsif flag_name == "allowparticles"
          elsif flag_name == "alwayspuff"
          elsif flag_name == "puffgetsowner"
          elsif flag_name == "forcedecal"
          elsif flag_name == "nodecal"
          elsif flag_name == "synchronized"
          elsif flag_name == "alwaysfast"
          elsif flag_name == "neverfast"
          elsif flag_name == "oldradiusdmg"
          elsif flag_name == "usespecial"
          elsif flag_name == "bumpspecial"
          elsif flag_name == "bossdeath"
          elsif flag_name == "nointeraction"
          elsif flag_name == "notautomated"
          elsif flag_name == "nomenu"
          elsif flag_name == "pickup"
          elsif flag_name == "touchy"
          elsif flag_name == "vulnerable"
          elsif flag_name == "notonautomap"
          elsif flag_name == "weaponspawn"
          
          # Limited Use
          elsif flag_name == "getowner"
          elsif flag_name == "seesdaggers"
          elsif flag_name == "incombat"
          elsif flag_name == "noclip"
          elsif flag_name == "nosector"
          elsif flag_name == "icecorpse"
          elsif flag_name == "justhit"
          elsif flag_name == "justattacked"
          elsif flag_name == "teleport"
          elsif flag_name == "blasted"
          elsif flag_name == "explocount"
          elsif flag_name == "skullfly"
          elsif flag_name == "retargetafterslam"
          elsif flag_name == "onlyslamsolid"
          elsif flag_name == "specialfiredamage"
          elsif flag_name == "specialfloorclip"
          elsif flag_name == "summonedmonster"
          elsif flag_name == "special"
          elsif flag_name == "nosavegame"

          # Boss Triggers
          elsif flag_name == "e1m8boss"
          elsif flag_name == "e2m8boss"
          elsif flag_name == "e3m8boss"
          elsif flag_name == "e4m6boss"
          elsif flag_name == "e4m8boss"

          # Internal Flags
          elsif flag_name == "inchase"
          elsif flag_name == "unmorphed"
          elsif flag_name == "fly"
          elsif flag_name == "onmobj"
          elsif flag_name == "argsdefined"
          elsif flag_name == "nosightcheck"
          elsif flag_name == "crashed"
          elsif flag_name == "warnbot"
          elsif flag_name == "huntplayers"
          elsif flag_name == "nohateplayers"
          elsif flag_name == "scrollmove"
          elsif flag_name == "vfriction"
          elsif flag_name == "bossspawned"
          elsif flag_name == "avoidingdropoff"
          elsif flag_name == "chasegoal"
          elsif flag_name == "inconversation"
          elsif flag_name == "armed"
          elsif flag_name == "falling"
          elsif flag_name == "linedone"
          elsif flag_name == "shattering"
          elsif flag_name == "killed"
          elsif flag_name == "bosscube"
          elsif flag_name == "intrymove"
          elsif flag_name == "handlenodelay"
          elsif flag_name == "flycheat"
          elsif flag_name == "respawninvul"
          
          # Depricated Flags
          elsif flag_name == "lowgravity"
          elsif flag_name == "quartergravity"
          elsif flag_name == "longmeleerange"
          elsif flag_name == "shortmissilerange"
          elsif flag_name == "highermprob"
          elsif flag_name == "fireresist"
          elsif flag_name == "donthurtspecies"
          elsif flag_name == "firedamage"
          elsif flag_name == "icedamage"
          elsif flag_name == "hereticbounce"
          elsif flag_name == "hexenbounce"
          elsif flag_name == "doombounce"
          elsif flag_name == "faster"
          elsif flag_name == "fastmelee"

          # Additional Flags
          elsif flag_name == "inventory.quiet"
          elsif flag_name == "inventory.autoactivate"
          elsif flag_name == "inventory.undroppable" || flag_name == "undroppable"
          elsif flag_name == "inventory.unclearable"
          elsif flag_name == "inventory.invbar" || flag_name == "invbar"
          elsif flag_name == "inventory.hubpower"
          elsif flag_name == "inventory.persistentpower"
          elsif flag_name == "inventory.interhubstrip"
          elsif flag_name == "inventory.pickupflash"
          elsif flag_name == "inventory.alwayspickup"
          elsif flag_name == "inventory.fancypickupsound" || flag_name == "fancypickupsound"
          elsif flag_name == "inventory.noattenpickupsound"
          elsif flag_name == "inventory.bigpowerup"
          elsif flag_name == "inventory.neverrespawn"
          elsif flag_name == "inventory.keepdepleted"
          elsif flag_name == "inventory.ignoreskill"
          elsif flag_name == "inventory.additivetime"
          elsif flag_name == "inventory.untossable"
          elsif flag_name == "inventory.restrictabsolutely"
          elsif flag_name == "inventory.noscreenflash"
          elsif flag_name == "inventory.tossed"
          elsif flag_name == "inventory.alwaysrespawn"
          elsif flag_name == "inventory.transfer"
          elsif flag_name == "inventory.noteleportfreeze"
          elsif flag_name == "inventory.noscreenblink"
          elsif flag_name == "inventory.ishealth"
          elsif flag_name == "inventory.isarmor"

          # Weapons
          elsif flag_name == "weapon.noautofire"
          elsif flag_name == "weapon.readysndhalf"
          elsif flag_name == "weapon.dontbob"
          elsif flag_name == "weapon.axeblood"
          elsif flag_name == "weapon.noalert"
          elsif flag_name == "weapon.ammo_optional"
          elsif flag_name == "weapon.alt_ammo_optional"
          elsif flag_name == "weapon.ammo_checkboth"
          elsif flag_name == "weapon.primary_uses_both"
          elsif flag_name == "weapon.alt_uses_both"
          elsif flag_name == "weapon.wimpy_weapon" || flag_name == "wimpy_weapon"
          elsif flag_name == "weapon.powered_up" || flag_name == "powered_up"
          elsif flag_name == "weapon.staff2_kickback"
          elsif flag_name == "weapon.explosive"
          elsif flag_name == "weapon.meleeweapon" || flag_name == "meleeweapon"
          elsif flag_name == "weapon.bfg"
          elsif flag_name == "weapon.cheatnotweapon"
          elsif flag_name == "weapon.noautoswitchto"
          elsif flag_name == "weapon.noautoaim"
          elsif flag_name == "weapon.nodeathdeselect"
          elsif flag_name == "weapon.nodeathinput"
          
          # PowerSpeed
          elsif flag_name == "powerspeed.notrail"
          
          # Players
          elsif flag_name == "playerpawn.nothrustwheninvul" || flag_name == "nothrustwheninvul"
          elsif flag_name == "playerpawn.cansupermorph" || flag_name == "cansupermorph"
          elsif flag_name == "playerpawn.crouchablemorph"
          elsif flag_name == "playerpawn.weaponlevel2ended"
         
          # Zandronum Specific Flags
          elsif flag_name == "allowclientspawn"
          elsif flag_name == "clientsideonly"
          elsif flag_name == "nonetid"
          elsif flag_name == "dontidentifytarget"
          elsif flag_name == "scorepillar"
          elsif flag_name == "serversideonly"
          elsif flag_name == "inventory.forcerespawninsurvival"
          elsif flag_name == "weapon.allow_with_respawn_invul"
          elsif flag_name == "weapon.nolms"
          elsif flag_name == "piercearmor"
          elsif flag_name == "blueteam"
          elsif flag_name == "redteam"
          elsif flag_name == "node"
          elsif flag_name == "basehealth"
          elsif flag_name == "superhealth"
          elsif flag_name == "basearmor"
          elsif flag_name == "superarmor"
          elsif flag_name == "explodeondeath"
          
          # Catchall for missing stuff to double check things
          else
            if missing_actor_flags.fetch(flag_name, nil)
              missing_flag = missing_actor_flags[flag_name]
            else
              missing_flag = Array(String).new
            end 
            missing_flag << new_actor.source_wad_folder
            missing_actor_flags[flag_name] = missing_flag
            missing_actor_flags[flag_name].uniq!
          end
        end
      # Variables need to be accounted for
      elsif property_name == "var"
        puts "  - Var: " + line.split[1..-1]?.to_s
        var_type = line.split[1]?.to_s
        var_name = line.split[2]?.to_s
        new_actor.user_vars[var_name] = var_type
      elsif property_name == "game"
        puts "  - Game: " + line.split[1]?.to_s
        new_actor.game = line.split[1]?.to_s
      elsif property_name == "spawnid"
        puts "  - SpawnID: " + line.split[1]?.to_s
        new_actor.spawn_id = line.split[1].to_i
      elsif property_name == "conversationid"
        puts "  - ConversationID: " + line.split[1..-1].join(' ')
        new_actor.conversation_id = line.split[1..-1].join(' ')
      elsif property_name == "tag"
        puts "  - Tag: " + line.split[1..-1].join(' ')
        new_actor.tag = line.split[1..-1].join(' ')
      elsif property_name == "health" && new_actor.name.downcase.strip != "health"
        puts "  - Health: " + line.split[1]?.to_s
        new_actor.health = line.split[1].to_i
      elsif property_name == "gibhealth"
        puts "  - GibHealth: " + line.split[1]?.to_s
        new_actor.gib_health = line.split[1].to_i
      elsif property_name == "woundhealth"
        puts "  - WoundHealth: " + line.split[1]?.to_s
        new_actor.wound_health = line.split[1].to_i
      elsif property_name == "reactiontime"
        puts "  - ReactionTime: " + line.split[1]?.to_s
        new_actor.reaction_time = line.split[1].to_i
      elsif property_name == "painchance"
        puts "  - PainChance: " + line.split[1]?.to_s
        new_actor.pain_chance = "#{line.split[1]?.to_s},#{line.split[2]?.to_s}"
      elsif property_name == "painthreshold"
        puts "  - PainThreshold: " + line.split[1]?.to_s
        new_actor.pain_threshold = line.split[1].to_i
      elsif property_name == "damagefactor"
        puts "  - DamageFactor: " + line.split[1..-1].join(' ')
        new_actor.damage_factor = line.split[1..-1].join(' ')
      elsif property_name == "selfdamagefactor"
        puts "  - SelfDamageFactor: " + line.split[1]?.to_s
        new_actor.self_damage_factor = line.split[1].to_f
      elsif property_name == "damagemultiply"
        puts "  - DamageMultiply: " + line.split[1]?.to_s
        new_actor.damage_multiply = line.split[1].to_f
      elsif property_name == "damage"
        puts "  - Damage: " + line.split[1]?.to_s
        new_actor.damage = line.split[1]?.to_s
      # DamageFunction goes here but it is ZScript specific
      elsif property_name == "poisondamage"
        puts "  - PoisonDamage: " + line.split[1..-1].join(' ')
        new_actor.poison_damage = line.split[1..-1].join(' ')
      elsif property_name == "poisondamagetype"
        puts "  - PoisonDamageType: " + line.split[1..-1].join(' ')
        new_actor.poison_damage_type = line.split[1..-1].join(' ')
      elsif property_name == "radiusdamagefactor"
        puts "  - RadiusDamageFactor: " + line.split[1]?.to_s
        new_actor.radius_damage_factor = line.split[1].to_f
      elsif property_name == "ripperlevel"
        puts "  - RipperLevel: " + line.split[1]?.to_s
        new_actor.ripper_level = line.split[1].to_i
      elsif property_name == "riplevelmin"
        puts "  - RipLevelMin: " + line.split[1]?.to_s
        new_actor.rip_level_min = line.split[1].to_i
      elsif property_name == "riplevelmax"
        puts "  - RipLevelMax: " + line.split[1]?.to_s
        new_actor.rip_level_max = line.split[1].to_i
      elsif property_name == "designatedteam"
        puts "  - DesignatedTeam: " + line.split[1]?.to_s
        new_actor.designated_team = line.split[1].to_i
      elsif property_name == "speed"
        puts "  - Speed: " + line.split[1]?.to_s
        new_actor.speed = line.split[1].to_f
      elsif property_name == "vspeed"
        puts "  - VSpeed: " + line.split[1]?.to_s
        new_actor.v_speed = line.split[1].to_f
      elsif property_name == "fastspeed"
        puts "  - FastSpeed: " + line.split[1]?.to_s
        new_actor.fast_speed = line.split[1].to_i
      elsif property_name == "floatspeed"
        puts "  - FloatSpeed: " + line.split[1]?.to_s
        new_actor.float_speed = line.split[1].to_i
      elsif property_name == "species"
        puts "  - Species: " + line.split[1]?.to_s
        new_actor.species = line.split[1].to_s
      elsif property_name == "accuracy"
        puts "  - Accuracy: " + line.split[1]?.to_s
        new_actor.accuracy = line.split[1].to_i
      elsif property_name == "stamina"
        puts "  - Stamina: " + line.split[1]?.to_s
        new_actor.stamina = line.split[1].to_i
      elsif property_name == "activation"
        puts "  - Activation: " + line.split[1..-1].join(' ')
        new_actor.activation = line.split[1..-1].join(' ')
      elsif property_name == "telefogsourcetype"
        puts "  - TeleFogSourceType: " + line.split[1]?.to_s
        new_actor.tele_fog_source_type = line.split[1].to_s
      elsif property_name == "telefogdesttype"
        puts "  - TeleFogDestType: " + line.split[1]?.to_s
        new_actor.tele_fog_dest_type = line.split[1].to_s
      elsif property_name == "threshold"
        puts "  - Threshold: " + line.split[1]?.to_s
        new_actor.threshold = line.split[1].to_i
      elsif property_name == "defthreshold"
        puts "  - DefThreshold: " + line.split[1]?.to_s
        new_actor.def_threshold = line.split[1].to_i
      elsif property_name == "friendlyseeblocks"
        puts "  - FriendlySeeBlocks: " + line.split[1]?.to_s
        new_actor.friendly_see_blocks = line.split[1].to_i
      elsif property_name == "shadowaimfactor"
        puts "  - ShadowAimFactor: " + line.split[1]?.to_s
        new_actor.shadow_aim_factor = line.split[1].to_f
      elsif property_name == "shadowpenaltyfactor"
        puts "  - ShadowPenaltyFactor: " + line.split[1]?.to_s
        new_actor.shadow_penalty_factor = line.split[1].to_f
      elsif property_name == "radius"
        puts "  - Radius: " + line.split[1]?.to_s
        new_actor.radius = line.split[1].to_f
      elsif property_name == "height"
        puts "  - Height: " + line.split[1]?.to_s
        new_actor.height = line.split[1].to_i
      elsif property_name == "deathheight"
        puts "  - DeathHeight: " + line.split[1]?.to_s
        new_actor.death_height = line.split[1].to_i
      elsif property_name == "burnheight"
        puts "  - BurnHeight: " + line.split[1]?.to_s
        new_actor.burn_height = line.split[1].to_i
      elsif property_name == "projectilepassheight"
        puts "  - ProjectilePassHeight: " + line.split[1]?.to_s
        new_actor.projectile_pass_height = line.split[1].to_i
      elsif property_name == "gravity"
        puts "  - Gravity: " + line.split[1]?.to_s
        new_actor.gravity = line.split[1].to_f
      elsif property_name == "friction"
        puts "  - Height: " + line.split[1]?.to_s
        new_actor.friction = line.split[1].to_f
      elsif property_name == "mass"
        puts "  - Mass: " + line.split[1]?.to_s
        new_actor.mass = line.split[1].to_s
      elsif property_name == "maxstepheight"
        puts "  - MaxStepHeight: " + line.split[1]?.to_s
        new_actor.max_step_height = line.split[1].to_i
      elsif property_name == "maxdropoffheight"
        puts "  - MaxDropOffHeight: " + line.split[1]?.to_s
        new_actor.max_drop_off_height = line.split[1].to_i
      elsif property_name == "maxslopesteepness"
        puts "  - MaxSlopeSteepness: " + line.split[1]?.to_s
        new_actor.max_slope_steepness = line.split[1].to_f
      elsif property_name == "bouncetype"
        puts "  - BounceType: " + line.split[1]?.to_s
        new_actor.bounce_type = line.split[1].to_s
      elsif property_name == "bouncefactor"
        puts "  - BounceFactor: " + line.split[1]?.to_s
        new_actor.bounce_factor = line.split[1].to_f
      elsif property_name == "wallbouncefactor"
        puts "  - WallBounceFactor: " + line.split[1]?.to_s
        new_actor.wall_bounce_factor = line.split[1].to_f
      elsif property_name == "bouncecount"
        puts "  - BounceCount: " + line.split[1]?.to_s
        new_actor.bounce_count = line.split[1].to_i
      elsif property_name == "projectilekickback"
        puts "  - ProjectileKickBack: " + line.split[1]?.to_s
        new_actor.projectile_kick_back = line.split[1].to_i
      elsif property_name == "pushfactor"
        puts "  - PushFactor: " + line.split[1]?.to_s
        new_actor.push_factor = line.split[1].to_f
      elsif property_name == "weaveindexxy"
        puts "  - WeaveIndexXY: " + line.split[1]?.to_s
        new_actor.weave_index_xy = line.split[1].to_i
      elsif property_name == "weaveindexz"
        puts "  - WeaveIndexZ: " + line.split[1]?.to_s
        new_actor.weave_index_z = line.split[1].to_i
      elsif property_name == "thrubits"
        puts "  - ThruBits: " + line.split[1]?.to_s
        new_actor.thru_bits = line.split[1].to_i
      elsif property_name == "activesound"
        puts "  - ActiveSound: " + line.split[1]?.to_s
        new_actor.active_sound = line.split[1].to_s
      elsif property_name == "attacksound"
        puts "  - AttackSound: " + line.split[1]?.to_s
        new_actor.attack_sound = line.split[1].to_s
      elsif property_name == "bouncesound"
        puts "  - BounceSound: " + line.split[1]?.to_s
        new_actor.bounce_sound = line.split[1].to_s
      elsif property_name == "crushpainsound"
        puts "  - CrushPainSound: " + line.split[1]?.to_s
        new_actor.crush_pain_sound = line.split[1].to_s
      elsif property_name == "deathsound"
        puts "  - DeathSound: " + line.split[1]?.to_s
        new_actor.death_sound = line.split[1].to_s
      elsif property_name == "howlsound"
        puts "  - HowlSound: " + line.split[1]?.to_s
        new_actor.howl_sound = line.split[1].to_s
      elsif property_name == "painsound"
        puts "  - PainSound: " + line.split[1]?.to_s
        new_actor.pain_sound = line.split[1].to_s
      elsif property_name == "ripsound"
        puts "  - RipSound: " + line.split[1]?.to_s
        new_actor.rip_sound = line.split[1].to_s
      elsif property_name == "seesound"
        puts "  - SeeSound: " + line.split[1]?.to_s
        new_actor.see_sound = line.split[1].to_s
      elsif property_name == "wallbouncesound"
        puts "  - WallBounceSound: " + line.split[1]?.to_s
        new_actor.wall_bounce_sound = line.split[1].to_s
      elsif property_name == "pushsound"
        puts "  - PushSound: " + line.split[1]?.to_s
        new_actor.push_sound = line.split[1].to_s
      elsif property_name == "renderstyle"
        puts "  - RenderStyle: " + line.split[1]?.to_s
        new_actor.render_style = line.split[1].to_s
      elsif property_name == "alpha"
        puts "  - Alpha: " + line.split[1]?.to_s
        new_actor.alpha = line.split[1].to_f
      elsif property_name == "defaultalpha"
        puts "  - DefaultAlpha: " + line.split[1]?.to_s
        new_actor.default_alpha = true
      elsif property_name == "stealthalpha"
        puts "  - StealthAlpha: " + line.split[1]?.to_s
        new_actor.stealth_alpha = line.split[1].to_f
      elsif property_name == "xscale"
        puts "  - XScale: " + line.split[1]?.to_s
        new_actor.x_scale = line.split[1].to_f
      elsif property_name == "yscale"
        puts "  - YScale: " + line.split[1]?.to_s
        new_actor.y_scale = line.split[1].to_f
      elsif property_name == "scale"
        puts "  - Scale: " + line.split[1]?.to_s
        new_actor.scale = line.split[1].to_f
      elsif property_name == "lightlevel"
        puts "  - LightLevel: " + line.split[1]?.to_s
        new_actor.light_level = line.split[1].to_i
      elsif property_name == "translation"
        puts "  - Translation: " + line.split[1..-1].join(' ')
        new_actor.translation = line.split[1..-1].join(' ')
      elsif property_name == "bloodcolor"
        puts "  - BloodColor: " + line.split[1..-1].join(' ')
        new_actor.blood_color = line.split[1..-1].join(' ')
      elsif property_name == "bloodtype"
        puts "  - BloodType: " + line.split[1..-1].join(' ')
        new_actor.blood_type = line.split[1..-1].join(' ')
      elsif property_name == "decal"
        puts "  - Decal: " + line.split[1]?.to_s
        new_actor.decal = line.split[1].to_s
      elsif property_name == "stencilcolor"
        puts "  - StencilColor: " + line.split[1]?.to_s
        new_actor.stencil_color = line.split[1].to_s
      elsif property_name == "floatbobphase"
        puts "  - FloatBobPhase: " + line.split[1]?.to_s
        new_actor.float_bob_phase = line.split[1].to_i
      elsif property_name == "floatbobstrength"
        puts "  - FloatBobStrength: " + line.split[1]?.to_s
        new_actor.float_bob_strength = line.split[1].to_i
      elsif property_name == "distancecheck"
        puts "  - DistanceCheck: " + line.split[1]?.to_s
        new_actor.distance_check = line.split[1]?.to_s
      elsif property_name == "spriteangle"
        puts "  - SpriteAngle: " + line.split[1]?.to_s
        new_actor.sprite_angle = line.split[1].to_i
      elsif property_name == "spriterotation"
        puts "  - SpriteRotation: " + line.split[1]?.to_s
        new_actor.sprite_rotation = line.split[1].to_i
      elsif property_name == "visibleangles"
        puts "  - VisibleAngles: " + line.split[1..-1].join(' ')
        new_actor.visible_angles = line.split[1..-1].join(' ')
      elsif property_name == "visiblepitch"
        puts "  - VisiblePitch: " + line.split[1..-1].join(' ')
        new_actor.visible_pitch = line.split[1..-1].join(' ')
      elsif property_name == "renderradius"
        puts "  - RenderRadius: " + line.split[1]?.to_s
        new_actor.render_radius = line.split[1].to_f
      elsif property_name == "cameraheight"
        puts "  - CameraHeight: " + line.split[1]?.to_s
        new_actor.camera_height = line.split[1].to_i
      elsif property_name == "camerafov"
        puts "  - CameraFOV: " + line.split[1]?.to_s
        new_actor.camera_fov = line.split[1].to_f
      elsif property_name == "hitobituary"
        puts "  - HitObituary: " + line.split[1]?.to_s
        new_actor.hit_obituary = line.split[1].to_s
      elsif property_name == "obituary"
        puts "  - Obituary: " + line.split[1]?.to_s
        new_actor.obituary = line.split[1].to_s
      elsif property_name == "minmissilechance"
        puts "  - MinMissileChance: " + line.split[1]?.to_s
        new_actor.min_missile_chance = line.split[1].to_i
      elsif property_name == "damagetype"
        puts "  - DamageType: " + line.split[1]?.to_s
        new_actor.damage_type = line.split[1].to_s
      elsif property_name == "deathtype"
        puts "  - DeathType: " + line.split[1]?.to_s
        new_actor.death_type = line.split[1].to_s
      elsif property_name == "meleethreshold"
        puts "  - MeleeThreshold: " + line.split[1]?.to_s
        new_actor.melee_threshold = line.split[1].to_i
      elsif property_name == "meleerange"
        puts "  - MeleeRange: " + line.split[1]?.to_s
        new_actor.melee_range = line.split[1].to_i
      elsif property_name == "maxtargetrange"
        puts "  - MaxTargetRange: " + line.split[1]?.to_s
        new_actor.max_target_range = line.split[1].to_i
      elsif property_name == "meleedamage"
        puts "  - MeleeDamage: " + line.split[1]?.to_s
        new_actor.melee_damage = line.split[1].to_i
      elsif property_name == "meleesound"
        puts "  - MeleeSound: " + line.split[1]?.to_s
        new_actor.melee_sound = line.split[1].to_s
      elsif property_name == "missileheight"
        puts "  - MissileHeight: " + line.split[1]?.to_s
        new_actor.missile_height = line.split[1].to_i
      elsif property_name == "missiletype"
        puts "  - MissileType: " + line.split[1]?.to_s
        new_actor.missile_type = line.split[1].to_s
      elsif property_name == "explosionradius"
        puts "  - ExplosionRadius: " + line.split[1]?.to_s
        new_actor.explosion_radius = line.split[1].to_i
      elsif property_name == "explosiondamage"
        puts "  - ExplosionDamage: " + line.split[1]?.to_s
        new_actor.explosion_damage = line.split[1].to_i
      elsif property_name == "donthurtshooter"
        puts "  - DontHurtShooter: " + line.split[1]?.to_s
        new_actor.dont_hurt_shooter = true
      elsif property_name == "paintype"
        puts "  - PainType: " + line.split[1]?.to_s
        new_actor.pain_type = line.split[1].to_s
      elsif property_name == "projectile"
        puts "  - Projectile"
        new_actor.projectile = true
      # this one needs white glove treatment :-/ lines that start with "monster"
      elsif property_name =~ /^monster/
        puts "  - Monster"
        new_actor.monster = true
        # Sometimes "monster" gets thrown in with flags because people don't know any better
        # And to be honest, it does set flags, so I can understand the confusion.
        # You can put multiple flags with no regard for whitespace and the interpreter
        # enables their bad coding behavior.
        # So we need to parse out the rest of the line after 'monster'
        # remove "monster" from the beginning and remove whitespace any leading whitespace after "monster"
        # e.g. "monster +blah" --> "+blah", "monster+boss" --> "+boss"
        remaining_line = line.lchop("monster").lstrip
        if remaining_line != ""
          puts "Remaining line detected: #{remaining_line}"
          # add the line to the end of the actor so we can process it
          actor = actor + "\n" + remaining_line
        end
      elsif property_name == "+ismonster"
        puts "  - Monster"
        new_actor.monster = true
      elsif property_name == "{" || property_name == "}"
      elsif property_name == "args"
        puts "  - Args: " + line.split[1..-1].join(' ')
        new_actor.args = line.split[1..-1].join(' ')
      elsif property_name == "clearflags"
        # I don't know what we need to do with this one but it might be
        # fairly complicated. I think this means clear all inherited flags.
        puts "  - ClearFlags: " + line.split[1]?.to_s
        new_actor.clear_flags = true
      elsif property_name == "dropitem"
        puts "  - DropItem: " + line.split[1..-1].join(' ')
        new_actor.drop_item = line.split[1..-1].join(' ')
      #Deprecated properties go here:
      # - Spawn
      # - See
      # - Melee
      # - Pain
      # - Death
      # - XDeath
      # - Burn
      # - Ice
      # - Disintegrate
      # - Raise
      # - Crash
      # - Wound
      # - Crush
      # - Heal
      elsif property_name == "skip_super"
        puts "  - Skip_Super"
        new_actor.skip_super = true
      elsif property_name == "visibletoteam"
        puts "  - VisibleToTeam: " + line.split[1]?.to_s
        new_actor.visible_to_team = line.split[1].to_i
      elsif property_name == "visibletoplayerclass"
        puts "  - VisibleToPlayerClass: " + line.split[1..-1].join(' ')
        new_actor.visible_to_player_class = line.split[1..-1].join(' ')
      elsif property_name == "inventory.amount"
        puts "  - Inventory.Amount: " + line.split[1]?.to_s
        new_actor.inventory.amount = line.split[1].to_i
      elsif property_name == "inventory.defmaxamount"
        puts "  - Inventory.DefMaxAmount"
        new_actor.inventory.def_max_amount = true
      elsif property_name == "inventory.maxamount"
        puts "  - Inventory.MaxAmount: " + line.split[1]?.to_s
        new_actor.inventory.max_amount = line.split[1].to_s
      elsif property_name == "inventory.interhubamount"
        puts "  - Inventory.InterHubAmount: " + line.split[1]?.to_s
        new_actor.inventory.inter_hub_amount = line.split[1].to_i
      elsif property_name == "inventory.icon"
        puts "  - Inventory.Icon: " + line.split[1]?.to_s
        new_actor.inventory.icon = line.split[1].to_s
      elsif property_name == "inventory.althudicon"
        puts "  - Inventory.AltHUDIcon: " + line.split[1]?.to_s
        new_actor.inventory.alt_hud_icon = line.split[1].to_s
      elsif property_name == "inventory.pickupmessage"
        puts "  - Inventory.PickupMessage: " + line.split[1..-1].join(' ')
        new_actor.inventory.pickup_message = line.split[1..-1].join(' ')
      elsif property_name == "inventory.pickupsound"
        puts "  - Inventory.PickupSound: " + line.split[1..-1].join(' ')
        new_actor.inventory.pickup_sound = line.split[1..-1].join(' ')
      elsif property_name == "inventory.pickupflash"
        puts "  - Inventory.PickupFlash: " + line.split[1]?.to_s
        new_actor.inventory.pickup_flash = line.split[1].to_s
      elsif property_name == "inventory.usesound"
        puts "  - Inventory.UseSound: " + line.split[1]?.to_s
        new_actor.inventory.use_sound = line.split[1].to_s
      elsif property_name == "inventory.respawntics"
        puts "  - Inventory.RespawnTics: " + line.split[1]?.to_s
        new_actor.inventory.respawn_tics = line.split[1].to_i
      elsif property_name == "inventory.givequest"
        puts "  - Inventory.GiveQuest: " + line.split[1]?.to_s
        new_actor.inventory.give_quest = line.split[1].to_i
      elsif property_name == "inventory.forbiddento"
        puts "  - Inventory.ForbiddenTo: " + line.split[1..-1].join(' ')
        new_actor.inventory.forbidden_to = line.split[1..-1].join(' ')
      elsif property_name == "inventory.restrictedto"
        puts "  - Inventory.RestrictedTo: " + line.split[1..-1].join(' ')
        new_actor.inventory.restricted_to = line.split[1..-1].join(' ')

      elsif property_name == "fakeinventory.respawns"

      elsif property_name == "armor.saveamount"
      elsif property_name == "armor.savepercent"
      elsif property_name == "armor.maxfullabsorb"
      elsif property_name == "armor.maxabsorb"
      elsif property_name == "armor.maxsaveamount"
      elsif property_name == "armor.maxbonus"
      elsif property_name == "armor.maxbonusmax"

      elsif property_name == "weapon.ammogive"
      elsif property_name == "weapon.ammogive1"
      elsif property_name == "weapon.ammogive2"
      elsif property_name == "weapon.ammotype"
      elsif property_name == "weapon.ammotype1"
      elsif property_name == "weapon.ammotype2"
      elsif property_name == "weapon.ammouse"
      elsif property_name == "weapon.ammouse1"
      elsif property_name == "weapon.ammouse2"
      elsif property_name == "weapon.minselectionammo1"
      elsif property_name == "weapon.minselectionammo2"
      elsif property_name == "weapon.bobpivot3d"
      elsif property_name == "weapon.bobrangex"
      elsif property_name == "weapon.bobrangey"
      elsif property_name == "weapon.bobspeed"
      elsif property_name == "weapon.bobstyle"
      elsif property_name == "weapon.kickback"
      elsif property_name == "weapon.defaultkickback"
      elsif property_name == "weapon.readysound"
      elsif property_name == "weapon.selectionorder"
      elsif property_name == "weapon.sisterweapon"
      elsif property_name == "weapon.slotnumber"
      elsif property_name == "weapon.slotpriority"
      elsif property_name == "weapon.upsound"
      elsif property_name == "weapon.weaponscalex"
      elsif property_name == "weapon.weaponscaley"
      elsif property_name == "weapon.yadjust"
      elsif property_name == "weapon.lookscale"
      elsif property_name == "ammo.backpackamount"
      elsif property_name == "ammo.backpackmaxamount"
      elsif property_name == "ammo.dropamount"
      elsif property_name == "weaponpiece.number"
      elsif property_name == "weaponpiece.weapon"
      elsif property_name == "health.lowmessage"
      elsif property_name == "puzzleitem.number"
      elsif property_name == "puzzleitem.failmessage"
      elsif property_name == "puzzleitem.failsound"
      elsif property_name == "player.aircapacity"
      elsif property_name == "player.attackzoffset"
      elsif property_name == "player.clearcolorset"
      elsif property_name == "player.colorrange"
      elsif property_name == "player.colorset"
      elsif property_name == "player.colorsetfile"
      elsif property_name == "player.crouchsprite"
      elsif property_name == "player.damagescreencolor"
      elsif property_name == "player.displayname"
      elsif property_name == "player.face"
      elsif property_name == "player.fallingscreamspeed"
      elsif property_name == "player.flechettetype"
      elsif property_name == "player.flybob"
      elsif property_name == "player.forwardmove"
      elsif property_name == "player.gruntspeed"
      elsif property_name == "player.healradiustype"
      elsif property_name == "player.hexenarmor"
      elsif property_name == "player.invulnerabilitymode"
      elsif property_name == "player.jumpz"
      elsif property_name == "player.maxhealth"
      elsif property_name == "player.morphweapon"
      elsif property_name == "player.mugshotmaxhealth"
      elsif property_name == "player.portrait"
      elsif property_name == "player.runhealth"
      elsif property_name == "player.scoreicon"
      elsif property_name == "player.sidemove"
      elsif property_name == "player.soundclass"
      elsif property_name == "player.spawnclass"
      elsif property_name == "player.startitem"
      elsif property_name == "player.teleportfreezetime"
      elsif property_name == "player.userange"
      elsif property_name == "player.viewbob"
      elsif property_name == "player.viewbobspeed"
      elsif property_name == "player.viewheight"
      elsif property_name == "player.waterclimbspeed"
      elsif property_name == "player.weaponslot"
      elsif property_name == "powerup.color"
      elsif property_name == "powerup.colormap"
      elsif property_name == "powerup.duration"
      elsif property_name == "powerup.mode"
      elsif property_name == "powerup.strength"
      elsif property_name == "powerspeed.notrail"
      elsif property_name == "powerup.type"
      elsif property_name == "healthpickup.autouse"
      elsif property_name == "morphprojectile.playerclass"
      elsif property_name == "morphprojectile.monsterclass"
      elsif property_name == "morphprojectile.duration"
      elsif property_name == "morphprojectile.morphstyle"
      elsif property_name == "morphprojectile.morphflash"
      elsif property_name == "morphprojectile.unmorphflash"
      

      elsif property_name == "{" || property_name == "}" || property_name == "#include"
        # ignore these and do nothing
      else
        if missing_property_names.fetch(property_name, nil)
          list_of_actors_missing_this_property = missing_property_names[property_name]
        else
          list_of_actors_missing_this_property = Array(String).new
        end
        list_of_actors_missing_this_property << new_actor.source_wad_folder
        missing_property_names[property_name] = list_of_actors_missing_this_property
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

puts "=================="
puts "Missing Properties"
puts "=================="
missing_property_names.each do |key, value|
  puts "Missing Property: #{key}"
  puts "Offending Actors:"
  value.each do |actor_name|
    puts actor_name
  end
end
puts "=================="

puts "=================="
puts "Missing Flags"
puts "=================="
missing_actor_flags.each do |key, value|
  puts "Missing Flag: #{key}"
  puts "Offending Actors:"
  value.each do |actor_name|
    puts actor_name
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
