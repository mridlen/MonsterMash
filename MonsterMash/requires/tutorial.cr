###############################################################################
# tutorial.cr — MonsterMash Setup Walkthrough
#
# Invoked when:
#   - unwad.exe is run with the --tutorial flag, OR
#   - The Source/ or IWADs/ directory is empty (first-run detection)
#
# Expected layout:
#   obsidian-<version>\
#     obsidian.exe                   <- 3 levels above unwad.exe
#     addons\
#       MonsterMash\
#         MonsterMash\
#           unwad.exe
###############################################################################

# Check for obsidian.exe exactly 3 parent directories above unwad.exe.
# Returns the full path if found, nil otherwise.
def find_obsidian_exe : String?
  exe_dir = File.dirname(Process.executable_path || ".")
  candidate = File.expand_path(File.join(exe_dir, "..", "..", "..", "obsidian.exe"))
  File.exists?(candidate) ? candidate : nil
end

# Print a prominent banner line
def tutorial_banner(text : String)
  border = "=" * (text.size + 4)
  puts border
  puts "  #{text}"
  puts border
end

# Pause until the user presses a key
def press_any_key
  print "\n  Press any key to continue..."
  STDOUT.flush
  begin
    STDIN.raw { STDIN.read_char }
  rescue
    STDIN.gets   # fallback if raw mode unavailable
  end
  puts ""
end

# Main entry point called from unwad.cr
def run_tutorial
  puts ""
  tutorial_banner("MonsterMash -- First-Time Setup Walkthrough")
  puts ""

  # -- Step 1: Obsidian installation check ----------------------------------

  puts "  Step 1/2 -- Checking for Obsidian installation..."
  puts ""

  obsidian_path = find_obsidian_exe

  if obsidian_path
    puts "  [OK] Found obsidian.exe at:"
    puts "         #{obsidian_path}"
    puts ""
    puts "       MonsterMash is correctly installed inside your Obsidian folder."
  else
    puts "  [WARNING] obsidian.exe was NOT found at the expected location."
    puts ""
    puts "  MonsterMash is running in STANDALONE mode."
    puts ""
    puts "  If you plan to use MonsterMash with Obsidian, the addon must be"
    puts "  placed inside your Obsidian installation at exactly:"
    puts ""
    puts "    obsidian-<version>\\addons\\MonsterMash\\MonsterMash\\unwad.exe"
    puts ""
    puts "  Running standalone is fine for processing WADs/PK3s, but the"
    puts "  generated monster_mash.lua will need to be copied to Obsidian"
    puts "  manually afterwards."
  end

  press_any_key

  # -- Step 2: Source & IWADs directory instructions ------------------------

  puts ""
  tutorial_banner("MonsterMash -- Where To Put Your Files")
  puts ""

  exe_dir     = File.dirname(Process.executable_path || ".")
  source_path = File.expand_path(File.join(exe_dir, "Source"))
  iwads_path  = File.expand_path(File.join(exe_dir, "IWADs"))

  puts "  Step 2/2 -- Populating Source/ and IWADs/"
  puts ""
  puts "  SOURCE DIRECTORY  (PWADs, mods, custom content)"
  puts "  -----------------------------------------------------------------"
  puts "  #{source_path}"
  puts ""
  puts "  Copy your custom WAD and PK3 files here.  These are third-party"
  puts "  mods, monster packs, and weapon packs -- anything that is NOT a"
  puts "  base game file."
  puts ""
  puts "  Supported formats:  .wad  .pk3  .pk7  .zip  .ipk3  .ipk7"
  puts ""
  puts "  Examples:"
  puts "    MyMod.pk3"
  puts "    cool_monster_pack.wad"
  puts ""
  puts ""
  puts "  IWADs DIRECTORY  (base game WADs)"
  puts "  -----------------------------------------------------------------"
  puts "  #{iwads_path}"
  puts ""
  puts "  Copy your official id Software IWAD files here.  MonsterMash"
  puts "  uses these to read built-in actor definitions."
  puts ""
  puts "  Supported IWADs:"
  puts "    DOOM.WAD       (Doom / Ultimate Doom)"
  puts "    DOOM2.WAD      (Doom II)"
  puts "    TNT.WAD        (Final Doom: TNT Evilution)"
  puts "    PLUTONIA.WAD   (Final Doom: The Plutonia Experiment)"
  puts "    HERETIC.WAD"
  puts "    HEXEN.WAD"
  puts "    CHEX.WAD       (Chex Quest)"
  puts ""
  puts "  Once your files are in place, run unwad.exe again -- no flags needed."
  puts ""
  tutorial_banner("Setup complete -- good luck, and rip & tear!")
  puts ""
end
