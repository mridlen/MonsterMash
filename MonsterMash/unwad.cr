puts "START"

puts "Requires..."
require "file"
require "file_utils"
require "regex"
require "digest/sha256"
require "compress/zip"

# To make this OS agnostic we need to use fs in place of slashes
# this way Windows will use "\\" and Linux/Mac can use "/"
fs = "/"
fs_os = "/"
{% if flag?(:win32) %}
  fs_os = "\\"
{% else %}
  fs_os = "/"
{% end %}
puts "fs_os: #{fs_os}"

# Other Code Specific To MonsterMash
# require statements use forward slashes regardless of OS
require "./requires/classes.cr"

# Import DoomEdNums from module
#doomednum_info = Hash(Int32, Tuple(Int32, Int32)).new
require "./requires/doomednums.cr"
doomednum_info = DoomEdNums.id_numbers

# Code to determine if a file is text or binary - more complicated than it sounds
def int2byte_range(start : Int32, stop : Int32)
  (start..stop).map(&.to_u8)
end
TEXT_CHARACTERS = int2byte_range(32, 126) + ['\n'.ord.to_u8, '\r'.ord.to_u8, '\t'.ord.to_u8, '\f'.ord.to_u8, '\b'.ord.to_u8]
def binary_file?(file_path : String | Path) : Bool
  file_is_binary = false
  bytes = File.read(file_path).to_slice
  bytes.each do |byte|
    if !TEXT_CHARACTERS.includes?(byte)
      file_is_binary = true
      break
    end
  end

  #File.open file_path do |file|
  #  break if file_is_binary == true
  #  file.each_char.all? do |char|
  #    if TEXT_CHARACTERS.includes?(char) == false
  #      file_is_binary = true
  #      break
  #    end
  #  end
  #end

  if file_is_binary == true
    puts " - file is binary"
  else
    puts " - file is text"
  end

  file_is_binary
rescue
  # assume it's binary by default and return "true"
  true
end

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
# CREATE DIRECTORIES
##########################################

# Source and IWADs directories need to not be autodeleted
puts "Creating WAD Source directory..."
Dir.mkdir_p(".#{fs}Source#{fs}")
puts "Creating IWADs directory..."
Dir.mkdir_p(".#{fs}IWADs#{fs}")

# The rest of the directories should be deleted
puts "Deleting WAD Processing directory..."
FileUtils.rm_r(".#{fs}Processing")
puts "Creating WAD Processing directory..."
Dir.mkdir_p(".#{fs}Processing#{fs}")

puts "Deleting PK3 Processing directory..."
FileUtils.rm_r(".#{fs}Processing_PK3")
puts "Creating PK3 Processing directory..."
Dir.mkdir_p(".#{fs}Processing_PK3#{fs}")

puts "Deleting Completed directory..."
FileUtils.rm_r(".#{fs}Completed")
puts "Creating Completed (WAD and PK3) directory..."
Dir.mkdir_p(".#{fs}Completed#{fs}")

puts "Deleting IWADs_Extracted directory..."
FileUtils.rm_r(".#{fs}IWADs_Extracted")
puts "Creating IWADs_Extracted directory..."
Dir.mkdir_p(".#{fs}IWADs_Extracted#{fs}")

#########################################
# RUN EXTRACTION PROCESS
#########################################
puts "Extraction process starting..."
# Extract each wad in Source to it's own subdirectory
# Wads will go into Processing, PK3s will go into

# build list of wad files
wad_file_list = Dir.glob(".#{fs}Source#{fs}*")
index_deletes = Array(Int32).new
wad_file_list.each_with_index do |file, file_index|
  # check if the extension is wad
  if file.split(".").last.downcase != "wad"
    puts "Not a wad file: #{file}"
    index_deletes << file_index
  end
end
index_deletes.reverse!
index_deletes.each do |deletion|
  wad_file_list.delete_at(deletion)
end

# build list of pk3 files
pk3_file_list = Dir.glob(".#{fs}Source#{fs}*")
index_deletes = Array(Int32).new
pk3_file_list.each_with_index do |file, file_index|
  # check if the extension is pk3
  if file.split(".").last.downcase != "pk3"
    puts "Not a pk3 file: #{file}"
    index_deletes << file_index
  end
end
index_deletes.reverse!
index_deletes.each do |deletion|
  pk3_file_list.delete_at(deletion)
end

puts "Wads:"
puts wad_file_list
puts "PK3s:"
puts pk3_file_list

# extract PK3 files to Processing_PK3 directory
pk3_file_list.each do |file|
  Compress::Zip::Reader.open(file) do |zip|
    # replace backslashes with slashes if they exist
    file = file.split("#{fs_os}").join("#{fs}")
    # Specify the target directory
    dir_name = file.split("#{fs}").last.split(".").first
    target_directory = ".#{fs}Processing_PK3#{fs}#{dir_name}"

    # Create the target directory if it doesn't exist
    Dir.mkdir(target_directory) unless Dir.exists?(target_directory)

    # Extract all entries in the zip archive to the target directory
    zip.each_entry do |entry|
      entry_name = entry.filename
      target_path = File.join(target_directory, entry_name)
      puts entry.filename.chars.last
      if entry_name.chars.last == '/'
        puts "Directory"
        Dir.mkdir_p(target_path)
      else
        puts "File"
        File.open(target_path, "w") do |file|
          IO.copy(entry.io, file)
        end
      end
    end
  end
end

wad_file_list.each do |file_path|
  if File.file?(file_path)
    puts "Processing file: #{file_path}"
    system ".#{fs}#{jeutoolexe} extract \"#{file_path}\" -r"
  end
end

# Do the same thing but for IWADs
Dir.each_child(".#{fs}IWADs") do |file_name|
  file_path = ".#{fs}IWADs#{fs}#{file_name}"
  if File.file?(file_path)
    puts "Processing file: #{file_path}"
    system ".#{fs}#{jeutoolexe} extract \"#{file_path}\" -r"
  end
end
puts "Extraction process complete."

puts "Starting the copy process from Source to Processing..."
# Copy the directories in Source to Processing for processing
# Only the directories are copied
Dir.glob(".#{fs}Source#{fs}*#{fs}").each do |path|
  dest_path = File.join(".#{fs}Processing#{fs}", File.basename(path))
  #completed_path = File.join(".#{fs}Completed#{fs}", File.basename(path))
  if Dir.exists?(dest_path)
    FileUtils.rm_rf(dest_path)
  end

  #FileUtils.cp_r(path, completed_path)
  FileUtils.mv(path, dest_path)
end
# Do the same thing but for IWADs
Dir.glob(".#{fs}IWADs#{fs}*#{fs}").each do |path|
  dest_path = File.join(".#{fs}IWADs_Extracted#{fs}", File.basename(path))
  if Dir.exists?(dest_path)
    FileUtils.rm_rf(dest_path)
  end

  FileUtils.mv(path, dest_path)
end

# The PK3 files are created at the Processing_PK3 folder so no further action
# is needed

puts "Copy from Source to Processing completed."

##########################################
# POST EXTRACTION PROCESSING
##########################################

puts "Starting Processing procedure..."

# Delete any KEYCONF.raw files in Processing directory
keyconf_list = Dir.glob(".#{fs}Processing#{fs}**#{fs}KEYCONF.raw")
puts keyconf_list.inspect
FileUtils.rm(keyconf_list)

# build a list of files under Processing_PK3 so we can do a case insensitive search
processing_pk3_file_list = Dir.glob(".#{fs}Processing_PK3#{fs}**/*")
case_insensitive_file_db = Hash(String, String).new
processing_pk3_file_list.each do |file|
  case_insensitive_file_db[file.to_s.downcase] = file.to_s
end

# build a list of files under Processing so we can do a case insensitive search
processing_file_list = Dir.glob(".#{fs}Processing#{fs}**/*")
processing_hash = Hash(String, String).new
processing_file_list.each do |file|
  case_insensitive_file_db[file.to_s.downcase] = file.to_s
end

# Build a list of files and put them into a hash that tells if they are ZSCRIPT
# or a DECORATE. We need to know this because ZSCRIPT works a little differently
zscript_files_pk3 = Dir.glob(".#{fs}Processing_PK3#{fs}*#{fs}ZSCRIPT*")

puts zscript_files_pk3

deletion_indexes = Array(Int32).new
zscript_files_pk3.each_with_index do |file, file_index|
  file = file.split("#{fs_os}").join("#{fs}")
  puts "Filename: #{file}"
  if File.file?(file) == false
    deletion_indexes << file_index
  end
  file_text = File.read(file)
  lines = file_text.lines
  lines.each do |line|
    if line =~ /^\s*\#include/i
      puts "line: #{line}"

      # determine the folder path - we need this to determine relative path
      folder_path = file.split("#{fs}")[0..-2].join("#{fs}")
      # root folder is useful for absolute paths
      root_folder = file.split("#{fs}")[0..2].join("#{fs}")
      puts "Folder path: #{folder_path}"
      puts "Root path: #{root_folder}"
      # Example: #include "<stuff here>"
      # this will get the content inside the quotation marks:
      include_file = line.split('"')[1]

      # join the path and verify that it isn't too long
      puts "Normalized path:"
      if include_file.chars.first == '.'
        include_file_normalized = ".#{fs}" + Path.posix(folder_path + "#{fs}" + include_file).normalize.to_s
      else
        include_file_normalized = ".#{fs}" + Path.posix(root_folder + "#{fs}" + include_file).normalize.to_s
      end
      puts include_file_normalized

      # size of 4 means at least 4 fields:
      #  1  2              3     4
      # "./Processing_PK3/<dir>/ZSCRIPT"
      # less than that means it goes out of bounds
      if include_file_normalized.split("#{fs}").size < 4
        puts "Fatal Error: relative path goes outside the bounds of the pk3"
        puts "File: #{file} Line: #{line}"
        exit(1)
      end

      # do a case insensitive search to find the case sensitive version
      include_file_normalized = case_insensitive_file_db[include_file_normalized.downcase]

      # add the path to the zscript_files_pk3
      zscript_files_pk3 << include_file_normalized
      puts "---------------------------------"
    end
  end
end
deletion_indexes.reverse!
deletion_indexes.each do |deletion|
  zscript_files_pk3.delete_at(deletion)
end

puts "zscript_files_pk3: #{zscript_files_pk3}"

decorate_files_pk3 = Dir.glob(".#{fs}Processing_PK3#{fs}*#{fs}DECORATE*")

deletion_indexes = Array(Int32).new
decorate_files_pk3.each_with_index do |file, file_index|
  file = file.split("#{fs_os}").join("#{fs}")
  puts "Filename: #{file}"
  if File.file?(file) == false
    deletion_indexes << file_index
  end
  # since Doom DECORATE is CASE INSENSITIVE we have to search and compare to find the actual file name
  file_search_term = "#{file.split("/")[0..2].join("/")}/**/*"
  puts "file_search_term: #{file_search_term}"
  file_search = Dir.glob("#{file_search_term}")
  file_match = "UNDEFINED"
  file_search.each do |searchfile|
    # this takes up a lot of time to display the text, but useful for troubleshooting...
    #puts "searching: #{file.downcase} == #{searchfile.downcase}"
    if file.downcase == searchfile.downcase
      file_match = searchfile
      break
    end
  end
  if file_match == "UNDEFINED"
    puts "Fatal Error: file not found: #{file}"
    exit(1)
  end
  file_text = File.read(file_match)
  lines = file_text.lines
  lines.each do |line|
    if line =~ /^\s*\#include/i
      puts "line: #{line}"

      # determine the folder path - we need this to determine relative path
      folder_path = file.split("#{fs}")[0..-2].join("#{fs}")
      # root folder is useful for absolute paths
      root_folder = file.split("#{fs}")[0..2].join("#{fs}")
      puts "Folder path: #{folder_path}"
      puts "Root path: #{root_folder}"
      # Example: #include "blah"
      # this will get the content inside the quotation marks:
      if line.split(" ")[1] =~ /\"/
        include_file = line.split('"')[1]
      else
        # if there are no quotation marks do a traditional split
        # Example: #include blah
        include_file = line.split[1]
      end
      # join the path and verify that it isn't too long
      puts "Normalized path:"
      if include_file.chars.first == '.'
        include_file_normalized = ".#{fs}" + Path.posix(folder_path + "#{fs}" + include_file).normalize.to_s
      else
        include_file_normalized = ".#{fs}" + Path.posix(root_folder + "#{fs}" + include_file).normalize.to_s
      end
      puts include_file_normalized

      # size of 4 means at least 4 fields:
      #  1  2              3     4
      # "./Processing_PK3/<dir>/ZSCRIPT"
      # less than that means it goes out of bounds
      if include_file_normalized.split("#{fs}").size < 4
        puts "Fatal Error: relative path goes outside the bounds of the pk3"
        puts "File: #{file} Line: #{line}"
        exit(1)
      end

      # do a case insensitive search for the path
      include_file_normalized = case_insensitive_file_db[include_file_normalized.downcase]

      # add the path to the decorate_files_pk3
      decorate_files_pk3 << include_file_normalized
      puts "---------------------------------"
    end
  end
end
deletion_indexes.reverse!
deletion_indexes.each do |deletion|
  decorate_files_pk3.delete_at(deletion)
end

puts decorate_files_pk3

zscript_processing_files = Dir.glob(".#{fs}Processing#{fs}*#{fs}defs#{fs}ZSCRIPT.raw")
zscript_processing_files.each do |zscript_file|
  file_text = File.read(zscript_file)
  file_path = zscript_file.split("#{fs}")[0..-2].join("#{fs}")
  lines = file_text.lines
  lines.each do |line|
    if line =~ /^\s*\#include/i
      include_file = File.dirname(zscript_file) + "#{fs}" + line.split('"')[1].upcase + ".raw"
      zscript_processing_files << include_file
    end
  end
end

puts "ZSCRIPT in Wad files"
puts zscript_processing_files

# Build a list of Processing and Built_In_Actors, and a flag to tell it
# not to touch the built in actors
processing_files = Dir.glob(".#{fs}Processing#{fs}*#{fs}defs#{fs}DECORATE.raw")

# I think this might work to grab all the zs files
built_in_actors = Dir.glob(".#{fs}Built_In_Actors#{fs}*#{fs}*.zs") + Dir.glob(".#{fs}Built_In_Actors#{fs}*.zs")

processing_files.each do |file|
  file_text = File.read(file)
  file_text.each_line do |line|
    # Only perform processing on the line if it is not empty - to save on CPU
    # cycles
    if !line.strip.empty?
      if line =~ /^\s*#include/i
        puts "Include file: " + line
	      # add the include file to the list of files full_dir_list
	      include_file = line.split('"')[1].upcase
        # line = File.read(File.dirname(file_path) + "/" + include_file + ".raw")
        new_directory = File.dirname(file) + "#{fs}" + include_file + ".raw"
        processing_files << new_directory
      end
    end
  end
end

#Build a DB to determine if a script is ZSCRIPT or DECORATE
# script_type[<path>] = "[ZSCRIPT|DECORATE|BUILT_IN]"
script_type = Hash(String, String).new

# There are 5 types we will need to iterate through:
# - WAD DECORATE
# - WAD ZSCRIPT
# - PK3 DECORATE
# - PK3 ZSCRIPT
# - BUILT_IN ZSCRIPT

# WAD DECORATE
processing_files.each do |file_path|
  file_path = file_path.split("#{fs_os}").join("#{fs}")
  script_type[file_path] = "DECORATE"
end
# WAD ZSCRIPT
zscript_processing_files.each do |file_path|
  file_path = file_path.split("#{fs_os}").join("#{fs}")
  script_type[file_path] = "ZSCRIPT"
end
# PK3 DECORATE
decorate_files_pk3.each do |file_path|
  file_path = file_path.split("#{fs_os}").join("#{fs}")
  script_type[file_path] = "DECORATE"
end
# PK3 ZSCRIPT
zscript_files_pk3.each do |file_path|
  file_path = file_path.split("#{fs_os}").join("#{fs}")
  script_type[file_path] = "ZSCRIPT"
end
# BUILT_IN ZSCRIPT
built_in_actors.each do |file_path|
  file_path = file_path.split("#{fs_os}").join("#{fs}")
  script_type[file_path] = "BUILT_IN"
end

# concatenate the two file arrays
# - built in goes first to avoid getting flagged as dupe
# - ZSCRIPT goes first before DECORATE
full_dir_list = built_in_actors + zscript_processing_files + zscript_files_pk3 + processing_files + decorate_files_pk3

puts full_dir_list
puts "-----"
puts script_type.inspect

missing_property_names = Hash(String, Array(String)).new
missing_actor_flags = Hash(String, Array(String)).new

# Processing on each decorate file, and any included files are added to the end
full_dir_list.each do |file_path|
  file_path = file_path.split("#{fs_os}").join("#{fs}")
  input_text = File.read(file_path)
  puts file_path
  wad_folder_name = file_path.split("#{fs}")[2]
  if script_type[file_path] != "BUILT_IN"
    # grabbing the wad file source folder name - split on "/" and grab element 2
    # which is essentially the wad name without ".wad" at the end

    decorate_source_file = file_path.split("#{fs}").last
    puts "#{wad_folder_name}"

    # Per line processing
    puts "Per line processing..."


    # eliminate any leading spaces for parsing
    input_text = input_text.gsub(/^\s*/, "")
  else
    # else -> Script is a BUILT_IN actor
    # no touchy means we skip all that and just open the file for reading

    # strip leading whitespace
    input_text = input_text.gsub(/^\s*/, "")
    # file paths are a little different...
    # We want to set the "decorate_source_file" as
    puts "file_path: #{file_path}"
    decorate_source_file = file_path.split("#{fs}").last
  end

  # remove "//" comments
  input_text = input_text.gsub(%r{//[^\n]*}, "")

  # remove /* through */ comments
  input_text = input_text.gsub(/\/\*[\s\S]*\*\//m, "")

  # put curly braces on their own line
  input_text = input_text.gsub('{', "\n{\n")
  input_text = input_text.gsub('}', "\n}\n")

  # removing any leading or trailing spaces on each line - cleanup
  input_text = input_text.split("\n").map { |line| line.lstrip.strip }.join("\n")

  # remove any blank lines
  input_text = input_text.split("\n").reject { |line| line.strip.empty? }.join("\n")

  # We need to treat ZSCRIPT differently than DECORATE
  # ZSCRIPT will have classes, and we need to treat them like actors... probably
  # in ZSCRIPT there is a "Default {}" section that holds the properties and flags
  #
  # DECORATE:
  # actor blah : blah2 replaces blah 12345
  # {
  #   <properties and flags here>
  #   states
  #   { <states here> }
  # }
  #
  # ZSCRIPT:
  # class blah : blah2 replaces blah 12345
  # {
  #   Default
  #   {
  #     <properties and flags>
  #   }
  #   States
  #   { <states here> }
  # }
  if script_type[file_path] == "ZSCRIPT" || script_type[file_path] == "BUILT_IN"
    actors = input_text.scan(/^\h*class\N*\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi)
  elsif script_type[file_path] == "DECORATE"
    actors = input_text.scan(/^\h*actor\N*\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi)
  end

  # transform regex match to strings
  actors = actors.nil? ? [] of String : actors.map {|match| match.to_s }

  puts "Actors:"
  actors.each do |actor|
   puts actor
   puts "------"
  end

  # Remove empty strings from the resulting array
  actors.reject! { |actor| actor.strip.empty? }

  actors.each_with_index do |actor, actor_index|
    # parse the actor's states, if any

    ## this is the old way
    ## states_raw = actor.gsub(/^states\n/im, "SPECIALDELIMITERstates\n")
    ## states_raw_split = states_raw.split("SPECIALDELIMITER")

    states_raw_split = actor.scan(/^\h*states\N*\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi)
    states_raw_split = states_raw_split.nil? ? [] of String : states_raw_split.map {|match| match.to_s }

    # THIS BLOCK I AM CONSIDERING REFACTORING AS I THINK WE CAN DO BETTER
    # AND I DON'T THINK THERE IS ANYTHING DEPENDENT ON IT
    ###################################################################
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
    #####################################################################

    puts "States before:"
    puts states_text
    puts "States after:"
    puts states

    puts "======================="
    # there are a few options here and we need to account for all of them
    # DECORATE
    # 0     1    2        3        4        5       6       7
    # actor blah
    # actor blah 1234
    # actor blah replaces oldblah
    # actor blah replaces oldblah 1234
    # actor blah :        oldblah
    # actor blah :        oldblah 1234
    # actor blah :        oldblah replaces oldblah
    # actor blah :        oldblah replaces oldblah 1234
    #
    # ZSCRIPT does not assign doomednums, which simplifies things
    # 0     1    2        3        4        5       6       7
    # class blah
    # class blah :        actor
    # class blah replaces oldblah
    # class blah :        actor    replaces oldblah
    #
    # either type can have "native" at the end, but that gets ignored
    # so I think the sorting logic should work for both DECORATE and ZSCRIPT

    #this has the full actor text in case we need to search it later
    actor_with_states = actor

    if script_type[file_path] == "DECORATE"
      actor_no_states = actor.to_s.gsub(/states\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi, "")
    elsif script_type[file_path] == "BUILT_IN" || script_type[file_path] == "ZSCRIPT"
      # we need to grab the match which will return the results with curly braces included
      # we also need the first line of the actor so that we can evaluate
      # actor name, inheritance, replaces
      actor_no_states_match = actor.match(/^\h*default\N*\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi)
      if actor_no_states_match
        actor_no_states = actor.to_s.lines.first + "\n" + actor_no_states_match[1].to_s
      else
        actor_no_states = actor.to_s.lines.first
      end
    end

    break if actor_no_states.nil?

    # remove any semicolons, and add a line break in case there are multiple
    # directives on one line... empty lines get removed anyway
    actor_no_states = actor_no_states.gsub(";", "\n")

    # split the actor_without_states into separate lines
    lines = actor_no_states.lines

    # get a case sensitive version
    lines_with_case = lines.map { |line| line.lstrip.strip }
    lines_with_case.reject! { |line| line.empty? }
    lines_with_case.compact!
    actor_with_case = lines_with_case.join("\n")
    first_line_with_case = lines_with_case.first
    name_with_case = first_line_with_case.split[1]

    # strip leading whitespace, trailing whitespace, and downcase
    lines.map! { |line| line.lstrip.strip.downcase }
    lines.reject! { |line| line.empty? }
    lines.compact!
    actor = lines.join("\n")

    first_line = lines.first
    # ensure colons are not connected to any character so that we can parse it easier
    first_line = first_line.gsub(":", " : ")
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
    new_actor.name_with_case = name_with_case
    new_actor.source_wad_folder = wad_folder_name
    new_actor.source_file = decorate_source_file
    new_actor.file_path = file_path
    new_actor.native = native
    new_actor.states = states
    # actor_text is used for checking actor flags and properties
    new_actor.actor_text = actor_no_states
    # full_actor_text is used for comparing actors with each other to find duplicates
    new_actor.full_actor_text = actor_with_states

    # number of words == 3 means that word[2] == a number
    if number_of_words == 3
      puts "Words(#{number_of_words}): #{words}"
      new_actor.doomednum = words[2].to_i
    end

    # there are 2 possibilities: colon (inheritance), or replaces
    if number_of_words == 4 || number_of_words == 5
      puts "Words(#{number_of_words}): #{words}"
      if words[2] == ":"
        new_actor.inherits = words[3]
      elsif words[2] == "replaces"
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
      puts "Words(#{number_of_words}): #{words}"
      new_actor.inherits = words[3]
      new_actor.replaces = words[5]
      if number_of_words == 7
        new_actor.doomednum = words[6].to_i
      end
    end

    actor.each_line.with_index do |line, index|
      # ignore first line - we already read it above
      next if index.zero?
      # flag the built in actors
      if script_type[file_path] == "BUILT_IN"
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

      if property_name =~ /^[\+|\-]/
        line.split.each do |flag|
          new_actor.flags_applied << flag
        end
      elsif property_name != "{" && property_name != "}" && property_name != "action" && property_name != "const" && property_name != "var" && property_name != "#include"
        new_actor.properties_applied << property_name
      end

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

          if flag_name == "interpolateangles"
            puts "  - Flag: #{flag}"
            new_actor.interpolateangles = flag_boolean
          elsif flag_name == "flatsprite"
            puts "  - Flag: #{flag}"
            new_actor.flatsprite = flag_boolean
          elsif flag_name == "rollsprite"
            puts "  - Flag: #{flag}"
            new_actor.rollsprite = flag_boolean
          elsif flag_name == "wallsprite"
            puts "  - Flag: #{flag}"
            new_actor.wallsprite = flag_boolean
          elsif flag_name == "rollcenter"
            puts "  - Flag: #{flag}"
            new_actor.rollcenter = flag_boolean
          elsif flag_name == "spriteangle"
            puts "  - Flag: #{flag}"
            new_actor.spriteangle = flag_boolean
          elsif flag_name == "spriteflip"
            puts "  - Flag: #{flag}"
            new_actor.spriteflip = flag_boolean
          elsif flag_name == "xflip"
            puts "  - Flag: #{flag}"
            new_actor.xflip = flag_boolean
          elsif flag_name == "yflip"
            puts "  - Flag: #{flag}"
            new_actor.yflip = flag_boolean
          elsif flag_name == "maskrotation"
            puts "  - Flag: #{flag}"
            new_actor.maskrotation = flag_boolean
          elsif flag_name == "absmaskangle"
            puts "  - Flag: #{flag}"
            new_actor.absmaskangle = flag_boolean
          elsif flag_name == "absmaskpitch"
            puts "  - Flag: #{flag}"
            new_actor.absmaskpitch = flag_boolean
          elsif flag_name == "dontinterpolate"
            puts "  - Flag: #{flag}"
            new_actor.dontinterpolate = flag_boolean
          elsif flag_name == "zdoomtrans"
            puts "  - Flag: #{flag}"
            new_actor.zdoomtrans = flag_boolean
          elsif flag_name == "absviewangles"
            puts "  - Flag: #{flag}"
            new_actor.absviewangles = flag_boolean
          elsif flag_name == "castspriteshadow"
            puts "  - Flag: #{flag}"
            new_actor.castspriteshadow = flag_boolean
          elsif flag_name == "nospriteshadow"
            puts "  - Flag: #{flag}"
            new_actor.nospriteshadow = flag_boolean
          elsif flag_name == "masternosee"
            puts "  - Flag: #{flag}"
            new_actor.masternosee = flag_boolean
          elsif flag_name == "addlightlevel"
            puts "  - Flag: #{flag}"
            new_actor.addlightlevel = flag_boolean
          elsif flag_name == "invisibleinmirrors"
            puts "  - Flag: #{flag}"
            new_actor.invisibleinmirrors = flag_boolean
          elsif flag_name == "onlyvisibleinmirrors"
            puts "  - Flag: #{flag}"
            new_actor.onlyvisibleinmirrors = flag_boolean
          elsif flag_name == "solid"
            puts "  - Flag: #{flag}"
            new_actor.solid = flag_boolean
          elsif flag_name == "shootable"
            puts "  - Flag: #{flag}"
            new_actor.shootable = flag_boolean
          elsif flag_name == "float"
            puts "  - Flag: #{flag}"
            new_actor.float = flag_boolean
          elsif flag_name == "nogravity"
            puts "  - Flag: #{flag}"
            new_actor.nogravity = flag_boolean
          elsif flag_name == "windthrust"
            puts "  - Flag: #{flag}"
            new_actor.windthrust = flag_boolean
          elsif flag_name == "pushable"
            puts "  - Flag: #{flag}"
            new_actor.pushable = flag_boolean
          elsif flag_name == "dontfall"
            puts "  - Flag: #{flag}"
            new_actor.dontfall = flag_boolean
          elsif flag_name == "canpass"
            puts "  - Flag: #{flag}"
            new_actor.canpass = flag_boolean
          elsif flag_name == "actlikebridge"
            puts "  - Flag: #{flag}"
            new_actor.actlikebridge = flag_boolean
          elsif flag_name == "noblockmap"
            puts "  - Flag: #{flag}"
            new_actor.noblockmap = flag_boolean
          elsif flag_name == "movewithsector"
            puts "  - Flag: #{flag}"
            new_actor.movewithsector = flag_boolean
          elsif flag_name == "relativetofloor"
            puts "  - Flag: #{flag}"
            new_actor.relativetofloor = flag_boolean
          elsif flag_name == "noliftdrop"
            puts "  - Flag: #{flag}"
            new_actor.noliftdrop = flag_boolean
          elsif flag_name == "slidesonwalls"
            puts "  - Flag: #{flag}"
            new_actor.slidesonwalls = flag_boolean
          elsif flag_name == "nodropoff"
            puts "  - Flag: #{flag}"
            new_actor.nodropoff = flag_boolean
          elsif flag_name == "noforwardfall"
            puts "  - Flag: #{flag}"
            new_actor.noforwardfall = flag_boolean
          elsif flag_name == "notrigger"
            puts "  - Flag: #{flag}"
            new_actor.notrigger = flag_boolean
          elsif flag_name == "blockedbysolidactors"
            puts "  - Flag: #{flag}"
            new_actor.blockedbysolidactors = flag_boolean
          elsif flag_name == "blockasplayer"
            puts "  - Flag: #{flag}"
            new_actor.blockasplayer = flag_boolean
          elsif flag_name == "nofriction"
            puts "  - Flag: #{flag}"
            new_actor.nofriction = flag_boolean
          elsif flag_name == "nofrictionbounce"
            puts "  - Flag: #{flag}"
            new_actor.nofrictionbounce = flag_boolean
          elsif flag_name == "falldamage"
            puts "  - Flag: #{flag}"
            new_actor.falldamage = flag_boolean
          elsif flag_name == "allowthrubits"
            puts "  - Flag: #{flag}"
            new_actor.allowthrubits = flag_boolean
          elsif flag_name == "crosslinecheck"
            puts "  - Flag: #{flag}"
            new_actor.crosslinecheck = flag_boolean
          elsif flag_name == "alwaysrespawn"
            puts "  - Flag: #{flag}"
            new_actor.alwaysrespawn = flag_boolean
          elsif flag_name == "ambush"
            puts "  - Flag: #{flag}"
            new_actor.ambush = flag_boolean
          elsif flag_name == "avoidmelee"
            puts "  - Flag: #{flag}"
            new_actor.avoidmelee = flag_boolean
          elsif flag_name == "boss"
            puts "  - Flag: #{flag}"
            new_actor.boss = flag_boolean
          elsif flag_name == "dontcorpse"
            puts "  - Flag: #{flag}"
            new_actor.dontcorpse = flag_boolean
          elsif flag_name == "dontfacetalker"
            puts "  - Flag: #{flag}"
            new_actor.dontfacetalker = flag_boolean
          elsif flag_name == "dormant"
            puts "  - Flag: #{flag}"
            new_actor.dormant = flag_boolean
          elsif flag_name == "friendly"
            puts "  - Flag: #{flag}"
            new_actor.friendly = flag_boolean
          elsif flag_name == "jumpdown"
            puts "  - Flag: #{flag}"
            new_actor.jumpdown = flag_boolean
          elsif flag_name == "lookallaround"
            puts "  - Flag: #{flag}"
            new_actor.lookallaround = flag_boolean
          elsif flag_name == "missileevenmore"
            puts "  - Flag: #{flag}"
            new_actor.missileevenmore = flag_boolean
          elsif flag_name == "missilemore"
            puts "  - Flag: #{flag}"
            new_actor.missilemore = flag_boolean
          elsif flag_name == "neverrespawn"
            puts "  - Flag: #{flag}"
            new_actor.neverrespawn = flag_boolean
          elsif flag_name == "nosplashalert"
            puts "  - Flag: #{flag}"
            new_actor.nosplashalert = flag_boolean
          elsif flag_name == "notargetswitch"
            puts "  - Flag: #{flag}"
            new_actor.notargetswitch = flag_boolean
          elsif flag_name == "noverticalmeleerange"
            puts "  - Flag: #{flag}"
            new_actor.noverticalmeleerange = flag_boolean
          elsif flag_name == "quicktoretaliate"
            puts "  - Flag: #{flag}"
            new_actor.quicktoretaliate = flag_boolean
          elsif flag_name == "standstill"
            puts "  - Flag: #{flag}"
            new_actor.standstill = flag_boolean
          elsif flag_name == "avoidhazards"
            puts "  - Flag: #{flag}"
            new_actor.avoidhazards = flag_boolean
          elsif flag_name == "stayonlift"
            puts "  - Flag: #{flag}"
            new_actor.stayonlift = flag_boolean
          elsif flag_name == "dontfollowplayers"
            puts "  - Flag: #{flag}"
            new_actor.dontfollowplayers = flag_boolean
          elsif flag_name == "seefriendlymonsters"
            puts "  - Flag: #{flag}"
            new_actor.seefriendlymonsters = flag_boolean
          elsif flag_name == "cannotpush"
            puts "  - Flag: #{flag}"
            new_actor.cannotpush = flag_boolean
          elsif flag_name == "noteleport"
            puts "  - Flag: #{flag}"
            new_actor.noteleport = flag_boolean
          elsif flag_name == "activateimpact"
            puts "  - Flag: #{flag}"
            new_actor.activateimpact = flag_boolean
          elsif flag_name == "canpushwalls"
            puts "  - Flag: #{flag}"
            new_actor.canpushwalls = flag_boolean
          elsif flag_name == "canusewalls"
            puts "  - Flag: #{flag}"
            new_actor.canusewalls = flag_boolean
          elsif flag_name == "activatemcross"
            puts "  - Flag: #{flag}"
            new_actor.activatemcross = flag_boolean
          elsif flag_name == "activatepcross"
            puts "  - Flag: #{flag}"
            new_actor.activatepcross = flag_boolean
          elsif flag_name == "cantleavefloorpic"
            puts "  - Flag: #{flag}"
            new_actor.cantleavefloorpic = flag_boolean
          elsif flag_name == "telestomp"
            puts "  - Flag: #{flag}"
            new_actor.telestomp = flag_boolean
          elsif flag_name == "notelestomp"
            puts "  - Flag: #{flag}"
            new_actor.notelestomp = flag_boolean
          elsif flag_name == "staymorphed"
            puts "  - Flag: #{flag}"
            new_actor.staymorphed = flag_boolean
          elsif flag_name == "canblast"
            puts "  - Flag: #{flag}"
            new_actor.canblast = flag_boolean
          elsif flag_name == "noblockmonst"
            puts "  - Flag: #{flag}"
            new_actor.noblockmonst = flag_boolean
          elsif flag_name == "allowthruflags"
            puts "  - Flag: #{flag}"
            new_actor.allowthruflags = flag_boolean
          elsif flag_name == "thrughost"
            puts "  - Flag: #{flag}"
            new_actor.thrughost = flag_boolean
          elsif flag_name == "thruactors"
            puts "  - Flag: #{flag}"
            new_actor.thruactors = flag_boolean
          elsif flag_name == "thruspecies"
            puts "  - Flag: #{flag}"
            new_actor.thruspecies = flag_boolean
          elsif flag_name == "mthruspecies"
            puts "  - Flag: #{flag}"
            new_actor.mthruspecies = flag_boolean
          elsif flag_name == "spectral"
            puts "  - Flag: #{flag}"
            new_actor.spectral = flag_boolean
          elsif flag_name == "frightened"
            puts "  - Flag: #{flag}"
            new_actor.frightened = flag_boolean
          elsif flag_name == "frightening"
            puts "  - Flag: #{flag}"
            new_actor.frightening = flag_boolean
          elsif flag_name == "notarget"
            puts "  - Flag: #{flag}"
            new_actor.notarget = flag_boolean
          elsif flag_name == "nevertarget"
            puts "  - Flag: #{flag}"
            new_actor.nevertarget = flag_boolean
          elsif flag_name == "noinfightspecies"
            puts "  - Flag: #{flag}"
            new_actor.noinfightspecies = flag_boolean
          elsif flag_name == "forceinfighting"
            puts "  - Flag: #{flag}"
            new_actor.forceinfighting = flag_boolean
          elsif flag_name == "noinfighting"
            puts "  - Flag: #{flag}"
            new_actor.noinfighting = flag_boolean
          elsif flag_name == "notimefreeze"
            puts "  - Flag: #{flag}"
            new_actor.notimefreeze = flag_boolean
          elsif flag_name == "nofear"
            puts "  - Flag: #{flag}"
            new_actor.nofear = flag_boolean
          elsif flag_name == "cantseek"
            puts "  - Flag: #{flag}"
            new_actor.cantseek = flag_boolean
          elsif flag_name == "seeinvisible"
            puts "  - Flag: #{flag}"
            new_actor.seeinvisible = flag_boolean
          elsif flag_name == "dontthrust"
            puts "  - Flag: #{flag}"
            new_actor.dontthrust = flag_boolean
          elsif flag_name == "allowpain"
            puts "  - Flag: #{flag}"
            new_actor.allowpain = flag_boolean
          elsif flag_name == "usekillscripts"
            puts "  - Flag: #{flag}"
            new_actor.usekillscripts = flag_boolean
          elsif flag_name == "nokillscripts"
            puts "  - Flag: #{flag}"
            new_actor.nokillscripts = flag_boolean
          elsif flag_name == "stoprails"
            puts "  - Flag: #{flag}"
            new_actor.stoprails = flag_boolean
          elsif flag_name == "minvisible"
            puts "  - Flag: #{flag}"
            new_actor.minvisible = flag_boolean
          elsif flag_name == "mvisblocked"
            puts "  - Flag: #{flag}"
            new_actor.mvisblocked = flag_boolean
          elsif flag_name == "shadowaim"
            puts "  - Flag: #{flag}"
            new_actor.shadowaim = flag_boolean
          elsif flag_name == "doshadowblock"
            puts "  - Flag: #{flag}"
            new_actor.doshadowblock = flag_boolean
          elsif flag_name == "shadowaimvert"
            puts "  - Flag: #{flag}"
            new_actor.shadowaimvert = flag_boolean
          elsif flag_name == "invulnerable"
            puts "  - Flag: #{flag}"
            new_actor.invulnerable = flag_boolean
          elsif flag_name == "buddha"
            puts "  - Flag: #{flag}"
            new_actor.buddha = flag_boolean
          elsif flag_name == "reflective"
            puts "  - Flag: #{flag}"
            new_actor.reflective = flag_boolean
          elsif flag_name == "shieldreflect"
            puts "  - Flag: #{flag}"
            new_actor.shieldreflect = flag_boolean
          elsif flag_name == "deflect"
            puts "  - Flag: #{flag}"
            new_actor.deflect = flag_boolean
          elsif flag_name == "mirrorreflect"
            puts "  - Flag: #{flag}"
            new_actor.mirrorreflect = flag_boolean
          elsif flag_name == "aimreflect"
            puts "  - Flag: #{flag}"
            new_actor.aimreflect = flag_boolean
          elsif flag_name == "thrureflect"
            puts "  - Flag: #{flag}"
            new_actor.thrureflect = flag_boolean
          elsif flag_name == "noradiusdmg"
            puts "  - Flag: #{flag}"
            new_actor.noradiusdmg = flag_boolean
          elsif flag_name == "dontblast"
            puts "  - Flag: #{flag}"
            new_actor.dontblast = flag_boolean
          elsif flag_name == "shadow"
            puts "  - Flag: #{flag}"
            new_actor.shadow = flag_boolean
          elsif flag_name == "ghost"
            puts "  - Flag: #{flag}"
            new_actor.ghost = flag_boolean
          elsif flag_name == "dontmorph"
            puts "  - Flag: #{flag}"
            new_actor.dontmorph = flag_boolean
          elsif flag_name == "dontsquash"
            puts "  - Flag: #{flag}"
            new_actor.dontsquash = flag_boolean
          elsif flag_name == "noteleother"
            puts "  - Flag: #{flag}"
            new_actor.noteleother = flag_boolean
          elsif flag_name == "harmfriends"
            puts "  - Flag: #{flag}"
            new_actor.harmfriends = flag_boolean
          elsif flag_name == "doharmspecies"
            puts "  - Flag: #{flag}"
            new_actor.doharmspecies = flag_boolean
          elsif flag_name == "dontharmclass"
            puts "  - Flag: #{flag}"
            new_actor.dontharmclass = flag_boolean
          elsif flag_name == "dontharmspecies"
            puts "  - Flag: #{flag}"
            new_actor.dontharmspecies = flag_boolean
          elsif flag_name == "nodamage"
            puts "  - Flag: #{flag}"
            new_actor.nodamage = flag_boolean
          elsif flag_name == "dontrip"
            puts "  - Flag: #{flag}"
            new_actor.dontrip = flag_boolean
          elsif flag_name == "notelefrag"
            puts "  - Flag: #{flag}"
            new_actor.notelefrag = flag_boolean
          elsif flag_name == "alwaystelefrag"
            puts "  - Flag: #{flag}"
            new_actor.alwaystelefrag = flag_boolean
          elsif flag_name == "dontdrain"
            puts "  - Flag: #{flag}"
            new_actor.dontdrain = flag_boolean
          elsif flag_name == "laxtelefragdmg"
            puts "  - Flag: #{flag}"
            new_actor.laxtelefragdmg = flag_boolean
          elsif flag_name == "shadowblock"
            puts "  - Flag: #{flag}"
            new_actor.shadowblock = flag_boolean
          elsif flag_name == "bright"
            puts "  - Flag: #{flag}"
            new_actor.bright = flag_boolean
          elsif flag_name == "invisible"
            puts "  - Flag: #{flag}"
            new_actor.invisible = flag_boolean
          elsif flag_name == "noblood"
            puts "  - Flag: #{flag}"
            new_actor.noblood = flag_boolean
          elsif flag_name == "noblooddecals"
            puts "  - Flag: #{flag}"
            new_actor.noblooddecals = flag_boolean
          elsif flag_name == "stealth"
            puts "  - Flag: #{flag}"
            new_actor.stealth = flag_boolean
          elsif flag_name == "floorclip"
            puts "  - Flag: #{flag}"
            new_actor.floorclip = flag_boolean
          elsif flag_name == "spawnfloat"
            puts "  - Flag: #{flag}"
            new_actor.spawnfloat = flag_boolean
          elsif flag_name == "spawnceiling"
            puts "  - Flag: #{flag}"
            new_actor.spawnceiling = flag_boolean
          elsif flag_name == "floatbob"
            puts "  - Flag: #{flag}"
            new_actor.floatbob = flag_boolean
          elsif flag_name == "noicedeath"
            puts "  - Flag: #{flag}"
            new_actor.noicedeath = flag_boolean
          elsif flag_name == "dontgib"
            puts "  - Flag: #{flag}"
            new_actor.dontgib = flag_boolean
          elsif flag_name == "dontsplash"
            puts "  - Flag: #{flag}"
            new_actor.dontsplash = flag_boolean
          elsif flag_name == "dontoverlap"
            puts "  - Flag: #{flag}"
            new_actor.dontoverlap = flag_boolean
          elsif flag_name == "randomize"
            puts "  - Flag: #{flag}"
            new_actor.randomize = flag_boolean
          elsif flag_name == "fixmapthingpos"
            puts "  - Flag: #{flag}"
            new_actor.fixmapthingpos = flag_boolean
          elsif flag_name == "fullvolactive"
            puts "  - Flag: #{flag}"
            new_actor.fullvolactive = flag_boolean
          elsif flag_name == "fullvoldeath"
            puts "  - Flag: #{flag}"
            new_actor.fullvoldeath = flag_boolean
          elsif flag_name == "fullvolsee"
            puts "  - Flag: #{flag}"
            new_actor.fullvolsee = flag_boolean
          elsif flag_name == "nowallbouncesnd"
            puts "  - Flag: #{flag}"
            new_actor.nowallbouncesnd = flag_boolean
          elsif flag_name == "visibilitypulse"
            puts "  - Flag: #{flag}"
            new_actor.visibilitypulse = flag_boolean
          elsif flag_name == "rockettrail"
            puts "  - Flag: #{flag}"
            new_actor.rockettrail = flag_boolean
          elsif flag_name == "grenadetrail"
            puts "  - Flag: #{flag}"
            new_actor.grenadetrail = flag_boolean
          elsif flag_name == "nobouncesound"
            puts "  - Flag: #{flag}"
            new_actor.nobouncesound = flag_boolean
          elsif flag_name == "noskin"
            puts "  - Flag: #{flag}"
            new_actor.noskin = flag_boolean
          elsif flag_name == "donttranslate"
            puts "  - Flag: #{flag}"
            new_actor.donttranslate = flag_boolean
          elsif flag_name == "nopain"
            puts "  - Flag: #{flag}"
            new_actor.nopain = flag_boolean
          elsif flag_name == "forceybillboard"
            puts "  - Flag: #{flag}"
            new_actor.forceybillboard = flag_boolean
          elsif flag_name == "forcexybillboard"
            puts "  - Flag: #{flag}"
            new_actor.forcexybillboard = flag_boolean
          elsif flag_name == "missile"
            puts "  - Flag: #{flag}"
            new_actor.missile = flag_boolean
          elsif flag_name == "ripper"
            puts "  - Flag: #{flag}"
            new_actor.ripper = flag_boolean
          elsif flag_name == "nobossrip"
            puts "  - Flag: #{flag}"
            new_actor.nobossrip = flag_boolean
          elsif flag_name == "nodamagethrust"
            puts "  - Flag: #{flag}"
            new_actor.nodamagethrust = flag_boolean
          elsif flag_name == "dontreflect"
            puts "  - Flag: #{flag}"
            new_actor.dontreflect = flag_boolean
          elsif flag_name == "noshieldreflect"
            puts "  - Flag: #{flag}"
            new_actor.noshieldreflect = flag_boolean
          elsif flag_name == "noshieldreflect"
            puts "  - Flag: #{flag}"
            new_actor.noshieldreflect = flag_boolean
          elsif flag_name == "floorhugger"
            puts "  - Flag: #{flag}"
            new_actor.floorhugger = flag_boolean
          elsif flag_name == "ceilinghugger"
            puts "  - Flag: #{flag}"
            new_actor.ceilinghugger = flag_boolean
          elsif flag_name == "bloodlessimpact"
            puts "  - Flag: #{flag}"
            new_actor.bloodlessimpact = flag_boolean
          elsif flag_name == "bloodsplatter"
            puts "  - Flag: #{flag}"
            new_actor.bloodsplatter = flag_boolean
          elsif flag_name == "foilinvul"
            puts "  - Flag: #{flag}"
            new_actor.foilinvul = flag_boolean
          elsif flag_name == "foilbuddha"
            puts "  - Flag: #{flag}"
            new_actor.foilbuddha = flag_boolean
          elsif flag_name == "seekermissile"
            puts "  - Flag: #{flag}"
            new_actor.seekermissile = flag_boolean
          elsif flag_name == "screenseeker"
            puts "  - Flag: #{flag}"
            new_actor.screenseeker = flag_boolean
          elsif flag_name == "skyexplode"
            puts "  - Flag: #{flag}"
            new_actor.skyexplode = flag_boolean
          elsif flag_name == "noexplodefloor"
            puts "  - Flag: #{flag}"
            new_actor.noexplodefloor = flag_boolean
          elsif flag_name == "strifedamage"
            puts "  - Flag: #{flag}"
            new_actor.strifedamage = flag_boolean
          elsif flag_name == "extremedeath"
            puts "  - Flag: #{flag}"
            new_actor.extremedeath = flag_boolean
          elsif flag_name == "noextremedeath"
            puts "  - Flag: #{flag}"
            new_actor.noextremedeath = flag_boolean
          elsif flag_name == "dehexplosion"
            puts "  - Flag: #{flag}"
            new_actor.dehexplosion = flag_boolean
          elsif flag_name == "piercearmor"
            puts "  - Flag: #{flag}"
            new_actor.piercearmor = flag_boolean
          elsif flag_name == "forceradiusdmg"
            puts "  - Flag: #{flag}"
            new_actor.forceradiusdmg = flag_boolean
          elsif flag_name == "forcezeroradiusdmg"
            puts "  - Flag: #{flag}"
            new_actor.forcezeroradiusdmg = flag_boolean
          elsif flag_name == "spawnsoundsource"
            puts "  - Flag: #{flag}"
            new_actor.spawnsoundsource = flag_boolean
          elsif flag_name == "painless"
            puts "  - Flag: #{flag}"
            new_actor.painless = flag_boolean
          elsif flag_name == "forcepain"
            puts "  - Flag: #{flag}"
            new_actor.forcepain = flag_boolean
          elsif flag_name == "causepain"
            puts "  - Flag: #{flag}"
            new_actor.causepain = flag_boolean
          elsif flag_name == "dontseekinvisible"
            puts "  - Flag: #{flag}"
            new_actor.dontseekinvisible = flag_boolean
          elsif flag_name == "stepmissile"
            puts "  - Flag: #{flag}"
            new_actor.stepmissile = flag_boolean
          elsif flag_name == "additivepoisondamage"
            puts "  - Flag: #{flag}"
            new_actor.additivepoisondamage = flag_boolean
          elsif flag_name == "additivepoisonduration"
            puts "  - Flag: #{flag}"
            new_actor.additivepoisonduration = flag_boolean
          elsif flag_name == "poisonalways"
            puts "  - Flag: #{flag}"
            new_actor.poisonalways = flag_boolean
          elsif flag_name == "hittarget"
            puts "  - Flag: #{flag}"
            new_actor.hittarget = flag_boolean
          elsif flag_name == "hitmaster"
            puts "  - Flag: #{flag}"
            new_actor.hitmaster = flag_boolean
          elsif flag_name == "hittracer"
            puts "  - Flag: #{flag}"
            new_actor.hittracer = flag_boolean
          elsif flag_name == "hitowner"
            puts "  - Flag: #{flag}"
            new_actor.hitowner = flag_boolean
          elsif flag_name == "bounceonwalls"
            puts "  - Flag: #{flag}"
            new_actor.bounceonwalls = flag_boolean
          elsif flag_name == "bounceonfloors"
            puts "  - Flag: #{flag}"
            new_actor.bounceonfloors = flag_boolean
          elsif flag_name == "bounceonceilings"
            puts "  - Flag: #{flag}"
            new_actor.bounceonceilings = flag_boolean
          elsif flag_name == "allowbounceonactors"
            puts "  - Flag: #{flag}"
            new_actor.allowbounceonactors = flag_boolean
          elsif flag_name == "bounceautooff"
            puts "  - Flag: #{flag}"
            new_actor.bounceautooff = flag_boolean
          elsif flag_name == "bounceautooffflooronly"
            puts "  - Flag: #{flag}"
            new_actor.bounceautooffflooronly = flag_boolean
          elsif flag_name == "bouncelikeheretic"
            puts "  - Flag: #{flag}"
            new_actor.bouncelikeheretic = flag_boolean
          elsif flag_name == "bounceonactors"
            puts "  - Flag: #{flag}"
            new_actor.bounceonactors = flag_boolean
          elsif flag_name == "bounceonunrippables"
            puts "  - Flag: #{flag}"
            new_actor.bounceonunrippables = flag_boolean
          elsif flag_name == "nowallbouncesnd"
            puts "  - Flag: #{flag}"
            new_actor.nowallbouncesnd = flag_boolean
          elsif flag_name == "nobouncesound"
            puts "  - Flag: #{flag}"
            new_actor.nobouncesound = flag_boolean
          elsif flag_name == "explodeonwater"
            puts "  - Flag: #{flag}"
            new_actor.explodeonwater = flag_boolean
          elsif flag_name == "canbouncewater"
            puts "  - Flag: #{flag}"
            new_actor.canbouncewater = flag_boolean
          elsif flag_name == "mbfbouncer"
            puts "  - Flag: #{flag}"
            new_actor.mbfbouncer = flag_boolean
          elsif flag_name == "usebouncestate"
            puts "  - Flag: #{flag}"
            new_actor.usebouncestate = flag_boolean
          elsif flag_name == "dontbounceonshootables"
            puts "  - Flag: #{flag}"
            new_actor.dontbounceonshootables = flag_boolean
          elsif flag_name == "dontbounceonsky"
            puts "  - Flag: #{flag}"
            new_actor.dontbounceonsky = flag_boolean
          elsif flag_name == "iceshatter"
            puts "  - Flag: #{flag}"
            new_actor.iceshatter = flag_boolean
          elsif flag_name == "dropped"
            puts "  - Flag: #{flag}"
            new_actor.dropped = flag_boolean
          elsif flag_name == "ismonster"
            puts "  - Flag: #{flag}"
            new_actor.ismonster = flag_boolean
          elsif flag_name == "corpse"
            puts "  - Flag: #{flag}"
            new_actor.corpse = flag_boolean
          elsif flag_name == "countitem"
            puts "  - Flag: #{flag}"
            new_actor.countitem = flag_boolean
          elsif flag_name == "countkill"
            puts "  - Flag: #{flag}"
            new_actor.countkill = flag_boolean
          elsif flag_name == "countsecret"
            puts "  - Flag: #{flag}"
            new_actor.countsecret = flag_boolean
          elsif flag_name == "notdmatch"
            puts "  - Flag: #{flag}"
            new_actor.notdmatch = flag_boolean
          elsif flag_name == "nonshootable"
            puts "  - Flag: #{flag}"
            new_actor.nonshootable = flag_boolean
          elsif flag_name == "dropoff"
            puts "  - Flag: #{flag}"
            new_actor.dropoff = flag_boolean
          elsif flag_name == "puffonactors"
            puts "  - Flag: #{flag}"
            new_actor.puffonactors = flag_boolean
          elsif flag_name == "allowparticles"
            puts "  - Flag: #{flag}"
            new_actor.allowparticles = flag_boolean
          elsif flag_name == "alwayspuff"
            puts "  - Flag: #{flag}"
            new_actor.alwayspuff = flag_boolean
          elsif flag_name == "puffgetsowner"
            puts "  - Flag: #{flag}"
            new_actor.puffgetsowner = flag_boolean
          elsif flag_name == "forcedecal"
            puts "  - Flag: #{flag}"
            new_actor.forcedecal = flag_boolean
          elsif flag_name == "nodecal"
            puts "  - Flag: #{flag}"
            new_actor.nodecal = flag_boolean
          elsif flag_name == "synchronized"
            puts "  - Flag: #{flag}"
            new_actor.synchronized = flag_boolean
          elsif flag_name == "alwaysfast"
            puts "  - Flag: #{flag}"
            new_actor.alwaysfast = flag_boolean
          elsif flag_name == "neverfast"
            puts "  - Flag: #{flag}"
            new_actor.neverfast = flag_boolean
          elsif flag_name == "oldradiusdmg"
            puts "  - Flag: #{flag}"
            new_actor.oldradiusdmg = flag_boolean
          elsif flag_name == "usespecial"
            puts "  - Flag: #{flag}"
            new_actor.usespecial = flag_boolean
          elsif flag_name == "bumpspecial"
            puts "  - Flag: #{flag}"
            new_actor.bumpspecial = flag_boolean
          elsif flag_name == "bossdeath"
            puts "  - Flag: #{flag}"
            new_actor.bossdeath = flag_boolean
          elsif flag_name == "nointeraction"
            puts "  - Flag: #{flag}"
            new_actor.nointeraction = flag_boolean
          elsif flag_name == "notautoaimed"
            puts "  - Flag: #{flag}"
            new_actor.notautoaimed = flag_boolean
          elsif flag_name == "nomenu"
            puts "  - Flag: #{flag}"
            new_actor.nomenu = flag_boolean
          elsif flag_name == "pickup"
            puts "  - Flag: #{flag}"
            new_actor.pickup = flag_boolean
          elsif flag_name == "touchy"
            puts "  - Flag: #{flag}"
            new_actor.touchy = flag_boolean
          elsif flag_name == "vulnerable"
            puts "  - Flag: #{flag}"
            new_actor.vulnerable = flag_boolean
          elsif flag_name == "notonautomap"
            puts "  - Flag: #{flag}"
            new_actor.notonautomap = flag_boolean
          elsif flag_name == "weaponspawn"
            puts "  - Flag: #{flag}"
            new_actor.weaponspawn = flag_boolean
          elsif flag_name == "getowner"
            puts "  - Flag: #{flag}"
            new_actor.getowner = flag_boolean
          elsif flag_name == "seesdaggers"
            puts "  - Flag: #{flag}"
            new_actor.seesdaggers = flag_boolean
          elsif flag_name == "incombat"
            puts "  - Flag: #{flag}"
            new_actor.incombat = flag_boolean
          elsif flag_name == "noclip"
            puts "  - Flag: #{flag}"
            new_actor.noclip = flag_boolean
          elsif flag_name == "nosector"
            puts "  - Flag: #{flag}"
            new_actor.nosector = flag_boolean
          elsif flag_name == "icecorpse"
            puts "  - Flag: #{flag}"
            new_actor.icecorpse = flag_boolean
          elsif flag_name == "justhit"
            puts "  - Flag: #{flag}"
            new_actor.justhit = flag_boolean
          elsif flag_name == "justattacked"
            puts "  - Flag: #{flag}"
            new_actor.justattacked = flag_boolean
          elsif flag_name == "teleport"
            puts "  - Flag: #{flag}"
            new_actor.teleport = flag_boolean
          elsif flag_name == "blasted"
            puts "  - Flag: #{flag}"
            new_actor.blasted = flag_boolean
          elsif flag_name == "explocount"
            puts "  - Flag: #{flag}"
            new_actor.explocount = flag_boolean
          elsif flag_name == "skullfly"
            puts "  - Flag: #{flag}"
            new_actor.skullfly = flag_boolean
          elsif flag_name == "retargetafterslam"
            puts "  - Flag: #{flag}"
            new_actor.retargetafterslam = flag_boolean
          elsif flag_name == "onlyslamsolid"
            puts "  - Flag: #{flag}"
            new_actor.onlyslamsolid = flag_boolean
          elsif flag_name == "specialfiredamage"
            puts "  - Flag: #{flag}"
            new_actor.specialfiredamage = flag_boolean
          elsif flag_name == "specialfloorclip"
            puts "  - Flag: #{flag}"
            new_actor.specialfloorclip = flag_boolean
          elsif flag_name == "summonedmonster"
            puts "  - Flag: #{flag}"
            new_actor.summonedmonster = flag_boolean
          elsif flag_name == "special"
            puts "  - Flag: #{flag}"
            new_actor.special = flag_boolean
          elsif flag_name == "nosavegame"
            puts "  - Flag: #{flag}"
            new_actor.nosavegame = flag_boolean
          elsif flag_name == "e1m8boss"
            puts "  - Flag: #{flag}"
            new_actor.e1m8boss = flag_boolean
          elsif flag_name == "e2m8boss"
            puts "  - Flag: #{flag}"
            new_actor.e2m8boss = flag_boolean
          elsif flag_name == "e3m8boss"
            puts "  - Flag: #{flag}"
            new_actor.e3m8boss = flag_boolean
          elsif flag_name == "e4m6boss"
            puts "  - Flag: #{flag}"
            new_actor.e4m6boss = flag_boolean
          elsif flag_name == "e4m8boss"
            puts "  - Flag: #{flag}"
            new_actor.e4m8boss = flag_boolean
          elsif flag_name == "inchase"
            puts "  - Flag: #{flag}"
            new_actor.inchase = flag_boolean
          elsif flag_name == "unmorphed"
            puts "  - Flag: #{flag}"
            new_actor.unmorphed = flag_boolean
          elsif flag_name == "fly"
            puts "  - Flag: #{flag}"
            new_actor.fly = flag_boolean
          elsif flag_name == "onmobj"
            puts "  - Flag: #{flag}"
            new_actor.onmobj = flag_boolean
          elsif flag_name == "argsdefined"
            puts "  - Flag: #{flag}"
            new_actor.argsdefined = flag_boolean
          elsif flag_name == "nosightcheck"
            puts "  - Flag: #{flag}"
            new_actor.nosightcheck = flag_boolean
          elsif flag_name == "crashed"
            puts "  - Flag: #{flag}"
            new_actor.crashed = flag_boolean
          elsif flag_name == "warnbot"
            puts "  - Flag: #{flag}"
            new_actor.warnbot = flag_boolean
          elsif flag_name == "huntplayers"
            puts "  - Flag: #{flag}"
            new_actor.huntplayers = flag_boolean
          elsif flag_name == "nohateplayers"
            puts "  - Flag: #{flag}"
            new_actor.nohateplayers = flag_boolean
          elsif flag_name == "scrollmove"
            puts "  - Flag: #{flag}"
            new_actor.scrollmove = flag_boolean
          elsif flag_name == "vfriction"
            puts "  - Flag: #{flag}"
            new_actor.vfriction = flag_boolean
          elsif flag_name == "bossspawned"
            puts "  - Flag: #{flag}"
            new_actor.bossspawned = flag_boolean
          elsif flag_name == "avoidingdropoff"
            puts "  - Flag: #{flag}"
            new_actor.avoidingdropoff = flag_boolean
          elsif flag_name == "chasegoal"
            puts "  - Flag: #{flag}"
            new_actor.chasegoal = flag_boolean
          elsif flag_name == "inconversation"
            puts "  - Flag: #{flag}"
            new_actor.inconversation = flag_boolean
          elsif flag_name == "armed"
            puts "  - Flag: #{flag}"
            new_actor.armed = flag_boolean
          elsif flag_name == "falling"
            puts "  - Flag: #{flag}"
            new_actor.falling = flag_boolean
          elsif flag_name == "linedone"
            puts "  - Flag: #{flag}"
            new_actor.linedone = flag_boolean
          elsif flag_name == "shattering"
            puts "  - Flag: #{flag}"
            new_actor.shattering = flag_boolean
          elsif flag_name == "killed"
            puts "  - Flag: #{flag}"
            new_actor.killed = flag_boolean
          elsif flag_name == "bosscube"
            puts "  - Flag: #{flag}"
            new_actor.bosscube = flag_boolean
          elsif flag_name == "intrymove"
            puts "  - Flag: #{flag}"
            new_actor.intrymove = flag_boolean
          elsif flag_name == "handlenodelay"
            puts "  - Flag: #{flag}"
            new_actor.handlenodelay = flag_boolean
          elsif flag_name == "flycheat"
            puts "  - Flag: #{flag}"
            new_actor.flycheat = flag_boolean
          elsif flag_name == "respawninvul"
            puts "  - Flag: #{flag}"
            new_actor.respawninvul = flag_boolean
          elsif flag_name == "lowgravity"
            puts "  - Flag: #{flag}"
            new_actor.lowgravity = flag_boolean
          elsif flag_name == "quartergravity"
            puts "  - Flag: #{flag}"
            new_actor.quartergravity = flag_boolean
          elsif flag_name == "longmeleerange"
            puts "  - Flag: #{flag}"
            new_actor.longmeleerange = flag_boolean
          elsif flag_name == "shortmissilerange"
            puts "  - Flag: #{flag}"
            new_actor.shortmissilerange = flag_boolean
          elsif flag_name == "highermprob"
            puts "  - Flag: #{flag}"
            new_actor.highermprob = flag_boolean
          elsif flag_name == "fireresist"
            puts "  - Flag: #{flag}"
            new_actor.fireresist = flag_boolean
          elsif flag_name == "donthurtspecies"
            puts "  - Flag: #{flag}"
            new_actor.donthurtspecies = flag_boolean
          elsif flag_name == "firedamage"
            puts "  - Flag: #{flag}"
            new_actor.firedamage = flag_boolean
          elsif flag_name == "icedamage"
            puts "  - Flag: #{flag}"
            new_actor.icedamage = flag_boolean
          elsif flag_name == "hereticbounce"
            puts "  - Flag: #{flag}"
            new_actor.hereticbounce = flag_boolean
          elsif flag_name == "hexenbounce"
            puts "  - Flag: #{flag}"
            new_actor.hexenbounce = flag_boolean
          elsif flag_name == "doombounce"
            puts "  - Flag: #{flag}"
            new_actor.doombounce = flag_boolean
          elsif flag_name == "faster"
            puts "  - Flag: #{flag}"
            new_actor.faster = flag_boolean
          elsif flag_name == "fastmelee"
            puts "  - Flag: #{flag}"
            new_actor.fastmelee = flag_boolean
          elsif flag_name == "inventory.quiet"
            puts "  - Flag: #{flag}"
            new_actor.inventory.quiet = flag_boolean
          elsif flag_name == "inventory.autoactivate"
            puts "  - Flag: #{flag}"
            new_actor.inventory.autoactivate = flag_boolean
          elsif flag_name == "inventory.undroppable" || flag_name == "undroppable"
            puts "  - Flag: #{flag}"
            new_actor.inventory.undroppable = flag_boolean
          elsif flag_name == "inventory.unclearable"
            puts "  - Flag: #{flag}"
            new_actor.inventory.unclearable = flag_boolean
          elsif flag_name == "inventory.invbar" || flag_name == "invbar"
            puts "  - Flag: #{flag}"
            new_actor.inventory.invbar = flag_boolean
          elsif flag_name == "inventory.hubpower"
            puts "  - Flag: #{flag}"
            new_actor.inventory.hubpower = flag_boolean
          elsif flag_name == "inventory.persistentpower"
            puts "  - Flag: #{flag}"
            new_actor.inventory.persistentpower = flag_boolean
          elsif flag_name == "inventory.interhubstrip"
            puts "  - Flag: #{flag}"
            new_actor.inventory.interhubstrip = flag_boolean
          elsif flag_name == "inventory.pickupflash"
            puts "  - Flag: #{flag}"
            new_actor.inventory.pickupflash = flag_boolean
          elsif flag_name == "inventory.alwayspickup"
            puts "  - Flag: #{flag}"
            new_actor.inventory.alwayspickup = flag_boolean
          elsif flag_name == "inventory.fancypickupsound" || flag_name == "fancypickupsound"
            puts "  - Flag: #{flag}"
            new_actor.inventory.fancypickupsound = flag_boolean
          elsif flag_name == "inventory.noattenpickupsound"
            puts "  - Flag: #{flag}"
            new_actor.inventory.noattenpickupsound = flag_boolean
          elsif flag_name == "inventory.bigpowerup"
            puts "  - Flag: #{flag}"
            new_actor.inventory.bigpowerup = flag_boolean
          elsif flag_name == "inventory.neverrespawn"
            puts "  - Flag: #{flag}"
            new_actor.inventory.neverrespawn = flag_boolean
          elsif flag_name == "inventory.keepdepleted"
            puts "  - Flag: #{flag}"
            new_actor.inventory.keepdepleted = flag_boolean
          elsif flag_name == "inventory.ignoreskill"
            puts "  - Flag: #{flag}"
            new_actor.inventory.ignoreskill = flag_boolean
          elsif flag_name == "inventory.additivetime"
            puts "  - Flag: #{flag}"
            new_actor.inventory.additivetime = flag_boolean
          elsif flag_name == "inventory.untossable"
            puts "  - Flag: #{flag}"
            new_actor.inventory.untossable = flag_boolean
          elsif flag_name == "inventory.restrictabsolutely"
            puts "  - Flag: #{flag}"
            new_actor.inventory.restrictabsolutely = flag_boolean
          elsif flag_name == "inventory.noscreenflash"
            puts "  - Flag: #{flag}"
            new_actor.inventory.noscreenflash = flag_boolean
          elsif flag_name == "inventory.tossed"
            puts "  - Flag: #{flag}"
            new_actor.inventory.tossed = flag_boolean
          elsif flag_name == "inventory.alwaysrespawn"
            puts "  - Flag: #{flag}"
            new_actor.inventory.alwaysrespawn = flag_boolean
          elsif flag_name == "inventory.transfer"
            puts "  - Flag: #{flag}"
            new_actor.inventory.transfer = flag_boolean
          elsif flag_name == "inventory.noteleportfreeze"
            puts "  - Flag: #{flag}"
            new_actor.inventory.noteleportfreeze = flag_boolean
          elsif flag_name == "inventory.noscreenblink"
            puts "  - Flag: #{flag}"
            new_actor.inventory.noscreenblink = flag_boolean
          elsif flag_name == "inventory.ishealth"
            puts "  - Flag: #{flag}"
            new_actor.inventory.ishealth = flag_boolean
          elsif flag_name == "inventory.isarmor"
            puts "  - Flag: #{flag}"
            new_actor.inventory.isarmor = flag_boolean
          elsif flag_name == "weapon.noautofire"
            puts "  - Flag: #{flag}"
            new_actor.weapon.noautofire = flag_boolean
          elsif flag_name == "weapon.readysndhalf"
            puts "  - Flag: #{flag}"
            new_actor.weapon.readysndhalf = flag_boolean
          elsif flag_name == "weapon.dontbob"
            puts "  - Flag: #{flag}"
            new_actor.weapon.dontbob = flag_boolean
          elsif flag_name == "weapon.axeblood"
            puts "  - Flag: #{flag}"
            new_actor.weapon.axeblood = flag_boolean
          elsif flag_name == "weapon.noalert"
            puts "  - Flag: #{flag}"
            new_actor.weapon.noalert = flag_boolean
          elsif flag_name == "weapon.ammo_optional"
            puts "  - Flag: #{flag}"
            new_actor.weapon.ammo_optional = flag_boolean
          elsif flag_name == "weapon.alt_ammo_optional"
            puts "  - Flag: #{flag}"
            new_actor.weapon.alt_ammo_optional = flag_boolean
          elsif flag_name == "weapon.ammo_checkboth"
            puts "  - Flag: #{flag}"
            new_actor.weapon.ammo_checkboth = flag_boolean
          elsif flag_name == "weapon.primary_uses_both"
            puts "  - Flag: #{flag}"
            new_actor.weapon.primary_uses_both = flag_boolean
          elsif flag_name == "weapon.alt_uses_both"
            puts "  - Flag: #{flag}"
            new_actor.weapon.alt_uses_both = flag_boolean
          elsif flag_name == "weapon.wimpy_weapon" || flag_name == "wimpy_weapon"
            puts "  - Flag: #{flag}"
            new_actor.weapon.wimpy_weapon = flag_boolean
          elsif flag_name == "weapon.powered_up" || flag_name == "powered_up"
            puts "  - Flag: #{flag}"
            new_actor.weapon.powered_up = flag_boolean
          elsif flag_name == "weapon.staff2_kickback"
            puts "  - Flag: #{flag}"
            new_actor.weapon.staff2_kickback = flag_boolean
          elsif flag_name == "weapon.explosive"
            puts "  - Flag: #{flag}"
            new_actor.weapon.explosive = flag_boolean
          elsif flag_name == "weapon.meleeweapon" || flag_name == "meleeweapon"
            puts "  - Flag: #{flag}"
            new_actor.weapon.meleeweapon = flag_boolean
          elsif flag_name == "weapon.bfg"
            puts "  - Flag: #{flag}"
            new_actor.weapon.bfg = flag_boolean
          elsif flag_name == "weapon.cheatnotweapon"
            puts "  - Flag: #{flag}"
            new_actor.weapon.cheatnotweapon = flag_boolean
          elsif flag_name == "weapon.noautoswitchto"
            puts "  - Flag: #{flag}"
            new_actor.weapon.noautoswitchto = flag_boolean
          elsif flag_name == "weapon.noautoaim"
            puts "  - Flag: #{flag}"
            new_actor.weapon.noautoaim = flag_boolean
          elsif flag_name == "weapon.nodeathdeselect"
            puts "  - Flag: #{flag}"
            new_actor.weapon.nodeathdeselect = flag_boolean
          elsif flag_name == "weapon.nodeathinput"
            puts "  - Flag: #{flag}"
            new_actor.weapon.nodeathinput = flag_boolean
          elsif flag_name == "powerspeed.notrail"
            puts "  - Flag: #{flag}"
            new_actor.powerspeed.notrail = flag_boolean
          elsif flag_name == "playerpawn.nothrustwheninvul" || flag_name == "nothrustwheninvul"
            puts "  - Flag: #{flag}"
            new_actor.player.nothrustwheninvul = flag_boolean
          elsif flag_name == "playerpawn.cansupermorph" || flag_name == "cansupermorph"
            puts "  - Flag: #{flag}"
            new_actor.player.cansupermorph = flag_boolean
          elsif flag_name == "playerpawn.crouchablemorph"
            puts "  - Flag: #{flag}"
            new_actor.player.crouchablemorph = flag_boolean
          elsif flag_name == "playerpawn.weaponlevel2ended"
            puts "  - Flag: #{flag}"
            new_actor.player.weaponlevel2ended = flag_boolean
          elsif flag_name == "allowclientspawn"
            puts "  - Flag: #{flag}"
            new_actor.allowclientspawn = flag_boolean
          elsif flag_name == "clientsideonly"
            puts "  - Flag: #{flag}"
            new_actor.clientsideonly = flag_boolean
          elsif flag_name == "nonetid"
            puts "  - Flag: #{flag}"
            new_actor.nonetid = flag_boolean
          elsif flag_name == "dontidentifytarget"
            puts "  - Flag: #{flag}"
            new_actor.dontidentifytarget = flag_boolean
          elsif flag_name == "scorepillar"
            puts "  - Flag: #{flag}"
            new_actor.scorepillar = flag_boolean
          elsif flag_name == "serversideonly"
            puts "  - Flag: #{flag}"
            new_actor.serversideonly = flag_boolean
          elsif flag_name == "inventory.forcerespawninsurvival"
            puts "  - Flag: #{flag}"
            new_actor.inventory.forcerespawninsurvival = flag_boolean
          elsif flag_name == "weapon.allow_with_respawn_invul"
            puts "  - Flag: #{flag}"
            new_actor.weapon.allow_with_respawn_invul = flag_boolean
          elsif flag_name == "weapon.nolms"
            puts "  - Flag: #{flag}"
            new_actor.weapon.nolms = flag_boolean
          elsif flag_name == "piercearmor"
            puts "  - Flag: #{flag}"
            new_actor.piercearmor = flag_boolean
          elsif flag_name == "blueteam"
            puts "  - Flag: #{flag}"
            new_actor.blueteam = flag_boolean
          elsif flag_name == "redteam"
            puts "  - Flag: #{flag}"
            new_actor.redteam = flag_boolean
          elsif flag_name == "node"
            puts "  - Flag: #{flag}"
            new_actor.node = flag_boolean
          elsif flag_name == "basehealth"
            puts "  - Flag: #{flag}"
            new_actor.basehealth = flag_boolean
          elsif flag_name == "superhealth"
            puts "  - Flag: #{flag}"
            new_actor.superhealth = flag_boolean
          elsif flag_name == "basearmor"
            puts "  - Flag: #{flag}"
            new_actor.basearmor = flag_boolean
          elsif flag_name == "superarmor"
            puts "  - Flag: #{flag}"
            new_actor.superarmor = flag_boolean
          elsif flag_name == "explodeondeath"
            puts "  - Flag: #{flag}"
            new_actor.explodeondeath = flag_boolean

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
        # adding {0} default value as hacky solution to enums for health value
        new_actor.health = line.split[1].to_i {0}
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
        new_actor.float_bob_strength = line.split[1].to_f
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
        #new_actor.monster = true
        new_actor.ismonster = true
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
        puts "  - FakeInventory.Respawns"
        new_actor.fakeinventory.respawns = true

      elsif property_name == "armor.saveamount"
        puts "  - Armor.SaveAmount: " + line.split[1..-1].join(' ')
        new_actor.armor.saveamount = line.split[1].to_i
      elsif property_name == "armor.savepercent"
        puts "  - Armor.SavePercent: " + line.split[1..-1].join(' ')
        new_actor.armor.savepercent = line.split[1].to_f
      elsif property_name == "armor.maxfullabsorb"
        puts "  - Armor.MaxFullAbsorb: " + line.split[1..-1].join(' ')
        new_actor.armor.maxfullabsorb = line.split[1].to_i
      elsif property_name == "armor.maxabsorb"
        puts "  - Armor.MaxAbsorb: " + line.split[1..-1].join(' ')
        new_actor.armor.maxabsorb = line.split[1].to_i
      elsif property_name == "armor.maxsaveamount"
        puts "  - Armor.MaxSaveAmount: " + line.split[1..-1].join(' ')
        new_actor.armor.maxsaveamount = line.split[1].to_i
      elsif property_name == "armor.maxbonus"
        puts "  - Armor.maxbonus: " + line.split[1..-1].join(' ')
        new_actor.armor.maxbonus = line.split[1].to_i
      elsif property_name == "armor.maxbonusmax"
        puts "  - Armor.MaxBonusMax: " + line.split[1..-1].join(' ')
        new_actor.armor.maxbonusmax = line.split[1].to_i

      elsif property_name == "weapon.ammogive"
        puts "  - Weapon.AmmoGive: " + line.split[1..-1].join(' ')
        new_actor.weapon.ammogive = line.split[1].to_i
      elsif property_name == "weapon.ammogive1"
        puts "  - Weapon.AmmoGive1: " + line.split[1..-1].join(' ')
        new_actor.weapon.ammogive1 = line.split[1].to_i
      elsif property_name == "weapon.ammogive2"
        puts "  - Weapon.AmmoGive2: " + line.split[1..-1].join(' ')
        new_actor.weapon.ammogive2 = line.split[1].to_i
      elsif property_name == "weapon.ammotype"
        puts "  - Weapon.AmmoType: " + line.split[1..-1].join(' ')
        new_actor.weapon.ammotype = line.split[1..-1].join(' ')
      elsif property_name == "weapon.ammotype1"
        puts "  - Weapon.AmmoType1: " + line.split[1..-1].join(' ')
        new_actor.weapon.ammotype1 = line.split[1..-1].join(' ')
      elsif property_name == "weapon.ammotype2"
        puts "  - Weapon.AmmoType2: " + line.split[1..-1].join(' ')
        new_actor.weapon.ammotype2 = line.split[1..-1].join(' ')
      elsif property_name == "weapon.ammouse"
        puts "  - Weapon.AmmoUse: " + line.split[1..-1].join(' ')
        new_actor.weapon.ammouse = line.split[1].to_i
      elsif property_name == "weapon.ammouse1"
        puts "  - Weapon.AmmoUse1: " + line.split[1..-1].join(' ')
        new_actor.weapon.ammouse1 = line.split[1].to_i
      elsif property_name == "weapon.ammouse2"
        puts "  - Weapon.AmmoUse2: " + line.split[1..-1].join(' ')
        new_actor.weapon.ammouse2 = line.split[1].to_i
      elsif property_name == "weapon.minselectionammo1"
        puts "  - Weapon.MinSelectionAmmo1: " + line.split[1..-1].join(' ')
        new_actor.weapon.minselectionammo1 = line.split[1].to_i
      elsif property_name == "weapon.minselectionammo2"
        puts "  - Weapon.MinSelectionAmmo2: " + line.split[1..-1].join(' ')
        new_actor.weapon.minselectionammo2 = line.split[1].to_i
      elsif property_name == "weapon.bobpivot3d"
        puts "  - Weapon.BobPivot3D: " + line.split[1..-1].join(' ')
        new_actor.weapon.bobpivot3d = line.split[1..-1]?.to_s
      elsif property_name == "weapon.bobrangex"
        puts "  - Weapon.BobRangeX: " + line.split[1..-1].join(' ')
        new_actor.weapon.bobrangex = line.split[1].to_f
      elsif property_name == "weapon.bobrangey"
        puts "  - Weapon.BobRangeY: " + line.split[1..-1].join(' ')
        new_actor.weapon.bobrangey = line.split[1].to_f
      elsif property_name == "weapon.bobspeed"
        puts "  - Weapon.BobSpeed: " + line.split[1..-1].join(' ')
        new_actor.weapon.bobspeed = line.split[1].to_f
      elsif property_name == "weapon.bobstyle"
        puts "  - Weapon.BobStyle: " + line.split[1..-1].join(' ')
        new_actor.weapon.bobstyle = line.split[1..-1]?.to_s
      elsif property_name == "weapon.kickback"
        puts "  - Weapon.KickBack: " + line.split[1..-1].join(' ')
        new_actor.weapon.kickback = line.split[1].to_i
      elsif property_name == "weapon.defaultkickback"
        puts "  - Weapon.DefaultKickBack: " + line.split[1..-1].join(' ')
        new_actor.weapon.defaultkickback = true
      elsif property_name == "weapon.readysound"
        puts "  - Weapon.ReadySound: " + line.split[1..-1].join(' ')
        new_actor.weapon.readysound = line.split[1..-1]?.to_s
      elsif property_name == "weapon.selectionorder"
        puts "  - Weapon.SelectionOrder: " + line.split[1..-1].join(' ')
        new_actor.weapon.selectionorder = line.split[1].to_i
      elsif property_name == "weapon.sisterweapon"
        puts "  - Weapon.SisterWeapon: " + line.split[1..-1].join(' ')
        new_actor.weapon.sisterweapon = line.split[1..-1]?.to_s
      elsif property_name == "weapon.slotnumber"
        puts "  - Weapon.SlotNumber: " + line.split[1..-1].join(' ')
        new_actor.weapon.slotnumber = line.split[1].to_i
      elsif property_name == "weapon.slotpriority"
        puts "  - Weapon.SlotPriority: " + line.split[1..-1].join(' ')
        new_actor.weapon.slotpriority = line.split[1].to_f
      elsif property_name == "weapon.upsound"
        puts "  - Weapon.UpSound: " + line.split[1..-1].join(' ')
        new_actor.weapon.upsound = line.split[1..-1]?.to_s
      elsif property_name == "weapon.weaponscalex"
        puts "  - Weapon.WeaponScaleX: " + line.split[1..-1].join(' ')
        new_actor.weapon.weaponscalex = line.split[1].to_f
      elsif property_name == "weapon.weaponscaley"
        puts "  - Weapon.WeaponScaleY: " + line.split[1..-1].join(' ')
        new_actor.weapon.weaponscaley = line.split[1].to_f
      elsif property_name == "weapon.yadjust"
        puts "  - Weapon.YAdjust: " + line.split[1..-1].join(' ')
        new_actor.weapon.yadjust = line.split[1].to_i
      elsif property_name == "weapon.lookscale"
        puts "  - Weapon.LookScale: " + line.split[1..-1].join(' ')
        new_actor.weapon.lookscale = line.split[1].to_f

      # Ammo
      elsif property_name == "ammo.backpackamount"
        puts "  - Ammo.BackpackAmount: " + line.split[1..-1].join(' ')
        new_actor.ammo.backpackamount = line.split[1].to_i
      elsif property_name == "ammo.backpackmaxamount"
        puts "  - Ammo.BackpackMaxAmount: " + line.split[1..-1].join(' ')
        new_actor.ammo.backpackmaxamount = line.split[1].to_i
      elsif property_name == "ammo.dropamount"
        puts "  - Ammo.DropAmount: " + line.split[1..-1].join(' ')
        new_actor.ammo.dropamount = line.split[1].to_i

      # Weapon Piece
      elsif property_name == "weaponpiece.number"
        puts "  - WeaponPiece.Number: " + line.split[1..-1].join(' ')
        new_actor.weaponpiece.number = line.split[1].to_i
      elsif property_name == "weaponpiece.weapon"
        puts "  - WeaponPiece.Weapon: " + line.split[1..-1].join(' ')
        new_actor.weaponpiece.weapon = line.split[1..-1]?.to_s

      # Health (note: health is named healthclass to differentiate from health property)
      elsif property_name == "health.lowmessage"
        puts "  - Health.LowMessage: " + line.split[1..-1].join(' ')
        new_actor.healthclass.lowmessage = line.split[1..-1]?.to_s

      # Puzzle Item
      elsif property_name == "puzzleitem.number"
        puts "  - PuzzleItem.Number: " + line.split[1..-1].join(' ')
        new_actor.puzzleitem.number = line.split[1].to_i
      elsif property_name == "puzzleitem.failmessage"
        puts "  - PuzzleItem.FailMessage: " + line.split[1..-1].join(' ')
        new_actor.puzzleitem.failmessage = line.split[1..-1]?.to_s
      elsif property_name == "puzzleitem.failsound"
        puts "  - PuzzleItem.FailSound: " + line.split[1..-1].join(' ')
        new_actor.puzzleitem.failsound = line.split[1]?.to_s

      # PlayerPawn
      elsif property_name == "player.aircapacity"
        puts "    - player.aircapacity: " + line.split[1..-1].join(' ')
        new_actor.player.aircapacity = line.split[1].to_f
      elsif property_name == "player.attackzoffset"
        puts "    - player.attackzoffset: " + line.split[1..-1].join(' ')
        new_actor.player.attackzoffset = line.split[1].to_i
      elsif property_name == "player.clearcolorset"
        puts "    - player.clearcolorset: " + line.split[1..-1].join(' ')
        new_actor.player.clearcolorset = line.split[1].to_i
      elsif property_name == "player.colorrange"
        puts "    - player.colorrange: " + line.split[1..-1].join(' ')
        new_actor.player.colorrange = line.split[1..-1].join(' ')
      elsif property_name == "player.colorset"
        puts "    - player.colorset: " + line.split[1..-1].join(' ')
        new_actor.player.colorset = line.split[1]?.to_s
      elsif property_name == "player.colorsetfile"
        puts "    - player.colorsetfile: " + line.split[1..-1].join(' ')
        new_actor.player.colorsetfile = line.split[1..-1].join(' ')
      elsif property_name == "player.crouchsprite"
        puts "    - player.crouchsprite: " + line.split[1..-1].join(' ')
        new_actor.player.crouchsprite = line.split[1]?.to_s
      elsif property_name == "player.damagescreencolor"
        puts "    - player.damagescreencolor: " + line.split[1..-1].join(' ')
        new_actor.player.damagescreencolor = line.split[1..-1].join(' ')
      elsif property_name == "player.displayname"
        puts "    - player.displayname: " + line.split[1..-1].join(' ')
        new_actor.player.displayname = line.split[1]?.to_s
      elsif property_name == "player.face"
        puts "    - player.face: " + line.split[1..-1].join(' ')
        new_actor.player.face = line.split[1]?.to_s
      elsif property_name == "player.fallingscreamspeed"
        puts "    - player.fallingscreamspeed: " + line.split[1..-1].join(' ')
        new_actor.player.fallingscreamspeed = line.split[1..-1].join(' ')
      elsif property_name == "player.flechettetype"
        puts "    - player.flechettetype: " + line.split[1..-1].join(' ')
        new_actor.player.flechettetype = line.split[1]?.to_s
      elsif property_name == "player.flybob"
        puts "    - player.flybob: " + line.split[1..-1].join(' ')
        new_actor.player.flybob = line.split[1].to_f
      elsif property_name == "player.forwardmove"
        puts "    - player.forwardmove: " + line.split[1..-1].join(' ')
        new_actor.player.forwardmove = line.split[1..-1].join(' ')
      elsif property_name == "player.gruntspeed"
        puts "    - player.gruntspeed: " + line.split[1..-1].join(' ')
        new_actor.player.gruntspeed = line.split[1].to_f
      elsif property_name == "player.healradiustype"
        puts "    - player.healradiustype: " + line.split[1..-1].join(' ')
        new_actor.player.healradiustype = line.split[1]?.to_s
      elsif property_name == "player.hexenarmor"
        puts "    - player.hexenarmor: " + line.split[1..-1].join(' ')
        new_actor.player.hexenarmor = line.split[1]?.to_s
      elsif property_name == "player.invulnerabilitymode"
        puts "    - player.invulnerabilitymode: " + line.split[1..-1].join(' ')
        new_actor.player.invulnerabilitymode = line.split[1]?.to_s
      elsif property_name == "player.jumpz"
        puts "    - player.jumpz: " + line.split[1..-1].join(' ')
        new_actor.player.jumpz = line.split[1].to_f
      elsif property_name == "player.maxhealth"
        puts "    - player.maxhealth: " + line.split[1..-1].join(' ')
        new_actor.player.maxhealth = line.split[1].to_i
      elsif property_name == "player.morphweapon"
        puts "    - player.morphweapon: " + line.split[1..-1].join(' ')
        new_actor.player.morphweapon = line.split[1]?.to_s
      elsif property_name == "player.mugshotmaxhealth"
        puts "    - player.mugshotmaxhealth: " + line.split[1..-1].join(' ')
        new_actor.player.mugshotmaxhealth = line.split[1].to_i
      elsif property_name == "player.portrait"
        puts "    - player.portrait: " + line.split[1..-1].join(' ')
        new_actor.player.portrait = line.split[1]?.to_s
      elsif property_name == "player.runhealth"
        puts "    - player.runhealth: " + line.split[1..-1].join(' ')
        new_actor.player.runhealth = line.split[1].to_i
      elsif property_name == "player.scoreicon"
        puts "    - player.scoreicon: " + line.split[1..-1].join(' ')
        new_actor.player.scoreicon = line.split[1]?.to_s
      elsif property_name == "player.sidemove"
        puts "    - player.sidemove: " + line.split[1..-1].join(' ')
        new_actor.player.sidemove = line.split[1..-1].join(' ')
      elsif property_name == "player.soundclass"
        puts "    - player.soundclass: " + line.split[1..-1].join(' ')
        new_actor.player.soundclass = line.split[1]?.to_s
      elsif property_name == "player.spawnclass"
        puts "    - player.spawnclass: " + line.split[1..-1].join(' ')
        new_actor.player.spawnclass = line.split[1]?.to_s
      elsif property_name == "player.startitem"
        puts "    - player.startitem: " + line.split[1..-1].join(' ')
        new_actor.player.startitem = line.split[1..-1].join(' ')
      elsif property_name == "player.teleportfreezetime"
        puts "    - player.teleportfreezetime: " + line.split[1..-1].join(' ')
        new_actor.player.teleportfreezetime = line.split[1].to_i
      elsif property_name == "player.userange"
        puts "    - player.userange: " + line.split[1..-1].join(' ')
        new_actor.player.userange = line.split[1].to_f
      elsif property_name == "player.viewbob"
        puts "    - player.viewbob: " + line.split[1..-1].join(' ')
        new_actor.player.viewbob = line.split[1].to_f
      elsif property_name == "player.viewbobspeed"
        puts "    - player.viewbobspeed: " + line.split[1..-1].join(' ')
        new_actor.player.viewbobspeed = line.split[1].to_f
      elsif property_name == "player.viewheight"
        puts "    - player.viewheight: " + line.split[1..-1].join(' ')
        new_actor.player.viewheight = line.split[1].to_f
      elsif property_name == "player.waterclimbspeed"
        puts "    - player.waterclimbspeed: " + line.split[1..-1].join(' ')
        new_actor.player.waterclimbspeed = line.split[1].to_f
      elsif property_name == "player.weaponslot"
        puts "    - player.weaponslot: " + line.split[1..-1].join(' ')
        new_actor.player.weaponslot = line.split[1..-1].join(' ')

      # Powerup
      elsif property_name == "powerup.color"
        puts "    - powerup.color: " + line.split[1..-1].join(' ')
        new_actor.powerup.color = line.split[1]?.to_s
      elsif property_name == "powerup.colormap"
        puts "    - powerup.colormap: " + line.split[1..-1].join(' ')
        new_actor.powerup.colormap = line.split[1..-1].join(' ')
      elsif property_name == "powerup.duration"
        puts "    - powerup.duration: " + line.split[1..-1].join(' ')
        new_actor.powerup.duration = line.split[1]?.to_s
      elsif property_name == "powerup.mode"
        puts "    - powerup.mode: " + line.split[1..-1].join(' ')
        new_actor.powerup.mode = line.split[1]?.to_s
      elsif property_name == "powerup.strength"
        puts "    - powerup.strength: " + line.split[1..-1].join(' ')
        new_actor.powerup.strength = line.split[1].to_f

      # PowerSpeed
      elsif property_name == "powerspeed.notrail"
        puts "    - powerspeed.notrail: " + line.split[1..-1].join(' ')
        if line.split[1].to_i == 1
          new_actor.powerspeed.notrail = true
        elsif line.split[1].to_i == 0
          new_actor.powerspeed.notrail = false
        end

      # PowerupGiver
      elsif property_name == "powerup.type"
        puts "    - powerup.type: " + line.split[1..-1].join(' ')
        new_actor.powerup.type = line.split[1]?.to_s

      # HealthPickup
      elsif property_name == "healthpickup.autouse"
        puts "    - healthpickup.autouse: " + line.split[1..-1].join(' ')
        new_actor.healthpickup.autouse = line.split[1].to_i

      # MorphProjectile
      elsif property_name == "morphprojectile.playerclass"
        puts "    - morphprojectile.playerclass: " + line.split[1..-1].join(' ')
        new_actor.morphprojectile.playerclass = line.split[1]?.to_s
      elsif property_name == "morphprojectile.monsterclass"
        puts "    - morphprojectile.monsterclass: " + line.split[1..-1].join(' ')
        new_actor.morphprojectile.monsterclass = line.split[1]?.to_s
      elsif property_name == "morphprojectile.duration"
        puts "    - morphprojectile.duration: " + line.split[1..-1].join(' ')
        new_actor.morphprojectile.duration = line.split[1].to_i
      elsif property_name == "morphprojectile.morphstyle"
        puts "    - morphprojectile.morphstyle: " + line.split[1..-1].join(' ')
        new_actor.morphprojectile.morphstyle = line.split[1..-1].join(' ')
      elsif property_name == "morphprojectile.morphflash"
        puts "    - morphprojectile.morphflash: " + line.split[1..-1].join(' ')
        new_actor.morphprojectile.morphflash = line.split[1..-1].join(' ')
      elsif property_name == "morphprojectile.unmorphflash"
        puts "    - morphprojectile.unmorphflash: " + line.split[1..-1].join(' ')
        new_actor.morphprojectile.unmorphflash = line.split[1..-1].join(' ')

      # Exclude any rouge curly brackets or include statements
      elsif property_name == "{" || property_name == "}" || property_name == "#include"
        # ignore these and do nothing
      # Log any missing property names so that we can address them
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
    # write out the new_actor to actordb
    actordb << new_actor
    puts "======================="
  end
end

actordb.each do |actor|
  puts "Actor: #{actor.name}"
  puts "Properties:"
  puts actor.properties_applied
  puts "Flags"
  puts actor.flags_applied
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

puts "=========================="
puts "END FILE READING"

#puts "====================="
#puts "PAUSING FOR CHECKS..."
#puts "====================="
#STDIN.gets

puts "=========================="
puts "Removing Identical Actors"
puts "=========================="
# actor_counter is the UUID for renamed actors
# before: ZombieMan
# after: ZombieMan_MonsterMash_0
actor_counter = 0
# first step is evaluate the list of files that are in scope
# DECORATE.raw is always going to be in scope, but any include file
# is also going to be in scope
# file_list = Array(String).new

# find identical actors and mark them for deletion

# Find actors with identical actor_text properties
# this includes the actor line including only the actor name and inheritance
# and the full actor text without any comments
# e.g.
#  actor blah [: blah2] <removed text>
#  {
#  <stuff here ...>
#  }
identical_actors = actordb.group_by { |actor|
  lines = actor.full_actor_text.lines
  first_line = lines[0]
  inherits = first_line.partition(/\:\s+[^\s]*/)
  first_line = first_line.split[0..1].join(' ')
  if inherits[1] != ""
    first_line = first_line + " " + inherits[1]
  end
  puts "First Line: #{first_line}"
  lines = first_line + "\n" + lines[1..-1].join("\n")
  lines = lines.lines
  lines.map! { |line| line.lstrip.strip.downcase }
  lines.reject! { |line| line.empty? }
  lines.compact!
  formatted_actor_text = lines.join("\n")
  formatted_actor_text }
  # actors size > 1 means that there is a duplicate entry
  .select { |_, actors| actors.size > 1 }
  .flat_map { |_, actors| actors }

# Print actors with identical actor_text properties
identical_actors.each do |actor|
  puts "Actor with identical actor_text: #{actor.name}"
  #puts "Inherited Actor #{actor.inherits}"
  #puts "Wad: #{actor.source_wad_folder}"
  #puts "#{actor.full_actor_text}"
end


# Remove the offending actors from their respective wad file
# ------------------------------------------------------------
# Here is the logic in plain english
# - we compare the following: actor name, full_actor_text
# - we don't care about replaces; those will be removed
# - we DO care about inheritance, if there are duplicate actors with the same name but inheriting different actors
#   they will be renamed
#
# Once we determine which actors will need to be removed, we will need to collect the following
# - actor.name
# - actor.source_wad_folder
# - actor.
# Regex:  ^actor\s+greenpoisonball\s+[^{]*\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})
# where "greenpoisonball" is the offending actor... we will use a variable for that

# identical_actor_name = "UNDEFINED"
# identical_actors.each_with_index do |actor, actor_index|
#   # if the identical_actor_name != actor.name, it means the actor changed
#   # They come into the list grouped by name like this:
#   # actor1, actor1, actor1, actor2, actor2, actor3, actor3, actor4, actor4...
#   # since we DO want one of each (we are only deleting DUPLICATES),
#   # we will go to next iteration when this occurs
#   if identical_actor_name != actor.name
#     identical_actor_name = actor.name
#     # mark the actor as primary in actordb - this way we will not touch it later
#     actordb[actor.index].primary = true
#     next
#   end
#
#   puts "Identical Actors Index: #{actor_index}"
#   file_text = File.read(actor.file_path)
#
#   if script_type[actor.file_path] == "ZSCRIPT"
#     regex = /^\h*class\s+#{actor.name}\s+[^{]*\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi
#   elsif script_type[actor.file_path] == "DECORATE"
#     regex = /^\h*actor\s+#{actor.name}\s+[^{]*\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi
#   elsif script_type[actor.file_path] == "BUILT_IN"
#     #take no action, since this is a built in actor
#     puts "Built In Actor: #{actor.name_with_case}. Skipping..."
#     next
#   else
#     next
#   end
#
#   puts "Removing Actor:"
#   puts file_text.partition(regex)[1]
#
#   file_text_post = file_text.gsub(regex, "// duplicate actor removed: #{actor.name}")
#
#   File.write(actor.file_path, file_text_post)
#
#   puts "---------------------------------------------------------"
#   puts "Removing Actor Name: #{actor.name}, Index: #{actor.index}"
#   puts "---------------------------------------------------------"
#   deletion_indexes = Array(Int32).new
#   actordb.each_with_index do |actor_del, actor_del_index|
#     if actor_del.index == actor.index && actor_del.file_path == actor.file_path
#       puts "actor_del name: #{actor_del.name}, actor name: #{actor.name}"
#       deletion_indexes << actor_del_index
#     end
#   end
#   #reverse order so that it doesn't delete the wrong actors
#   # e.g. it should delete the element 12 before deleting element 10
#   # otherwise it would delete element 10 and then delete former element 13 (I think)
#   deletion_indexes.reverse!
#   deletion_indexes.each do |deletion_index|
#     puts "Deleting #{actordb[deletion_index].name}..."
#     actordb.delete_at(deletion_index)
#   end
# end

puts "=========================="
puts "CHECKING DUPLICATES"
puts "=========================="

# Experiments with a new duplicate detection method...
# We are sorting by the different fields that we want to query by...
# e.g. actors_by_name["doomimp"] will return an array of Actors that are named "doomimp"
actors_by_name = actordb.reduce(Hash(String, Array(Actor)).new) do |acc, actor|
  acc ||= Hash(String, Array(Actor)).new
  if acc.fetch(actor.name, nil)
    iteration_array = acc[actor.name]
  else
    iteration_array = Array(Actor).new
  end
  iteration_array << actor
  acc[actor.name] = iteration_array

  acc
end


# this code doesn't do anything useful
#puts "==================================="
#puts "Actor Dupe Count"
#puts "==================================="
#if actors_by_name.size > 0
#  actors_by_name.each_key do |key|
#    puts "Actor Name: #{key}"
#    puts "Actor Count: #{actors_by_name[key].size}"
#    if actors_by_inherits.fetch(key, nil)
#      puts "Inherit Count: #{actors_by_inherits[key].size}"
#    end
#    if actors_by_replaces.fetch(key, nil)
#      puts "Replace Count: #{actors_by_replaces[key].size}"
#    end
#    puts "----------------------------------"
#  end
#end

puts "===================================="
puts "Renaming Duplicate Actor Names"
puts "===================================="
# process out any built-ins out of the list because they ruin our counts
actors_by_name.each_key do |key|
  deletion_indexes = Array(Int32).new
  actors_by_name[key].each_with_index do |actor, actor_index|
    if actor.file_path.split("#{fs}")[1] == "Built_In_Actors"
      puts "Actor is Built In: #{actor.name}"
      deletion_indexes << actor_index
    end
  end
  # reverse the array so it goes largest to smallest
  deletion_indexes.reverse!
  deletion_indexes.each do |deletion|
    actors_by_name[key].delete_at(deletion)
  end
end

# do the renames
actors_by_name.each_key do |key|
  if actors_by_name[key].size > 1
    puts "Actor: #{key} Count: #{actors_by_name[key].size}"
    actor_counter = 0
    actors_by_name[key].each_with_index do |actor, actor_index|
      #if key == "gemturret"
      #  puts "Actor Name With Case: \"#{actor.name_with_case}\""
      #  puts "Actor Name No Case: \"#{actor.name}\""
      #  actor.name_with_case.each_byte do |byte|
      #    print byte.to_s(16).rjust(2, '0') + " "
      #  end
      #  puts
      #  puts "waiting..."
      #  gets
      #end
      if actor_index == 0
        puts "Primary:"
      end
      puts "Actor File: #{actor.file_path}"

      # do a gsub for every file in the defs folder of that wad
      # (?<=[\s"])WyvernBall(?=[\s"])
      # remove the last field of the file path, which is the file name
      wad_folder = actor.file_path.split("#{fs}")[0..2].join("#{fs}") + "#{fs}**#{fs}*"
      puts wad_folder
      puts Dir.glob(wad_folder).inspect
      #if key == "gemturret"
      #  puts "waiting..."
      #  gets
      #end
      puts "Wad Folder: #{wad_folder}"
      if actor_index == 0
         puts "Renames:"
         next
      end
      Dir.glob(wad_folder).each do |file|
        next if File.directory?(file)
        puts file
        if binary_file?(file) == true
          puts " - File is binary"
          #if key == "gemturret"
          #  gets
          #end
          next
        else
          puts " - File is not binary"
          #if key == "gemturret"
          #  gets
          #end
        end
        file_text = File.read(file)
        #puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
        #puts "File Text Pre:"
        #puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
        #puts file_text
        search_term = "#{actor.name_with_case}"
        renamed_actor = "#{actor.name_with_case}_MM#{actor_counter.to_s}"

        # the actor name should either be surrounded by spaces
        # ' actorname '
        # or by quotes
        # '"actorname"'
        # which is what [\s"] accomplishes in the regex
        # regex_search = /(?<=[\s"])#{search_term}(?=[\s"])/i

        # Regex is too hard here... we need to do more fine tuned replacement
        # There may be a better solution but I am not seeing it
        file_lines = file_text.lines
        file_lines.each_with_index do |line, line_index|
          words = line.split
          words.each_with_index do |word, word_index|
            # word 0 is never going to be the actor name
            next if word_index == 0
            if word.downcase == actor.name
              words[word_index] = renamed_actor
            elsif word =~ /\"#{actor.name}\"/
              words[word_index] = word.gsub(/\"#{actor.name}\"/, "\"#{renamed_actor}\"")
            end
          end
          file_lines[line_index] = words.join(" ")
        end
        file_text_modified = file_lines.join("\n")
        #if key == "gemturret"
        #  puts file_text_modified
        #  puts actor.name_with_case
        #  gets
        #end
        #puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
        #puts "File Text Post:"
        #puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
        #puts file_text
        if file_text != file_text_modified
          File.write(file, file_text_modified)
          # rename the actor in actordb
          actordb.each_with_index do |actorrename, actorrename_index|
            if actor.file_path.downcase == actorrename.file_path.downcase && actor.name.downcase == actorrename.name.downcase
              actordb[actorrename_index].renamed_with_case = renamed_actor
              actordb[actorrename_index].renamed = renamed_actor.downcase
            end
          end
          puts "File: #{file}"
          puts file_text_modified
          #puts "waiting..."
          #gets
        end
      end
      puts "------------------------------"
      actor_counter += 1
    end
  end
end
# Update actor names to their renamed values
actordb.each_with_index do |actor, actor_index|
  if actor.renamed != "UNDEFINED"
    actordb[actor_index].name = actor.renamed
    actordb[actor_index].name_with_case = actor.renamed_with_case
    puts actor.renamed_with_case
  end
end
# All duplicate names should be addressed by this point.

# Update actordb and perform deletions if they are gone
deletion_indexes = Array(Int32).new
actordb.each_with_index do |actor, actor_index|
  next if actor.native == true
  #check if the actor still exists
  if script_type[actor.file_path] == "DECORATE"
    regex = /^\h*actor\s+#{actor.name}/mi
  elsif script_type[actor.file_path] == "ZSCRIPT"
    regex = /^\h*class\s+#{actor.name}/mi
  elsif script_type[actor.file_path] == "BUILT_IN"
    next
  end
  file_paths_array = Array(String).new
  #file_text_array = Array(String).new
  #file_text = File.read(actor.file_path)
  #file_text_array << file_text
  success = false
  file_paths_array << actor.file_path
  file_paths_array.each do |file_path|
    #check the case insensitve list we built at the beginning
    file_path = case_insensitive_file_db[file_path.downcase]
    next if File.directory?(file_path)
    text = File.read(file_path)
    lines = text.lines
    lines.each do |line|
      if line =~ /^\#include/i
        if actor.file_path.split("#{fs}")[1] == "Processing"
          include_file = file_path.split("#{fs}")[0..-2].join("#{fs}") + "#{fs}" + line.lstrip.strip.split[1].split('"')[1].upcase + ".raw"
        elsif actor.file_path.split("#{fs}")[1] == "Processing_PK3"
          # an out of bounds include file should have already thrown a fatal error, so I think this is safe to do
          puts "Scanning source file: #{file_path}"
          puts "Include Line: #{line}"
          puts "Actor.source_file: #{actor.source_file}"
          include_file = ".#{fs}" + Path.posix(file_path.split("#{fs}")[0..-2].join("#{fs}") + "#{fs}" + line.split('"')[1]).normalize.to_s

        else
          next
        end
        #puts "Include File: #{include_file}"
        file_paths_array << include_file
      end
    end
    if text =~ regex
      puts "Actor found! #{actor.name} - #{actor.file_path}"
      success = true
    end
  end
  if success == false
    puts "Removing missing actor from actordb: #{actor.name} - #{actor.file_path}"
    deletion_indexes << actor_index
  end
end
deletion_indexes.reverse!
if deletion_indexes.empty? == false
  deletion_indexes.each do |deletion_index|
    puts "Deleting #{actordb[deletion_index].name_with_case}..."
    actordb.delete_at(deletion_index)
  end
end

# refresh actors_by_name to the latest
actors_by_name = actordb.reduce(Hash(String, Array(Actor)).new) do |acc, actor|
  acc ||= Hash(String, Array(Actor)).new
  if acc.fetch(actor.name, nil)
    iteration_array = acc[actor.name]
  else
    iteration_array = Array(Actor).new
  end
  iteration_array << actor
  acc[actor.name] = iteration_array

  acc
end

# identify weapons
actordb.each_with_index do |actor, actor_index|
  # skip any built_in weapons
  next if actor.built_in == true

  # we are going to assume that any weapon values
  # means that it is in fact a weapon
  # probably not a safe bet, but it might be "good enough"
  if actor.weapon.noautofire == true ||
     actor.weapon.readysndhalf == true ||
     actor.weapon.dontbob == true ||
     actor.weapon.axeblood == true ||
     actor.weapon.noalert == true ||
     actor.weapon.ammo_optional == true ||
     actor.weapon.alt_ammo_optional == true ||
     actor.weapon.ammo_checkboth == true ||
     actor.weapon.primary_uses_both == true ||
     actor.weapon.alt_uses_both == true ||
     actor.weapon.wimpy_weapon == true ||
     actor.weapon.powered_up == true ||
     actor.weapon.staff2_kickback == true ||
     actor.weapon.explosive == true ||
     actor.weapon.meleeweapon == true ||
     actor.weapon.bfg == true ||
     actor.weapon.cheatnotweapon == true ||
     actor.weapon.noautoswitchto == true ||
     actor.weapon.noautoaim == true ||
     actor.weapon.nodeathdeselect == true ||
     actor.weapon.nodeathinput == true ||
     actor.weapon.allow_with_respawn_invul == true ||
     actor.weapon.nolms == true ||
     
     actor.weapon.ammogive != -1 ||
     actor.weapon.ammogive1 != -1 ||
     actor.weapon.ammogive2 != -1 ||
     actor.weapon.ammotype != "UNDEFINED" ||
     actor.weapon.ammotype1 != "UNDEFINED" ||
     actor.weapon.ammotype2 != "UNDEFINED" ||
     actor.weapon.ammouse != -1 ||
     actor.weapon.ammouse1 != -1 ||
     actor.weapon.ammouse2 != -1 ||
     actor.weapon.minselectionammo1 != -1 ||
     actor.weapon.minselectionammo2 != -1 ||
     actor.weapon.bobpivot3d != "UNDEFINED" ||
     actor.weapon.bobrangex != 1.0 ||
     actor.weapon.bobrangey != 1.0 ||
     actor.weapon.bobspeed != 1.0 ||
     actor.weapon.bobstyle != "UNDEFINED" ||
     actor.weapon.kickback != -1 ||
     actor.weapon.defaultkickback == true ||
     actor.weapon.readysound != "UNDEFINED" ||
     actor.weapon.selectionorder != -1 ||
     actor.weapon.sisterweapon != "UNDEFINED" ||
     actor.weapon.slotnumber != -1 ||
     actor.weapon.slotpriority != 0.0 ||
     actor.weapon.upsound != "UNDEFINED" ||
     actor.weapon.weaponscalex != 1.0 ||
     actor.weapon.weaponscaley != 1.2 ||
     actor.weapon.yadjust != 0 ||
     actor.weapon.lookscale != 0.0
    actordb[actor_index].is_weapon = true
    puts "Weapon: #{actor.name_with_case}"

    # Set a slot number if not defined (this is essentially mandatory or the guns will not work correctly)
    if actor.weapon.slotnumber == -1
      #slot number is not defined so lets check ammo type
      if actor.weapon.ammotype == "UNDEFINED" && actor.weapon.ammotype1 == "UNDEFINED" && actor.weapon.ammotype2 == "UNDEFINED"
        puts "#{actor.source_file}:#{actor.name} is a weapon with both no slot number and no ammo type. It's not a weapon."
        actordb[actor_index].is_weapon = false
      else
        # parse out ammotype if there are quotation marks
        weapon_ammo_type = "UNDEFINED"
        weapon_ammo_type1 = "UNDEFINED"
        weapon_ammo_type2 = "UNDEFINED"
        if actor.weapon.ammotype =~ /\"/
          weapon_ammo_type = actor.weapon.ammotype.gsub(/\"/, "").downcase
        else
          weapon_ammo_type = actor.weapon.ammotype.to_s.downcase
        end
        if actor.weapon.ammotype1 =~ /\"/
          weapon_ammo_type1 = actor.weapon.ammotype1.gsub(/\"/, "").downcase
        else
          weapon_ammo_type1 = actor.weapon.ammotype1.to_s.downcase
        end
        if actor.weapon.ammotype2 =~ /\"/
          weapon_ammo_type2 = actor.weapon.ammotype2.gsub(/\"/, "").downcase
        else
          weapon_ammo_type2 = actor.weapon.ammotype2.to_s.downcase
        end

        # we already checked to make sure at least one value was populated
        # so now we just need to establish precidence
        # priority: 1) ammotype 2) ammotype1 3) ammotype
        if weapon_ammo_type == "UNDEFINED" || weapon_ammo_type == "undefined"
          if weapon_ammo_type1 != "UNDEFINED" && weapon_ammo_type1 != "undefined"
            weapon_ammo_type = weapon_ammo_type1.gsub(/\"/, "")
          else
            weapon_ammo_type = weapon_ammo_type2.gsub(/\"/, "")
          end
        end

        # set weapon slot based on ammo type
        if weapon_ammo_type == "clip"
          #set to slot 2 if wimpy weapon, otherwise it gets slot 4
          if actor.weapon.wimpy_weapon == true
            actordb[actor_index].weapon.slotnumber = 2
          else
            actordb[actor_index].weapon.slotnumber = 4
          end
        elsif weapon_ammo_type == "shell"
          actordb[actor_index].weapon.slotnumber = 3
        elsif weapon_ammo_type == "rocketammo"
          actordb[actor_index].weapon.slotnumber = 5
        elsif weapon_ammo_type == "cell"
          if actor.weapon.bfg == true
            actordb[actor_index].weapon.slotnumber = 7
          else
            actordb[actor_index].weapon.slotnumber = 6
          end
        else
          # slot number 8 will be an "unknown weapon bucket"
          actordb[actor_index].weapon.slotnumber = 8
        end

        puts "Actor Ammo Type: #{actor.weapon.ammotype} -> #{weapon_ammo_type}"
        puts "Actor Ammo Type1: #{actor.weapon.ammotype1} -> #{weapon_ammo_type1}"
        puts "Actor Ammo Type2: #{actor.weapon.ammotype2} -> #{weapon_ammo_type2}"
        puts "Updating #{actor.source_file}:#{actor.name}: New slot number: #{actordb[actor_index].weapon.slotnumber}"

        # Edit the file and make the insertion
        if script_type[actor.file_path] == "DECORATE"
          file_text = File.read(actor.file_path)
          found_actor_line = -1
          found_open_curly = -1
          file_text_lines = file_text.lines
          file_text_lines.each_with_index do |line, line_index|
            if found_actor_line == -1 && line =~ /^\s*actor\s+#{actor.name}[:|\s]/i
              puts "Actor Line found: #{line_index}"
              puts "Line: #{line}"
              found_actor_line = line_index
            end
            if found_actor_line != -1 && found_open_curly == -1 && line =~ /\{/
              puts "Found Open Curly: #{line_index}"
              puts "Line: #{line}"
              found_open_curly = line_index
              break
            end
          end
          found_open_curly = found_open_curly + 1
          puts "Found Open Curly + 1: #{found_open_curly}"
          insert_line = "  Weapon.SlotNumber #{actordb[actor_index].weapon.slotnumber}"
          puts "Insert Line: #{insert_line}"
          file_text_lines.insert(found_open_curly, insert_line)
          file_text = file_text_lines.join("\n")
          File.write(actor.file_path, file_text)
        elsif script_type[actor.file_path] == "ZSCRIPT"
          file_text = File.read(actor.file_path)
          found_actor_line = -1
          found_actor_open_curly = -1
          found_default_line = -1
          found_default_open_curly = -1
          file_text_lines = file_text.lines
          file_text_lines.each_with_index do |line, line_index|
            if found_actor_line == -1 && line =~ /^\s*class\s+#{actor.name}\s+/i
              puts "Actor Line found: #{line_index}"
              puts "Line: #{line}"
              found_actor_line = line_index
            end
            if found_actor_line != -1 && found_actor_open_curly == -1 && line =~ /\{/
              puts "Found Actor Open Curly: #{line_index}"
              puts "Line: #{line}"
              found_actor_open_curly = line_index
            end
            if found_actor_open_curly != -1 && found_default_line == -1 && line =~ /^\s*default/i
              puts "Found Default Section: #{line_index}"
              puts "Line: #{line}"
              found_default_line = line_index
            end
            if found_default_line != -1 && found_default_open_curly == -1 && line =~ /\{/
              puts "Found Default Open Curly: #{line_index}"
              puts "Line: #{line}"
              found_default_open_curly = line_index
              break
            end
          end
          puts "Found Default Open Curly: #{found_default_open_curly}"
          found_default_open_curly = found_default_open_curly + 1
          puts "Inserting at #{found_default_open_curly}"
          insert_line = "  Weapon.SlotNumber #{actordb[actor_index].weapon.slotnumber};"
          puts "Insert Line: #{insert_line}"
          file_text_lines = file_text_lines.insert(found_default_open_curly, insert_line)
          file_text = file_text_lines.join("\n")
          File.write(actor.file_path, file_text)
        end        
      end
    end
  end
end

# Evaluate Inheritance for Ammo and Pickups
inheritance = Hash(String, String).new
actordb.each_with_index do |actor, actor_index|
  if actor.inherits != "UNDEFINED"
    puts "Actor #{actor.name} inherits #{actor.inherits}"
    inheritance[actor.name] = actor.inherits
  end
end
actordb.each_with_index do |actor, actor_index|
  inheritance_list = Array(String).new
  puts "Actor: #{actor.name}"
  inheritance_list << actor.name
  iteration_name = actor.inherits
  while inheritance.has_key?(iteration_name) == true
    puts " - Inherits: #{iteration_name}"
    inheritance_list << iteration_name
    iteration_name = inheritance[iteration_name]
  end
  puts "Inheritance List:"
  puts inheritance_list.inspect
  if inheritance_list.includes?("ammo")
    puts "Ammo Item!"
    actordb[actor_index].is_ammo = true
  elsif inheritance_list.includes?("healthpickup")
    puts "Health Item!"
    actordb[actor_index].is_health = true
  elsif inheritance_list.includes?("armor")
    puts "Armor Item!"
    actordb[actor_index].is_armor = true
  elsif inheritance_list.includes?("backpackitem")
    puts "Backpack Item!"
    actordb[actor_index].is_backpackitem = true
  elsif inheritance_list.includes?("health")
    puts "Health Item!"
    actordb[actor_index].is_health = true
  elsif inheritance_list.includes?("powerup")
    puts "Powerup Item!"
    actordb[actor_index].is_powerup = true
  end 
end

puts "Ammo items:"
actordb.each do |actor|
  if actor.is_ammo == true
    puts " - #{actor.name}"
  end
end

#  shell_box =
#  {
#    id = 2049,
#    kind = "ammo",
#    rank = 2,
#    add_prob = 40,
#    give = { {ammo="shell",count=20} },
#  },

# we need to evaluate inheritance specifically as far as monsters are concerned
actordb.each_with_index do |actor, actor_index|
  next if actor.built_in == true

  is_monster = false
  if actor.monster == true || actor.ismonster == true
    puts "Actor is a confirmed monster, no need to evaluate inheritance"
    is_monster = true
  else
    puts "Evaluating Inheritance For #{actor.name_with_case}"
    inheritance = Array(String).new
    inheritance << actor.name
    inherits_name = actor.inherits
    puts "Actor.inherits: #{inherits_name}"
    while inherits_name != "UNDEFINED"
      break if inherits_name == "UNDEFINED"
      break if inherits_name == "actor"
      break if inherits_name == "object"
      break if inherits_name == "thinker"
      break if inherits_name == "eventhandler"
      actordb.each_with_index do |actor_check, actor_check_index|
        if inherits_name == actor_check.name
          puts " - Inherits: #{inherits_name} -> #{actor_check.inherits}"
          inheritance << actor_check.name
          inherits_name = actor_check.inherits
          break
        end
      end
    end
    # we go reverse order from end of the inheritance to beginning
    # e.g. Blah : Blah2, Blah2 : Blah3, Blah3 <no inheritance on Blah3>
    # we start with Blah3, check properties and then go to Blah2, and then Blah
    inheritance.reverse!
    is_monster = false
    inheritance.each do |inherited_actor|
      actordb.each do |actor_check|
        if actor_check.name == inherited_actor
          puts "Inherited Actor: #{inherited_actor}"
          #skip_super means inherit only states, not properties/flags AFAIK
          #so we reset to false
          if actor_check.skip_super == true
            puts "SKIP SUPER! Reset any flags!"
            is_monster = false
          end
          #Check for Monster property or +ISMONSTER flag
          if actor_check.monster == true || actor_check.ismonster == true
            puts "IS MONSTER! (monster: #{actor_check.monster} ismonster: #{actor_check.ismonster})"
            is_monster = true
          #for "false" values we also need to check flags_applied array
          #because default value is "false" but it may override "monster" in rare cases
          #I don't think the "monster" property can be false, it's true if present
          else
            actor_check.flags_applied.each do |flag|
              if flag == "-ismonster"
                puts "Actor: #{actor_check.name}, Flag -ismonster"
                is_monster = false
              elsif flag == "+ismonster"
                puts "Actor: #{actor_check.name}, Flag +ismonster"
                is_monster = true
              end
            end
          end
        end
      end
    end
  end
  #after all of that, if is_monster == true, then we have us a monster
  #we will set this property for future reference
  if is_monster == true
    puts "Actor #{actor.name_with_case} is a Monster!"
    actordb[actor_index].ismonster = true
    actordb[actor_index].monster = true
  else
    puts "Actor #{actor.name_with_case} is NOT a Monster."
    actordb[actor_index].ismonster = false
    actordb[actor_index].monster = false
    actordb[actor_index].doomednum = -1
  end
end

actor_count = 0
monster_count = 0
built_in_count = 0
id_non_monster = 0
actordb.each do |actor|
  if actor.ismonster == true || actor.monster == true
    puts "Actor #{actor.name_with_case} is a monster!"
    monster_count += 1
    if actor.built_in == true
      built_in_count += 1
    end
  elsif actor.doomednum != -1
    puts "Actor #{actor.name_with_case} has ID #{actor.doomednum} but is not a monster"
    id_non_monster += 1
  end
  actor_count += 1
end
puts "Total Actors: #{actor_count}"
puts "Total Monsters: #{monster_count}"
puts "  - Built In: #{built_in_count}"
puts "ID'd non-monsters: #{id_non_monster}"

# wipe all doomednums from the Processing directory
# wipe all replaces as well
actordb.each do |actor|
  if (actor.built_in != true)
    puts "-------------------------------------------------------------------"
    puts "Actor: #{actor.name_with_case}"
    puts "File: #{actor.file_path}"
    file_text = File.read(actor.file_path)
    lines = file_text.lines
    lines.each_with_index do |line, line_index|
      if line =~ /^\s*actor\s+/i
        #insert line break before curly braces
        modified_line = line.gsub("{", "\n{")
        lines[line_index] = modified_line
      end
    end
    file_text = lines.join("\n")
    lines = file_text.lines
    lines.each_with_index do |line, line_index|
      if line =~ /^\s*actor\s+/i
        # ensure that comments, and colons have a space in front
        line = line.gsub("//", " //")
        line = line.gsub(":", " :")
        # make sure any newly doubled spaces go away with a quick split and join
        line = line.split.join(" ")

        puts "actor_line: #{line}"

        delete_word = -1

        # remove doomednums
        words = line.split
        words.each_with_index do |word, word_index|
          puts "  word: #{word}"
          if word =~ /^{/
            puts "   Fatal Error: Word detected that starts with { or /"
            puts "   Line: #{line}"
            puts "   Words: #{words}"
            exit(1)
            break
          end
          if word =~ /^\/\//
            puts "   Comment detected"
            break
          end
          if word.to_i? != nil
            puts "  Number detected"
            delete_word = word_index
            break
          end
        end
        if delete_word != -1
          puts "Deleting Word: #{words[delete_word]}"
          words.delete_at(delete_word)
        end
        lines[line_index] = words.join(" ")

        delete_word = -1
        words = lines[line_index].split
        words.each_with_index do |word, word_index|
          puts "  word: #{word}"
          if word =~ /^{/ || word =~ /^\//
            puts "   Word detected that starts with { or /"
            break
          end
          if word =~ /replaces/i
            puts "  Replaces detected"
            delete_word = word_index
            break
          end
        end
        if delete_word != -1
          puts "Deleting Replace: #{words[delete_word]} #{words[delete_word + 1]}"
          words.delete_at(delete_word)
          words.delete_at(delete_word)
          puts "Words: #{words}"
        end
        lines[line_index] = words.join(" ")


        puts "Writing Line: #{lines[line_index]}"
        puts "---------------------"
      end
    end
    puts "Writing file: #{actor.file_path}"
    file_text = lines.join("\n")
    File.write(actor.file_path, file_text)
  end
end

# Wipe any DoomEdNums from the MAPINFO files
# looks for any 'doomednums {<code_here>}' section in MAPINFO and deletes it
# case insensitive (i)
puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
puts "@  WIPING DOOMEDNUMS           @"
puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
puts ""
mapinfo_files_pk3 = Dir.glob(".#{fs}Processing_PK3#{fs}*#{fs}MAPINFO*")
mapinfo_files_wad = Dir.glob(".#{fs}Processing#{fs}*#{fs}MAPINFO")
puts "MAPINFO in PK3 files:"
puts ""
mapinfo_files_pk3.each do |mapinfo_file|
  mapinfo_file_text = File.read(mapinfo_file)
  mapinfo_file_text = mapinfo_file_text.gsub(/doomednums\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi, "")
  File.write(mapinfo_file, mapinfo_file_text)
end
puts "MAPINFO in WAD files:"
puts ""
mapinfo_files_wad.each do |mapinfo_file|
  mapinfo_file_text = File.read(mapinfo_file)
  mapinfo_file_text = mapinfo_file_text.gsub(/doomednums\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi, "")
  File.write(mapinfo_file, mapinfo_file_text)
end
# gsub(/doomednums\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi, "")

# assign doomednums to all monster actors (& weapons) (& ammo)
doomednum_counter = 15000
actordb.each_with_index do |actor, actor_index|
  if script_type[actor.file_path] == "DECORATE"
    if (actor.built_in != true) && (actor.ismonster == true || actor.monster == true || actor.is_weapon == true || actor.is_ammo == true)
      file_text = File.read(actor.file_path)
      lines = file_text.lines
      lines.each_with_index do |line, line_index|
        if line =~ /^\s*actor\s+/i
          #make sure any comments have a space in front
          line = line.gsub("//", " //")
          #make sure colons have space around them
          line = line.gsub(":", " : ")
          words = line.lstrip.split
          next if words[1].downcase != actor.name_with_case.downcase
          puts "Assignable Actor found (#{actor.name_with_case}): #{line}"
          # set to size minus 1
          early_end_index = words.size
          words.each_with_index do |word, word_index|
            if word == "{" || word =~ /\//
              early_end_index = word_index
            end
          end
          puts "Incrementing doomednum..."
          while true
            break if doomednum_info.fetch(doomednum_counter, nil) == nil
            doomednum_counter += 1
          end
          words.insert((early_end_index), doomednum_counter.to_s)
          doomednum_info[doomednum_counter] = {-1, -1}
          actordb[actor_index].doomednum = doomednum_counter
          lines[line_index] = words.join(" ")
          puts "Modified line: #{lines[line_index]}"
        end
      end
      file_text = lines.join("\n")
      File.write(actor.file_path, file_text)
    else
      #the actor is not a monster/weapon, so it will not be assigned a doomednum, and we will wipe it to -1 in the database
      actordb[actor_index].doomednum = -1
    end
  elsif script_type[actor.file_path] == "ZSCRIPT"
    next if actor.built_in == true
    next if actor.ismonster == false && actor.monster == false && actor.is_weapon == false && actor.is_ammo == false
    # determine if a MAPINFO file exists, and create if not
    if actor.file_path.split("#{fs}")[1] == "Processing_PK3"
      mapinfo_file = actor.file_path.split("#{fs}")[0..2].join("#{fs}") + "#{fs}MAPINFO"
    else
      mapinfo_file = actor.file_path.split("#{fs}")[0..2].join("#{fs}") + "#{fs}defs#{fs}MAPINFO.raw"
    end
    if File.file?(mapinfo_file) == false
      File.open(mapinfo_file, "w") do |file|
        # just write a blank file and do nothing else
      end
    end

    # determine if a DoomEdNums section exits, and create if not
    mapinfo_file_text = File.read(mapinfo_file)
    if mapinfo_file_text.match(/doomednums\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi) == nil
      mapinfo_file_text = mapinfo_file_text + "\nDoomEdNums\n{\n\n}"
    end

    # Increment DoomEdNums counter to next available
    while true
      break if doomednum_info.fetch(doomednum_counter, nil) == nil
      doomednum_counter += 1
    end
    doomednum_info[doomednum_counter] = {-1, -1}

    # add doomednum to actordb
    actordb[actor_index].doomednum = doomednum_counter

    # insert new doomednum by replacing..
    # before:
    # DoomEdNums
    # {
    #
    # after:
    # DoomEdNums
    # {
    #   <id> = <actor_name>
    mapinfo_file_text = mapinfo_file_text.gsub(/^\h*doomednums\s*\{/mi, "DoomEdNums\n{\n  #{doomednum_counter} = #{actor.name_with_case}")

    # write file
    File.write(mapinfo_file, mapinfo_file_text)
  elsif script_type[actor.file_path] == "BUILT_IN"
    next
  end
end

#################################################################
# delete duplicate sprites                                      #
#################################################################
# sprites must be named identically and have identical contents #
#################################################################
sprites_files = Dir.glob(".#{fs_os}Processing#{fs_os}*#{fs_os}sprites#{fs_os}*")
sprites_pk3 = Dir.glob(".#{fs_os}Processing_PK3#{fs_os}**#{fs_os}*").select { |entry| entry =~ /sprites/i }
sprites_files = sprites_files + sprites_pk3
sprites_files = sprites_files + Dir.glob(".#{fs_os}IWADs_Extracted#{fs_os}*#{fs_os}sprites#{fs_os}*")


sprites_files.each do |sprite|
  if sprite =~ /acbwaoeuaoeuaoeu/i
    puts "Sprite: #{sprite}"
    #STDIN.gets
  end
end

#sprites_by_name = sprites_files
#  .group_by { |sprite| sprite.split("/").last }
#  .select { |_, sprites| sprites.size > 1 }

sprites_by_sha = sprites_files
  .select { |sprite| File.file?(sprite) }
  .group_by { |sprite| Digest::SHA256.new.file(sprite).hexfinal }
  .select { |_, sprites| sprites.size > 1 }
  .transform_values { |sprites| sprites.sort }

#sprites_by_sha.each do |key, sprite|
#  puts "Sprite: #{key}"
#  file_index = 0
#  sprite[key].each do |file|
#    next if sprite.split("/")[1] == "IWADs_Extracted"
#    puts "Sprite: #{sprite}"
#    file_index += 1
#  end
#end

sprites_by_sha.each do |key, sprites|
  unique_sprites = Hash(String, String).new
  puts "SHA Hash: #{key}"
  sprites.each do |sprite|
    if unique_sprites.fetch(sprite.split("#{fs_os}").last, nil) == nil || sprite.split("#{fs_os}")[1] == "IWADs_Extracted"
      puts "  - Original: #{sprite}"
      unique_sprites[sprite.split("#{fs_os}").last] = sprite
    elsif sprite.split("#{fs_os}")[1] != "IWADs_Extracted"
      puts "  - Duplicate: #{sprite}"
      puts "    - Deleting!"
      #File.delete(sprite)
    else
      # We can't really delete duplicate IWAD sprites for hopefully obvious reasons
      puts "  - IWAD Sprite: #{sprite}"
    end
  end
end

# wad1 -> BLAH, BORK, FOOD
# wad2 -> BLAH, BLA3, BOOP
# sprite_prefix["BOOP"] = [{"./Processing/monsters/sprites/BOOPA1.raw", "sha_hash_text..."}]

# after deleting the dupes, we need to rebuild the list
sprite_prefix = Hash(String, Array(Tuple(String, String))).new
sprites_files = Dir.glob(".#{fs_os}Processing#{fs_os}*#{fs_os}sprites#{fs_os}*")
sprites_pk3 = Dir.glob(".#{fs_os}Processing_PK3#{fs_os}**#{fs_os}*").select { |entry| entry =~ /sprites/i }
sprites_files = sprites_files + sprites_pk3
sprites_files = sprites_files + Dir.glob(".#{fs_os}IWADs_Extracted#{fs_os}*#{fs_os}sprites#{fs_os}*")

# this is a bad "each" name, I'll have to fix it later...
sprites_files.each do |directory|
  next if File.file?(directory) == false
  # hash key is the first 4 characters
  # grab filename (last field in split), grab filename without extension, take first 4 chars, and ensure upper case
  key = directory.split("#{fs_os}").last.split(".").first[0..3].upcase

  # grab the filename sha
  sha = Digest::SHA256.new.file(directory).hexfinal

  # initialize if nil
  if sprite_prefix.fetch(key, nil) == nil
    sprite_prefix[key] = Array(Tuple(String, String)).new
  end
  sprite_prefix[key] << {directory, sha}
end

puts sprite_prefix.inspect
#puts "waiting..."
#gets

# This function should safely increment to the next available prefix
def increment_prefix(original_string : String, sprite_prefix : Hash(String, Array(Tuple(String, String)))) : String
  puts "Increment Prefix: #{original_string}"
  original_string_modified = original_string.succ
  puts "Modified Prefix: #{original_string_modified}"
  while sprite_prefix.has_key?(original_string_modified)
    puts "Modified Prefix #{original_string_modified} is taken by #{sprite_prefix[original_string_modified][0]}, trying next..."
    original_string_modified = original_string_modified.succ
    #error protection, check for numbers or 5 char prefixes
    if original_string_modified.size > 4
      puts "Fatal Error: prefix \"#{original_string_modified}\" is larger than 4 characters"
      exit(1)
    end
  end
  puts "Found Available Prefix: #{original_string_modified}"
  return original_string_modified
end

sprite_prefix.each do |key, prefix|
  puts "Prefix: #{key}"

  # Determine if a dupe prefix even exists
  dupe_exists = false
  dupe_name = "UNDEFINED"
  prefix.each_with_index do |pfix, pfix_index|
    if pfix_index == 0
      dupe_name = pfix[0].split("#{fs_os}")[2]
      next
    end
    if dupe_name != pfix[0].split("#{fs_os}")[2]
      dupe_exists = true
      break
    end
  end

  # stop burning CPU for this prefix if no dupes
  if dupe_exists == false
    puts "NO DUPES"
    next
  else
    puts "DUPE EXISTS"
  end

  # Create the array to hold the list of wads that use this prefix
  # this is necessary, because there may be more than one wad in conflict
  # format is: wad name, prefix name
  # e.g. NewCacodemon, HEAD
  wads_with_prefix = Hash(String, String).new

  # Step 1) determine if an IWAD file has the prefix
  iwad_has_prefix = false
  original_wad_prefix = "UNDEFINED"
  prefix.each do |pfix|
    if pfix[0].split("#{fs_os}")[1] == "IWADs_Extracted"
      puts "IWAD Matched: #{pfix[0]}"
      iwad_has_prefix = true
      # we are going to take the first 3 fields
      # ./Processing/<wadname>
      # ./Processing_PK3/<pk3name>
      original_wad_prefix = pfix[0].split("#{fs_os}")[0..2].join("#{fs_os}")
      wads_with_prefix[original_wad_prefix] = key
      break
    end
  end

  # Set wad prefix to first in list if undefined
  if original_wad_prefix == "UNDEFINED"
    original_wad_prefix = prefix[0][0].split("#{fs_os}")[0..2].join("#{fs_os}")
    wads_with_prefix[original_wad_prefix] = key
  end

  # Increment the string to next value
  prefix_counter = increment_prefix(key, sprite_prefix)

  # Step 2) build list of wads_with_prefix and assign new prefixes as needed
  prefix.each do |pfix|
    if wads_with_prefix.fetch(pfix[0].split("#{fs_os}")[0..2].join("#{fs_os}"), nil) == nil
      wads_with_prefix[pfix[0].split("#{fs_os}")[0..2].join("#{fs_os}")] = prefix_counter
      sprite_prefix[prefix_counter] = Array(Tuple(String, String)).new
      sprite_prefix[prefix_counter] << pfix
      prefix_counter = increment_prefix(prefix_counter, sprite_prefix)
    end
  end

  puts "wads_with_prefix:"
  puts wads_with_prefix.inspect
  #puts "waiting..."
  #gets

  # rename the files
  wads_with_prefix.each_with_index do |wad_prefix, index|
    # skip the first entry which is the original
    next if index == 0
    if wad_prefix[0].split("#{fs_os}")[1] == "Processing"
      list_of_sprites = Dir.glob(".#{fs_os}#{wad_prefix[0]}#{fs_os}sprites#{fs_os}#{key}*")
    elsif wad_prefix[0].split("#{fs_os}")[1] == "Processing_PK3"
      list_of_sprites = Dir.glob(".#{fs_os}#{wad_prefix[0]}#{fs_os}**#{fs_os}*").select { |entry| entry =~ /sprites/i && entry =~ /#{key}/i }
    else
      # compiler necessitates this "else" I think
      next
    end
    puts "Sprites in #{wad_prefix[0]}:"
    list_of_sprites.each_with_index do |sprite, sprite_index|
      updated_sprite = Path.posix(sprite).normalize.to_s
      list_of_sprites[sprite_index] = ".#{fs}" + updated_sprite
    end
    puts list_of_sprites.inspect
    puts "Renaming..."
    list_of_sprites.each do |sprite|
      next if File.directory?(sprite)
      # Below is a bad choice, and I'm doing it differently... folders were getting renamed
      #
      # prefix[1] should hold the new prefix which we will rename with
      # regex looks for /BLAH and replaces with /BLA2
      # new_path = sprite.gsub(/#{fs_os}#{key}/, "/#{wad_prefix[1]}")
      #
      new_file = sprite.split("#{fs_os}").last
      # we take wad prefix[1] which is the new 4 character prefix
      # and tack on the remaining characters of the original filename starting with the 5th char (4)
      new_file_renamed = wad_prefix[1] + new_file[4..-1]
      new_path = sprite.split("#{fs_os}")[0..-2].join("#{fs_os}") + fs_os + new_file_renamed
      if new_path != sprite
        puts "Renaming: #{sprite} -> #{new_path}"
        File.rename(sprite, new_path)
      end
    end

    puts "wad_refix: #{wad_prefix}"
    puts "prefix: #{prefix}"
    puts "key: #{key}"
    puts "prefix_counter: #{prefix_counter}"

    # Troubleshooting a prefix is made easier by this code...
    #if key == "MUZZ"
    #  puts "hit enter..."
    #  gets
    #end
  end

  # rename the animations in decorate or zscript
  wads_with_prefix.each_with_index do |prefix, index|
    # skip the first entry which is the original
    next if index == 0
    # build list of wad file DECORATE and ZSCRIPT, and then pk3 version
    if prefix[0].split("#{fs}")[1] == "Processing"
      list_of_decorate = Dir.glob("#{prefix[0]}#{fs_os}defs#{fs_os}DECORATE.raw")
      list_of_zscript = Dir.glob("#{prefix[0]}#{fs_os}defs#{fs_os}ZSCRIPT.raw")
    elsif prefix[0].split("#{fs}")[1] == "Processing_PK3"
      list_of_decorate = Dir.glob("#{prefix[0]}#{fs_os}DECORATE*")
      list_of_zscript = Dir.glob("#{prefix[0]}#{fs_os}ZSCRIPT*")
    else
      # compiler necessitates this "else" I think
    end
    # populate includes
    if list_of_decorate.nil?
      puts "list_of_decorate is nil"
    else
      list_of_decorate.each_with_index do |decorate, decorate_index|
        puts "Decorate: #{decorate}"
        # since Doom DECORATE is CASE INSENSITIVE we have to search and compare to find the actual file name
        file_search_term = "#{decorate.split("/")[0..1].join("/")}/**/*"
        puts "file_search_term: #{file_search_term}"
        file_search = Dir.glob("#{file_search_term}")
        file_match = "UNDEFINED"
        file_search.each do |searchfile|
          # this takes up a lot of time, but might be nice for troubleshooting
          #puts "searching: #{decorate.downcase} == #{searchfile.downcase}"
          if decorate.downcase == searchfile.downcase
            file_match = searchfile
            list_of_decorate[decorate_index] = file_match
            break
          end
        end
        if file_match == "UNDEFINED"
          puts "Fatal Error: file not found: #{decorate}"
          exit(1)
        end

        decorate_text = File.read(file_match)
        decorate_text.each_line do |decorate_line|
          puts "Decorate Line: #{decorate_line}"
          if decorate_line =~ /^\s*\#include\s+/i
            include_file = "UNDEFINED"
            if decorate_line =~ /\"/
              include_file = decorate_line.split('"')[1]
            else
              include_file = decorate_line.split[1]
            end
            if prefix[0].split("#{fs_os}")[1] == "Processing"
              list_of_decorate << "#{prefix[0]}#{fs_os}defs#{fs_os}#{include_file.upcase}.raw"
            elsif prefix[0].split("#{fs_os}")[1] == "Processing_PK3"
              # normalize path
              decorate_path_normalized = Path["#{prefix[0]}#{fs_os}#{include_file}"].normalize.to_s
              list_of_decorate << "#{decorate_path_normalized}"
            end
          end
        end
      end
      list_of_decorate.each do |decorate|
        puts "Checking file #{decorate}..."
        decorate_text = File.read(decorate)
        decorate_text_lines = decorate_text.lines
        decorate_text_lines.each_with_index do |decorate_line, decorate_line_index|
          if decorate_line =~ /^\s*#{key}\s+/i
            puts "Matched line..: #{decorate_line}"
            decorate_text_lines[decorate_line_index] = decorate_line.sub(key, prefix[1])
            puts "Corrected line: #{decorate_text_lines[decorate_line_index]}"
          end
          if ( decorate_line =~ /^\s*inventory.icon/i ||
               decorate_line =~ /^\s*inventory.althudicon/i ||
               decorate_line =~ /^\s*player.crouchsprite/i ||
               decorate_line =~ /^\s*player.scoreicon/i ) &&
             decorate_line =~ /#{key}/i
            puts "Matched line..: #{decorate_line}"
            value = decorate_line.split[1]
            value_renamed = value.sub(key, prefix[1])
            decorate_text_lines[decorate_line_index] = decorate_line.sub(value, value_renamed)
            puts "Key: #{key}"
            puts "Prefix: #{prefix.inspect}"
            puts "Value: #{value}"
            puts "Value Renamed: #{value}"
            puts "Decorate Text: #{decorate_text_lines[decorate_line_index]}"
          end
          
        end
        decorate_text = decorate_text_lines.join("\n")
        File.write(decorate, decorate_text)
      end
    end

    # next we need to do the exact same thing with zscript files
    if list_of_zscript.nil?
      puts "list_of_zscript is nil"
    else
      list_of_zscript.each do |zscript|
        zscript_text = File.read(zscript)
        zscript_text.each_line do |zscript_line|
          if zscript_line =~ /^\s*\#include\s+/i
            if prefix[0].split("#{fs}")[1] == "Processing"
              list_of_zscript << "#{prefix[0]}#{fs}defs#{fs}#{zscript_line.split("\"")[1].upcase}.raw"
            elsif prefix[0].split("#{fs}")[1] == "Processing_PK3"
              # normalize path
              zscript_path_normalized = Path["#{prefix[0]}#{fs}#{zscript_line.split("\"")[1]}"].normalize.to_s
              list_of_zscript << "#{zscript_path_normalized}"
            end
          end
        end
      end
      list_of_zscript.each do |zscript|
        puts "Checking file #{zscript}..."
        zscript_text = File.read(zscript)
        zscript_text_lines = zscript_text.lines
        zscript_text_lines.each_with_index do |zscript_line, zscript_line_index|
          if zscript_line =~ /^\s*#{key}\s+/i
            puts "Matched line..: #{zscript_line}"
            zscript_text_lines[zscript_line_index] = zscript_line.sub(key, prefix[1])
            puts "Corrected line: #{zscript_text_lines[zscript_line_index]}"
          end
          if ( zscript_line =~ /^\s*inventory.icon/i ||
               zscript_line =~ /^\s*inventory.althudicon/i ||
               zscript_line =~ /^\s*player.crouchsprite/i ||
               zscript_line =~ /^\s*player.scoreicon/i ) &&
               zscript_line =~ /#{key}/i
            puts "Matched line..: #{zscript_line}"
            value = zscript_line.split[1]
            value_renamed = value.sub(key, prefix[1])
            zscript_text_lines[zscript_line_index] = zscript_line.sub(value, value_renamed)
            puts "Key: #{key}"
            puts "Prefix: #{prefix.inspect}"
            puts "Value: #{value}"
            puts "Value Renamed: #{value}"
            puts "Decorate Text: #{zscript_text_lines[zscript_line_index]}"
          end
        end
        zscript_text = zscript_text_lines.join("\n")
        File.write(zscript, zscript_text)
      end
    end

    # TEXTURES lump renaming
    textures_list = Dir.glob(".#{fs}Processing#{fs}*#{fs}defs#{fs}TEXTURES.raw")
    pk3_textures_list = Dir.glob(".#{fs}Processing_PK3#{fs}*#{fs}*")
    pk3_textures_list = pk3_textures_list.select {|file| file.split("#{fs_os}")[3] =~ /textures/i }
    pk3_textures_list = pk3_textures_list.select {|file| File.directory?(file) == false }
    textures_list = textures_list + pk3_textures_list
    textures_list.each do |texture_file|
      puts "Texture File: #{texture_file}"
      puts "Prefix: #{prefix[0]}"
      next if texture_file !~ /#{prefix[0]}/
      file_text = File.read(texture_file)
      file_text_lines = file_text.lines
      file_text_lines.each_with_index do |line, line_index|
        if   line =~ /#{key}/ &&
           ( line =~ /^\s*texture/i ||
             line =~ /^\s*sprite/i ||
             line =~ /^\s*graphic/i ||
             line =~ /^\s*walltexture/i ||
             line =~ /^\s*flat/i ||
             line =~ /^\s*patch/i ||
             line =~ /^\s*graphic/i ||
             line =~ /^\s*sprite/i )
          value = line.split[1]
          replacement_value = value.gsub(key, prefix[1])
          replacement_line = line.gsub(value, replacement_value)
          puts "Replacing / With:"
          puts line
          puts replacement_line
          file_text_lines[line_index] = replacement_line
        end
      end
      file_text = file_text_lines.join("\n")
      File.write(texture_file, file_text)
    end

    # GLDEFS lump renaming
    gldefs_list = Dir.glob(".#{fs}Processing#{fs}*#{fs}defs#{fs}GLDEFS.raw")
    pk3_gldefs_list = Dir.glob(".#{fs}Processing_PK3#{fs}*#{fs}*")
    pk3_gldefs_list = pk3_gldefs_list.select {|file| file.split("#{fs_os}")[3] =~ /gldefs/i }
    pk3_gldefs_list = pk3_gldefs_list.select {|file| File.directory?(file) == false }
    gldefs_list = gldefs_list + pk3_gldefs_list
    gldefs_list.each do |gldefs_file|
      file_text = File.read(gldefs_file)
      file_text_lines = file_text.lines
      file_text_lines.each_with_index do |line, line_index|
        if ( line =~ /^\s*frame/i ) &&
             line =~ /#{key}/
          value = line.split[1]
          replacement_value = value.sub(key, prefix[1])
          replacement_line = line.sub(value, replacement_value)
          file_text_lines[line_index] = replacement_line
        end
      end
      file_text = file_text_lines.join("\n")
      File.write(gldefs_file, file_text)      
    end
  end
end

# Delete "maps" folders - we are not merging maps, those will be generated with Obsidian
map_folders = Dir.glob(".#{fs}Processing#{fs}*#{fs}maps#{fs}")
# we are looking for "maps" in case insensitive
map_folders_pk3 = Dir.glob(".#{fs}Processing_PK3#{fs}*#{fs}*#{fs}").select { |entry|
    entry = entry.split("#{fs_os}").join("#{fs}")
    entry.split("#{fs}")[3] =~ /maps/i
  }
map_folders = map_folders + map_folders_pk3
map_folders.each do |folder|
  FileUtils.rm_r(folder)
end

puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
puts "@ DELETING ANY 'GAME' PROPERTY      @"
puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
# This only affects DECORATE, allegedly...
decorate_files = Dir.glob(".#{fs}Processing#{fs}*#{fs}defs#{fs}DECORATE.raw")
decorate_files_pk3 = Dir.glob(".#{fs}Processing_PK3#{fs}*#{fs}DECORATE")
decorate_files = decorate_files + decorate_files_pk3
all_files = Dir.glob(".#{fs}Processing*#{fs}**#{fs}*")

# rename the directories to use forward slashes
decorate_files.each do |decorate_file|
  decorate_file = decorate_file.split("#{fs_os}").join("#{fs}")
end
# add include files
decorate_files.each do |decorate_file|
  file_text = File.read(decorate_file)
  include_file = "UNDEFINED"
  file_text_lines = file_text.lines
  file_text_lines.each_with_index do |line, line_index|
    if line =~ /^\h*\#include/i
      if line =~ /\"/
        include_file = line.split('"')[1]
      else
        include_file = line.split[1]
      end
      folder_path = decorate_file.split("#{fs}")[0..-2].join("#{fs}")

      include_file_upcase = include_file.upcase
      raw_path = Path.posix(folder_path + "#{fs}" + include_file_upcase + ".raw").normalize.to_s
      raw_path = ".#{fs}" + raw_path
      no_ext_path = Path.posix(folder_path + "#{fs}" + include_file).normalize.to_s
      no_ext_path = ".#{fs}" + no_ext_path

      actual_path = ""
      all_files.each do |real_path|
        puts "Path: #{raw_path} Path: #{no_ext_path} Real: #{real_path}"
        if raw_path.upcase == real_path.upcase
          puts "Path: #{raw_path} Matched: #{real_path}"
          actual_path = real_path
        elsif no_ext_path.upcase == real_path.upcase
          puts "Path: #{no_ext_path} Matched: #{real_path}"
          actual_path = real_path
        end
      end

      if actual_path != ""
        decorate_files << actual_path
      else
        raise "File not found: #{include_file} Path: #{no_ext_path}"
        STDIN.gets
      end

      #include_file_path = Path.posix(folder_path + "#{fs}" + include_file.upcase + ".raw").normalize.to_s
      #decorate_files << include_file_path
    end
  end
end
# delete the lines that start with "game
decorate_files.each do |decorate_file|
  file_text = File.read(decorate_file)
  file_lines = file_text.lines
  file_lines.each_with_index do |file_line, file_line_index|
    if file_line =~ /^\h*game/i
      #puts "line found: #{file_line}"
      #puts "hit enter to continue..."
      #gets

      # note: normally this would mess up the counts, but I don't expect two "game" properties in a row
      # there should only be one "game" per actor
      file_lines.delete_at(file_line_index)
    end
  end
  file_text_modified = file_lines.join("\n")
  File.write(decorate_file, file_text_modified)
end

# Compile the folders back into wads
puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
puts "@ CREATING WADS AGAIN               @"
puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
wad_directories = Dir.glob(".#{fs}Processing#{fs}*#{fs}")
puts wad_directories.sort.inspect
# ./jeutool-linux build ./Completed/Reaper.wad ./Processing/Reaper/
wad_directories.each do |wad_directory|
  # replace any backslashes
  wad_directory = wad_directory.split("#{fs_os}").join("#{fs}")
  puts "wad_directory: #{wad_directory}"
  wad_destination = ".#{fs}Completed#{fs}#{wad_directory.split("#{fs}")[2]}.wad"
  puts "wad_destination: #{wad_destination}"
  system ".#{fs}#{jeutoolexe} build \"#{wad_destination}\" \"#{wad_directory}\" -v"
end

puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
puts "@ CREATING PK3S AGAIN               @"
puts "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
# Compile the pk3 folders back into pk3s
def add_files_to_zip(zip : Compress::Zip::Writer, base_directory : String, directory : String)
  Dir.each_child(directory) do |entry|
    entry_path = directory + "/" + entry
    relative_path = entry_path.sub(base_directory, "").strip

    if File.directory?(entry_path)
      # Recursively add files from subdirectories
      add_files_to_zip(zip, base_directory, entry_path)
    else
      # Read the file contents and add them to the zip archive
      file_contents = File.read(entry_path)
      zip.add(relative_path, file_contents)
    end
  end
end
directories_to_compress = Dir.glob(".#{fs}Processing_PK3#{fs}*")
directories_to_compress.each do |directory|
  directory = directory.split("#{fs_os}").join("#{fs}")
  puts "Directory: #{directory}"
  zip_file = ".#{fs}Completed#{fs}" + directory.split("#{fs}").last + ".pk3"
  puts "Zip File: #{zip_file}"
  Compress::Zip::Writer.open(zip_file) do |zip|
    add_files_to_zip(zip, directory, directory)
  end
end

# Generate the Lua
lua_file  = "------------------------------------------------\n"
lua_file += "--        Monster Mash                        --\n"
lua_file += "------------------------------------------------\n"
lua_file += "\n"
lua_file += "MONSTER_MASH = { }\n"
lua_file += "\n"
lua_file += "MONSTER_MASH.MONSTERS =\n"
lua_file += "{\n"

actordb.each do |actor|
  next if (actor.ismonster == false && actor.monster == false) || actor.doomednum == -1
  lua_file += "  -- Source Wad: #{actor.source_wad_folder}\n"
  lua_file += "  #{actor.name} =\n"
  lua_file += "  {\n"
  lua_file += "    id = #{actor.doomednum},\n"
  lua_file += "    r = #{actor.radius.to_i},\n"
  lua_file += "    h = #{actor.height},\n"
  lua_file += "    prob = 30,\n"
  lua_file += "    health = #{actor.health},\n"
  lua_file += "    damage = 10,\n"
  lua_file += "    attack = \"missile\",\n"
  lua_file += "    density = 0.9\n"
  lua_file += "  },\n"
end
# Close out the section
lua_file += "}\n"


# Generate the Lua for Weapons
lua_file += "MONSTER_MASH.WEAPONS =\n"
lua_file += "{\n"
actordb.each_with_index do |actor, index|
  next if actor.is_weapon == false
  # grab the ammo type value
  actor_ammo_extracted = "UNDEFINED"
  # default is ammotype, second chance is ammotype1 and then ammotype2 (not sure how to implement ammotype2)
  if actor.weapon.ammotype =~ /\"/
    actor_ammo_extracted_pre = actor.weapon.ammotype.split("\"")[1]
    if actor_ammo_extracted_pre != nil
      actor_ammo_extracted = actor_ammo_extracted_pre.sub("\\", "")
    end
  elsif actor.weapon.ammotype != "UNDEFINED"
    actor_ammo_extracted = actor.weapon.ammotype
  elsif actor.weapon.ammotype1 =~ /\"/
    actor_ammo_extracted_pre = actor.weapon.ammotype1.split("\"")[1]
    if actor_ammo_extracted_pre != nil
      actor_ammo_extracted = actor_ammo_extracted_pre.sub("\\", "")
    end
  elsif actor.weapon.ammotype1 != "UNDEFINED"
    actor_ammo_extracted = actor.weapon.ammotype1
  elsif actor.weapon.ammotype2 =~ /\"/
    actor_ammo_extracted_pre = actor.weapon.ammotype2.split("\"")[1]
    if actor_ammo_extracted_pre != nil
      actor_ammo_extracted = actor_ammo_extracted_pre.sub("\\", "")
    end
  elsif actor.weapon.ammotype2 != "UNDEFINED"
    actor_ammo_extracted = actor.weapon.ammotype2
  else
    # if all else fails, we default to "clip"
    actor_ammo_extracted = "clip"
  end
  # downcase it
  actor_ammo_extracted = actor_ammo_extracted.downcase
  # add an underscore if it starts with a number
  number_prefix = ""
  if actor.name_with_case =~ /^\d/
    number_prefix = "_"
  end
  if actor.weapon.ammogive < 1
    ammo_count = 5
  else
    ammo_count = actor.weapon.ammogive
  end

  # do some character replaces if these pop up (might fix these earlier in the process)
  fixed_actor_name = actor.name_with_case.gsub("~", "_")
  fixed_actor_name = fixed_actor_name.gsub(":", "")
  fixed_actor_name = fixed_actor_name.gsub("-", "_")
  lua_file += "  -- Source File: #{actor.source_wad_folder}\n"
  lua_file += "  #{number_prefix}#{fixed_actor_name} =\n"
  lua_file += "  {\n"
  lua_file += "    id = #{actor.doomednum},\n"
  lua_file += "    level = 1,\n"
  lua_file += "    pref = 40,\n"
  lua_file += "    add_prob = 70,\n"
  lua_file += "    attack = \"hitscan\",\n"
  lua_file += "    rate = 0.9,\n"
  lua_file += "    damage = 50,\n"
  lua_file += "    ammo = \"#{actor_ammo_extracted}\",\n"
  lua_file += "    per = 1,\n"
  lua_file += "    give = { { ammo=\"#{actor_ammo_extracted}\", count=#{ammo_count} } }\n"
  lua_file += "  },\n"
end
lua_file += "}\n"

lua_file += "MONSTER_MASH.PICKUPS =\n"
lua_file += "{\n"
actordb.each do |actor|
  next if actor.is_ammo == false
  next if actor.built_in == true
  # add an underscore if it starts with a number
  number_prefix = ""
  if actor.name_with_case =~ /^\d/
    number_prefix = "_"
  end
  # check if there's an inventory amount and if not, count=5
  if actor.inventory.amount != "" && actor.inventory.amount > 0
    inventory_count = actor.inventory.amount
  elsif actor.inventory.amount < 1
    inventory_count = 5
  else
    inventory_count = 5
  end
  lua_file += "  -- Source File: #{actor.source_wad_folder}\n"
  lua_file += "  #{number_prefix}#{actor.name} =\n"
  lua_file += "  {\n"
  lua_file += "    id = #{actor.doomednum},\n"
  lua_file += "    kind = \"ammo\",\n"
  lua_file += "    rank = 2,\n"
  lua_file += "    add_prob = 40,\n"
  lua_file += "    give = { {ammo=\"#{actor.name.downcase}\",count=#{inventory_count} } },\n"
  lua_file += "  },\n"
end
lua_file += "}\n"

lua_file += "OB_MODULES[\"monster_mash\"] =\n"
lua_file += "{\n"
lua_file += "  name = \"monster_mash_control\",\n"
lua_file += "  label = _(\"Monster Mash\"),\n"
lua_file += "  game = \"doomish\",\n"
lua_file += "  port = \"zdoom\",\n"
lua_file += "  tables =\n"
lua_file += "  {\n"
lua_file += "    MONSTER_MASH\n"
lua_file += "  },\n"
lua_file += "  hooks =\n"
lua_file += "  {\n"
lua_file += "    setup = MONSTER_MASH.control_setup\n"
lua_file += "  },\n"
lua_file += "  options =\n"
lua_file += "  {\n"

# Monster controls
actordb.each do |actor|
  next if (actor.ismonster == false && actor.monster == false) || actor.doomednum == -1
  lua_file += "    -- Source File: #{actor.source_wad_folder}\n"
  lua_file += "    {\n"
  lua_file += "      name = \"float_#{actor.name}\",\n"
  lua_file += "      label = _(\"#{actor.name_with_case}\"),\n"
  lua_file += "      valuator = \"slider\",\n"
  lua_file += "      min = 0,\n"
  lua_file += "      max = 20,\n"
  lua_file += "      increment = .02,\n"
  lua_file += "      default = 5.0,\n"
  lua_file += "      nan = 5.0,\n"
  lua_file += "      tooltip = _(\"Control the amount of #{actor.name_with_case}\"),\n"
  lua_file += "      presets = _(\"0:0 (None at all,.02:0.02 (Scarce),.14:0.14 (Less),.5:0.5 (Plenty),1.2:1.2 (More),3:3 (Heaps),20:20 (INSANE)\"),\n"
  lua_file += "      randomize_group = \"monsters\",\n"
  lua_file += "    },\n"
end

# Weapon controls
actordb.each do |actor|
  next if (actor.is_weapon == false) || actor.doomednum == -1
  lua_file += "    -- Source File: #{actor.source_wad_folder}\n"
  lua_file += "    {\n"
  lua_file += "      name = \"float_#{actor.name}\",\n"
  lua_file += "      label = _(\"#{actor.name_with_case}\"),\n"
  lua_file += "      valuator = \"slider\",\n"
  lua_file += "      min = 0,\n"
  lua_file += "      max = 20,\n"
  lua_file += "      increment = .02,\n"
  lua_file += "      default = 5.0,\n"
  lua_file += "      nan = 5.0,\n"
  lua_file += "      tooltip = _(\"Control the amount of #{actor.name_with_case}\"),\n"
  lua_file += "      presets = _(\"0:0 (None at all,.02:0.02 (Scarce),.14:0.14 (Less),.5:0.5 (Plenty),1.2:1.2 (More),3:3 (Heaps),20:20 (INSANE)\"),\n"
  lua_file += "      randomize_group=\"pickups\",\n"
  lua_file += "    },\n"
end

# Ammo controls
actordb.each do |actor|
  next if actor.is_ammo == false
  next if actor.built_in == true
  lua_file += "   -- Source File: #{actor.source_wad_folder}\n"
  lua_file += "   {\n"
  lua_file += "     name = \"float_#{actor.name}\",\n"
  lua_file += "     label = _(\"#{actor.name_with_case}\"),\n"
  lua_file += "     valuator = \"slider\",\n"
  lua_file += "     min = 0,\n"
  lua_file += "     max = 10,\n"
  lua_file += "     increment = .02,\n"
  lua_file += "     default = 5.0,\n"
  lua_file += "     nan = 5.0,\n"
  lua_file += "     tooltip = _(\"Control the amount of #{actor.name_with_case}.\"),\n"
  lua_file += "     presets = _(\"0:0 (None),.02:0.02 (Scarce),.14:0.14 (Less),.5:0.5 (Plenty),1.2:1.2 (More),3:3 (Heaps),10:10 (I LOVE IT)\"),\n"
  lua_file += "     randomize_group=\"pickups\",\n"
  lua_file += "     priority = 75,\n"
  lua_file += "   },\n"
end

lua_file += "  },\n"
lua_file += "}\n"

#output lua script to the screen
puts lua_file

#write the lua file
File.write("..#{fs_os}modules#{fs_os}monster_mash.lua", lua_file)

###########################
# Script FINISHED!!!
###########################
###########################
###########################
# exit cleanly
exit(0)
#
###########################

