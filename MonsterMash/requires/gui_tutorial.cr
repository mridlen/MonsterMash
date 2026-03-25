###############################################################################
# gui_tutorial.cr — GTK4 Tutorial Wizard for Unwad / Monster Mash
#
# Provides a first-run setup wizard using Gtk::Assistant. Shown automatically
# when Source/ or IWADs/ directories are empty (same trigger as CLI tutorial).
#
# Functions:
#   gui_should_show_tutorial? — returns true if first-run conditions are met
#   gui_run_tutorial(app)     — launches the Gtk::Assistant wizard
###############################################################################

require "log"

###############################################################################
# gui_should_show_tutorial? — check if Source/ or IWADs/ is empty
###############################################################################

def gui_should_show_tutorial? : Bool
  # Ensure directories exist before checking contents
  Dir.mkdir_p(SOURCE_DIR)   # pk3_extract.cr
  Dir.mkdir_p(IWADS_DIR)    # pk3_extract.cr

  source_empty = Dir.children(SOURCE_DIR).empty?
  iwads_empty  = Dir.children(IWADS_DIR).reject { |f| f == ".gitkeep" }.empty?

  Log.info { "[gui_tutorial] source_empty=#{source_empty}, iwads_empty=#{iwads_empty}" }

  source_empty || iwads_empty
end

###############################################################################
# gui_run_tutorial — create and present the Gtk::Assistant wizard
###############################################################################

def gui_run_tutorial(app : Gtk::Application)
  Log.info { "[gui_tutorial] Launching tutorial wizard" }

  assistant = Gtk::Assistant.new
  assistant.title = "MonsterMash — First-Time Setup"
  assistant.set_default_size(600, 480)
  assistant.modal = true

  # =========================================================================
  # PAGE 1 — Obsidian Installation Check
  # =========================================================================
  page1_box = Gtk::Box.new(Gtk::Orientation::Vertical, 12)
  page1_box.margin_top = 16
  page1_box.margin_bottom = 16
  page1_box.margin_start = 16
  page1_box.margin_end = 16

  obsidian_path = find_obsidian_exe  # tutorial.cr

  if obsidian_path
    # --- Success: Obsidian found ---
    lbl_ok = Gtk::Label.new("[OK] Found obsidian.exe at:")
    lbl_ok.halign = Gtk::Align::Start
    page1_box.append(lbl_ok)

    lbl_path = Gtk::Label.new(obsidian_path)
    lbl_path.halign = Gtk::Align::Start
    lbl_path.selectable = true
    lbl_path.wrap = true
    page1_box.append(lbl_path)

    lbl_installed = Gtk::Label.new(
      "\nMonsterMash is correctly installed inside your Obsidian folder."
    )
    lbl_installed.halign = Gtk::Align::Start
    lbl_installed.wrap = true
    page1_box.append(lbl_installed)
  else
    # --- Warning: Obsidian not found ---
    lbl_warn = Gtk::Label.new("[WARNING] obsidian.exe was NOT found at the expected location.")
    lbl_warn.halign = Gtk::Align::Start
    lbl_warn.wrap = true
    page1_box.append(lbl_warn)

    lbl_standalone = Gtk::Label.new(
      "\nMonsterMash is running in STANDALONE mode.\n\n" \
      "If you plan to use MonsterMash with Obsidian, the addon must be " \
      "placed inside your Obsidian installation at exactly:\n\n" \
      "  obsidian-<version>\\addons\\MonsterMash\\MonsterMash\\unwad.exe\n\n" \
      "Running standalone is fine for processing WADs/PK3s, but the " \
      "generated monster_mash.lua will need to be copied to Obsidian manually afterwards."
    )
    lbl_standalone.halign = Gtk::Align::Start
    lbl_standalone.wrap = true
    page1_box.append(lbl_standalone)
  end

  # Add page 1 to the assistant
  assistant.append_page(page1_box)
  assistant.set_page_title(page1_box, "Step 1/2 -- Checking for Obsidian Installation")
  assistant.set_page_type(page1_box, Gtk::AssistantPageType::Intro)
  assistant.set_page_complete(page1_box, true)

  # =========================================================================
  # PAGE 2 — File Setup (Source/ and IWADs/ directories)
  # =========================================================================
  page2_box = Gtk::Box.new(Gtk::Orientation::Vertical, 10)
  page2_box.margin_top = 16
  page2_box.margin_bottom = 16
  page2_box.margin_start = 16
  page2_box.margin_end = 16

  # --- Source directory section ---
  lbl_source_header = Gtk::Label.new("SOURCE DIRECTORY (PWADs, mods, custom content)")
  lbl_source_header.halign = Gtk::Align::Start
  page2_box.append(lbl_source_header)

  source_path = File.expand_path(SOURCE_DIR)  # pk3_extract.cr
  lbl_source_path = Gtk::Label.new(source_path)
  lbl_source_path.halign = Gtk::Align::Start
  lbl_source_path.selectable = true
  lbl_source_path.wrap = true
  page2_box.append(lbl_source_path)

  lbl_source_info = Gtk::Label.new(
    "Copy your custom WAD and PK3 files here. These are third-party mods, " \
    "monster packs, and weapon packs -- anything that is NOT a base game file.\n\n" \
    "Supported formats: .wad .pk3 .pk7 .zip .ipk3 .ipk7"
  )
  lbl_source_info.halign = Gtk::Align::Start
  lbl_source_info.wrap = true
  page2_box.append(lbl_source_info)

  btn_open_source = Gtk::Button.new_with_label("Open Source Folder")
  btn_open_source.halign = Gtk::Align::Start
  btn_open_source.clicked_signal.connect { open_folder(SOURCE_DIR) }  # gui.cr
  page2_box.append(btn_open_source)

  # --- Spacer ---
  spacer = Gtk::Label.new("")
  page2_box.append(spacer)

  # --- IWADs directory section ---
  lbl_iwads_header = Gtk::Label.new("IWADs DIRECTORY (base game WADs)")
  lbl_iwads_header.halign = Gtk::Align::Start
  page2_box.append(lbl_iwads_header)

  iwads_path = File.expand_path(IWADS_DIR)  # pk3_extract.cr
  lbl_iwads_path = Gtk::Label.new(iwads_path)
  lbl_iwads_path.halign = Gtk::Align::Start
  lbl_iwads_path.selectable = true
  lbl_iwads_path.wrap = true
  page2_box.append(lbl_iwads_path)

  lbl_iwads_info = Gtk::Label.new(
    "Copy your official id Software IWAD files here. MonsterMash uses " \
    "these to read built-in actor definitions.\n\n" \
    "Supported IWADs: DOOM.WAD, DOOM2.WAD, TNT.WAD, PLUTONIA.WAD,\n" \
    "HERETIC.WAD, HEXEN.WAD, CHEX.WAD"
  )
  lbl_iwads_info.halign = Gtk::Align::Start
  lbl_iwads_info.wrap = true
  page2_box.append(lbl_iwads_info)

  btn_open_iwads = Gtk::Button.new_with_label("Open IWADs Folder")
  btn_open_iwads.halign = Gtk::Align::Start
  btn_open_iwads.clicked_signal.connect { open_folder(IWADS_DIR) }  # gui.cr
  page2_box.append(btn_open_iwads)

  # Add page 2 to the assistant
  assistant.append_page(page2_box)
  assistant.set_page_title(page2_box, "Step 2/2 -- Where To Put Your Files")
  assistant.set_page_type(page2_box, Gtk::AssistantPageType::Confirm)
  assistant.set_page_complete(page2_box, true)

  # =========================================================================
  # CLOSE HANDLING — Cancel, Close, and Apply all dismiss the wizard
  # =========================================================================
  assistant.cancel_signal.connect do
    Log.info { "[gui_tutorial] Wizard cancelled by user" }
    assistant.destroy
  end

  assistant.close_signal.connect do
    Log.info { "[gui_tutorial] Wizard finished by user" }
    assistant.destroy
  end

  assistant.apply_signal.connect do
    Log.info { "[gui_tutorial] Wizard apply triggered" }
    # No action needed — close_signal will fire next
  end

  # =========================================================================
  # PRESENT the wizard
  # =========================================================================
  assistant.present

  Log.info { "[gui_tutorial] Tutorial wizard presented" }
end
