###############################################################################
# extraction.cr — WAD / PK3 extraction loops for Unwad / Monster Mash
#
# Extracts Source/ mods and IWADs/ into Processing/ and IWADs_Extracted/
# respectively. WAD files use jeutool; PK3/ZIP files use Crystal's ZIP reader.
###############################################################################

WAD_EXTENSIONS  = Set{".wad"}
PK3_EXTENSIONS  = Set{".pk3", ".zip", ".pk7", ".ipk3", ".ipk7"}

# Extract all mod files from Source/ into Processing/
def extract_source_mods(jeutoolexe : String)
  log(2, "Extraction process starting...")

  source_files = Dir.children("./Source").select { |f| File.file?("./Source/#{f}") }
  total_source = source_files.size

  source_files.each_with_index do |file_name, file_index|
    file_path = "./Source/#{file_name}"

    ext = File.extname(file_name).downcase
    base = File.basename(file_name, File.extname(file_name))

    # Progress bar
    print_progress_bar(file_index, total_source, "Extracting #{base}")

    if WAD_EXTENSIONS.includes?(ext)
      puts ""  # Newline before jeutool output
      log(3, "Extracting WAD: #{file_path}")
      system "./#{jeutoolexe} extract \"#{file_path}\" \"./Processing/#{base}\" -r"

    elsif PK3_EXTENSIONS.includes?(ext)
      dest = normalize_path("./Processing/#{base}")
      log(3, "Extracting PK3: #{file_path}")
      extract_pk3(file_path, dest) # requires/pk3_extract.cr

    else
      log(1, "Skipping unknown file type in Source/: #{file_name} (#{ext})")
    end
  end
  puts "" # Clear progress bar
end

# Extract all IWAD files from IWADs/ into IWADs_Extracted/
def extract_iwads(jeutoolexe : String)
  Dir.each_child("./IWADs") do |file_name|
    file_path = "./IWADs/#{file_name}"
    next unless File.file?(file_path)

    ext = File.extname(file_name).downcase
    base = File.basename(file_name, File.extname(file_name))

    if WAD_EXTENSIONS.includes?(ext)
      log(2, "Extracting IWAD WAD: #{file_path}")
      system "./#{jeutoolexe} extract \"#{file_path}\" \"./IWADs_Extracted/#{base}\" -r"

    elsif PK3_EXTENSIONS.includes?(ext)
      dest = normalize_path("./IWADs_Extracted/#{base}")
      log(2, "Extracting IWAD PK3: #{file_path}")
      extract_pk3(file_path, dest) # requires/pk3_extract.cr

    else
      log(1, "Skipping unknown file type in IWADs/: #{file_name} (#{ext})")
    end
  end

  log(2, "Extraction complete.")
end
