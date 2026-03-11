###############################################################################
# extraction.cr — WAD / PK3 extraction loops for Unwad / Monster Mash
#
# Extracts SOURCE_DIR mods and IWADS_DIR into PROCESSING_DIR and IWADS_EXTRACTED_DIR
# respectively. WAD files use jeutool; PK3/ZIP files use Crystal's ZIP reader.
###############################################################################

WAD_EXTENSIONS  = Set{".wad"}
PK3_EXTENSIONS  = Set{".pk3", ".zip", ".pk7", ".ipk3", ".ipk7"}

# ZIP magic bytes: PK\x03\x04
ZIP_MAGIC = Bytes[0x50, 0x4B, 0x03, 0x04]

# Check if a file is actually a ZIP/PK3 regardless of its extension.
# GZDoom doesn't care about extensions — it checks the file header.
# Some .wad files are actually ZIP archives (e.g. Monster.wad).
def file_is_zip?(file_path : String) : Bool
  File.open(file_path, "rb") do |f|
    header = Bytes.new(4)
    bytes_read = f.read(header)
    return bytes_read == 4 && header == ZIP_MAGIC
  end
rescue
  false
end

# After PK3 extraction, find any nested .wad files and extract them with
# jeutool into their own top-level Processing folders. Each nested WAD becomes
# an independent mod folder (e.g. Processing/Monster__Nightmare/) so that
# rename_actor_in_folder only scans its own small defs/ directory, not the
# parent's entire defs/ folder with 200+ files.
def extract_nested_wads(dest_dir : String, jeutoolexe : String)
  nested_wads = Dir.glob("#{dest_dir}/**/*.wad")
    .concat(Dir.glob("#{dest_dir}/**/*.WAD"))
    .select { |p| File.file?(p) }
    .uniq
  return if nested_wads.empty?

  total_nested = nested_wads.size
  parent_name = File.basename(dest_dir)
  log(2, "  Found #{total_nested} nested WAD(s) — extracting with jeutool...")

  nested_wads.each_with_index do |wad_path, wad_index|
    wad_name = File.basename(wad_path, File.extname(wad_path))
    # Progress bar for nested WAD extraction
    print_progress_bar(wad_index, total_nested, "#{parent_name}: nested WAD #{wad_name}")

    # Promote each nested WAD to its own top-level Processing folder.
    # e.g. Processing/Monster__Nightmare/ instead of Processing/Monster/Nightmare_extracted/
    # This keeps each nested WAD's defs/ small so renames are fast.
    promoted_dest = normalize_path(File.join(PROCESSING_DIR, "#{parent_name}__#{wad_name}"))
    log(3, "  Nested WAD: #{wad_path} → #{promoted_dest}")
    system "./#{jeutoolexe} extract \"#{wad_path}\" \"#{promoted_dest}\" -r"
  end
  puts "" # Clear progress bar
  log(2, "  Nested WAD extraction complete: #{total_nested} WAD(s) promoted to Processing/ for #{parent_name}")
end

# Build a mapping of source filenames to unique extraction folder names.
# On Windows, folder names are case-insensitive, so "M16.wad" and "m16.pk3"
# would collide into the same folder. When a collision is detected, append
# the extension to disambiguate (e.g. "M16_wad", "m16_pk3").
def build_extraction_folder_map(source_files : Array(String)) : Hash(String, String)
  folder_map = Hash(String, String).new

  # Group source files by their lowercase base name to detect collisions
  groups = Hash(String, Array(String)).new
  source_files.each do |file_name|
    base = File.basename(file_name, File.extname(file_name))
    key = base.downcase
    groups[key] ||= Array(String).new
    groups[key] << file_name
  end

  groups.each do |_key, files|
    if files.size == 1
      # No collision — use the base name as-is
      file_name = files.first
      base = File.basename(file_name, File.extname(file_name))
      folder_map[file_name] = base
    else
      # Collision — append extension (without dot) to disambiguate
      files.each do |file_name|
        base = File.basename(file_name, File.extname(file_name))
        ext_suffix = File.extname(file_name).lchop('.').downcase
        folder_name = "#{base}_#{ext_suffix}"
        folder_map[file_name] = folder_name
        log(2, "Name collision: #{file_name} → folder #{folder_name}")
      end
    end
  end

  folder_map
end

# Extract all mod files from Source/ into Processing/
def extract_source_mods(jeutoolexe : String)
  log(2, "Extraction process starting...")

  source_files = Dir.children(SOURCE_DIR).select { |f| File.file?("#{SOURCE_DIR}/#{f}") }
  total_source = source_files.size

  # Build folder name map to handle case-insensitive collisions
  folder_map = build_extraction_folder_map(source_files) # extraction.cr

  source_files.each_with_index do |file_name, file_index|
    file_path = "#{SOURCE_DIR}/#{file_name}"

    ext = File.extname(file_name).downcase
    folder_name = folder_map[file_name]

    # Progress bar
    print_progress_bar(file_index, total_source, "Extracting #{folder_name}")

    dest = normalize_path("#{PROCESSING_DIR}/#{folder_name}")

    if WAD_EXTENSIONS.includes?(ext) && file_is_zip?(file_path)
      # Misnamed ZIP — .wad file that's actually a PK3 (e.g. Monster.wad)
      log(2, "#{file_name} is a ZIP despite .wad extension — extracting as PK3")
      extract_pk3(file_path, dest)  # requires/pk3_extract.cr
      extract_nested_wads(dest, jeutoolexe)  # extraction.cr

    elsif WAD_EXTENSIONS.includes?(ext)
      puts ""  # Newline before jeutool output
      log(3, "Extracting WAD: #{file_path} → #{folder_name}")
      system "./#{jeutoolexe} extract \"#{file_path}\" \"#{dest}\" -r"

    elsif PK3_EXTENSIONS.includes?(ext)
      log(3, "Extracting PK3: #{file_path} → #{folder_name}")
      extract_pk3(file_path, dest) # requires/pk3_extract.cr
      extract_nested_wads(dest, jeutoolexe)  # extraction.cr

    else
      log(1, "Skipping unknown file type in #{SOURCE_DIR}: #{file_name} (#{ext})")
    end
  end
  puts "" # Clear progress bar
end

# Extract all IWAD files from IWADs/ into IWADs_Extracted/
def extract_iwads(jeutoolexe : String)
  Dir.each_child(IWADS_DIR) do |file_name|
    file_path = "#{IWADS_DIR}/#{file_name}"
    next unless File.file?(file_path)

    ext = File.extname(file_name).downcase
    base = File.basename(file_name, File.extname(file_name))

    if WAD_EXTENSIONS.includes?(ext)
      log(2, "Extracting IWAD WAD: #{file_path}")
      system "./#{jeutoolexe} extract \"#{file_path}\" \"#{IWADS_EXTRACTED_DIR}/#{base}\" -r"

    elsif PK3_EXTENSIONS.includes?(ext)
      dest = normalize_path("#{IWADS_EXTRACTED_DIR}/#{base}")
      log(2, "Extracting IWAD PK3: #{file_path}")
      extract_pk3(file_path, dest) # requires/pk3_extract.cr

    else
      log(1, "Skipping unknown file type in #{IWADS_DIR}: #{file_name} (#{ext})")
    end
  end

  log(2, "Extraction complete.")
end
