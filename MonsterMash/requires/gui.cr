###############################################################################
# gui.cr — GTK4 GUI for Unwad / Monster Mash
#
# Launches a GTK4 window with slider controls, options, and output display.
# Button handlers wire into run_pipeline() for processing and clean-only modes.
###############################################################################

require "gtk4"

###############################################################################
# HELPER — open_folder: platform-specific file manager launch
###############################################################################

def open_folder(path : String)
  expanded = File.expand_path(path)
  {% if flag?(:win32) %}
    Process.new("explorer", [expanded.gsub("/", "\\")])
  {% elsif flag?(:darwin) %}
    Process.new("open", [expanded])
  {% elsif flag?(:linux) %}
    Process.new("xdg-open", [expanded])
  {% end %}
end

###############################################################################
# HELPER — create a slider row: Label | Scale | Value label
# Returns {scale, value_label} so the caller can capture references.
###############################################################################

def build_slider_row(grid : Gtk::Grid, row : Int32, label_text : String,
                     default_val : Float64, lower : Float64, upper : Float64,
                     step : Float64) : {Gtk::Scale, Gtk::Label}
  # Column 0: descriptive label
  label = Gtk::Label.new(label_text)
  label.halign = Gtk::Align::Start
  label.width_chars = 10
  grid.attach(label, 0, row, 1, 1)

  # Column 1: scale (slider) widget
  adjustment = Gtk::Adjustment.new(default_val, lower, upper, step, step * 10, 0.0)
  scale = Gtk::Scale.new(Gtk::Orientation::Horizontal, adjustment)
  scale.hexpand = true
  scale.draw_value = false
  scale.digits = 2
  grid.attach(scale, 1, row, 1, 1)

  # Column 2: value readout label
  value_label = Gtk::Label.new(format_slider_value(default_val))
  value_label.width_chars = 6
  value_label.halign = Gtk::Align::End
  grid.attach(value_label, 2, row, 1, 1)

  # Update the readout when the slider moves
  adjustment.value_changed_signal.connect do
    value_label.text = format_slider_value(adjustment.value)
  end

  {scale, value_label}
end

###############################################################################
# HELPER — format slider value for display
###############################################################################

def format_slider_value(val : Float64) : String
  sprintf("%.2f", val)
end

###############################################################################
# HELPER — gui_append_output: thread-safe text buffer append with scrollback
###############################################################################

GUI_MAX_SCROLLBACK = 100_000

# Appends a line of text to the GTK text buffer and auto-scrolls to bottom.
# Uses GLib.idle_add to ensure UI updates happen on the main thread.
# Prunes from the top if the buffer exceeds GUI_MAX_SCROLLBACK characters.
def gui_append_output(text_buffer : Gtk::TextBuffer, text_view : Gtk::TextView, line : String)
  GLib.idle_add do
    # Append the line to the buffer
    end_iter = text_buffer.end_iter
    text_buffer.insert(end_iter, line + "\n", -1)

    # Prune from the top if over scrollback limit
    if text_buffer.char_count > GUI_MAX_SCROLLBACK
      start_iter = text_buffer.start_iter
      # Calculate how many chars to remove (trim to 80% of max)
      excess = text_buffer.char_count - (GUI_MAX_SCROLLBACK * 4 // 5)
      trim_iter = text_buffer.iter_at_offset(excess)
      text_buffer.delete(start_iter, trim_iter)
    end

    # Auto-scroll to the bottom
    end_mark = text_buffer.create_mark("scroll_end", text_buffer.end_iter, false)
    text_view.scroll_mark_onscreen(end_mark)
    text_buffer.delete_mark(end_mark)

    false # one-shot: remove from idle queue
  end
end

###############################################################################
# launch_gui — main entry point (called from unwad.cr when ARGV is empty)
###############################################################################

def launch_gui
  app = Gtk::Application.new("com.monstermash.unwad", Gio::ApplicationFlags::None)

  app.activate_signal.connect do
    # =========================================================================
    # WINDOW
    # =========================================================================
    window = Gtk::ApplicationWindow.new(app)
    window.title = "Unwad V2 — Monster Mash WAD Processor"
    window.set_default_size(720, 700)

    # =========================================================================
    # ROOT LAYOUT — vertical box
    # =========================================================================
    root_box = Gtk::Box.new(Gtk::Orientation::Vertical, 8)
    root_box.margin_top = 12
    root_box.margin_bottom = 12
    root_box.margin_start = 12
    root_box.margin_end = 12

    # =========================================================================
    # ROW 1 — Folder buttons
    # =========================================================================
    folder_row = Gtk::Box.new(Gtk::Orientation::Horizontal, 8)

    btn_source = Gtk::Button.new_with_label("Open Source Folder")
    btn_source.clicked_signal.connect { open_folder(SOURCE_DIR) }
    folder_row.append(btn_source)

    btn_iwads = Gtk::Button.new_with_label("Open IWADs Folder")
    btn_iwads.clicked_signal.connect { open_folder(IWADS_DIR) }
    folder_row.append(btn_iwads)

    root_box.append(folder_row)

    # =========================================================================
    # ROW 2 — Slider Defaults frame
    # =========================================================================
    slider_frame = Gtk::Frame.new("Slider Defaults")
    slider_grid = Gtk::Grid.new
    slider_grid.row_spacing = 4
    slider_grid.column_spacing = 8
    slider_grid.margin_top = 8
    slider_grid.margin_bottom = 8
    slider_grid.margin_start = 8
    slider_grid.margin_end = 8

    # Build each slider row and capture references for Task 6
    scale_weapon, lbl_weapon     = build_slider_row(slider_grid, 0, "Weapon:",    0.0,  0.0, 20.0, 0.02)
    scale_monster, lbl_monster   = build_slider_row(slider_grid, 1, "Monster:",   1.0,  0.0, 20.0, 0.02)
    scale_ally, lbl_ally         = build_slider_row(slider_grid, 2, "Ally:",      1.0,  0.0, 20.0, 0.02)
    scale_ammo, lbl_ammo         = build_slider_row(slider_grid, 3, "Ammo:",     10.0,  0.0, 20.0, 0.02)
    scale_nice, lbl_nice         = build_slider_row(slider_grid, 4, "Nice Item:", 0.3,  0.0, 20.0, 0.02)
    scale_pickup, lbl_pickup     = build_slider_row(slider_grid, 5, "Pickup:",    0.3,  0.0, 20.0, 0.02)

    slider_frame.child = slider_grid
    root_box.append(slider_frame)

    # =========================================================================
    # ROW 3 — Options row: checkbox + verbosity dropdown
    # =========================================================================
    options_row = Gtk::Box.new(Gtk::Orientation::Horizontal, 12)

    chk_skip_cleanup = Gtk::CheckButton.new
    chk_skip_cleanup.label = "Skip post-run cleanup"
    options_row.append(chk_skip_cleanup)

    lbl_verbosity = Gtk::Label.new("Verbosity:")
    options_row.append(lbl_verbosity)

    verbosity_strings = ["Errors only", "Warnings", "Info", "Debug"]
    dd_verbosity = Gtk::DropDown.new_from_strings(verbosity_strings)
    dd_verbosity.selected = 0_u32
    options_row.append(dd_verbosity)

    root_box.append(options_row)

    # =========================================================================
    # ROW 4 — Action buttons
    # =========================================================================
    action_row = Gtk::Box.new(Gtk::Orientation::Horizontal, 8)

    btn_run = Gtk::Button.new_with_label("Run Unwad")
    btn_run.add_css_class("suggested-action")
    action_row.append(btn_run)

    btn_clean = Gtk::Button.new_with_label("Clean Only")
    action_row.append(btn_clean)

    root_box.append(action_row)

    # =========================================================================
    # ROW 5 — Output section: label + scrolled text view
    # =========================================================================
    lbl_output = Gtk::Label.new("Output")
    lbl_output.halign = Gtk::Align::Start
    root_box.append(lbl_output)

    text_buffer = Gtk::TextBuffer.new
    text_view = Gtk::TextView.new_with_buffer(text_buffer)
    text_view.editable = false
    text_view.monospace = true
    text_view.wrap_mode = Gtk::WrapMode::WordChar
    text_view.vexpand = true

    scrolled = Gtk::ScrolledWindow.new
    scrolled.child = text_view
    scrolled.vexpand = true
    scrolled.min_content_height = 200
    root_box.append(scrolled)

    # =========================================================================
    # BUTTON HANDLERS — run_pipeline wiring
    # =========================================================================

    btn_run.clicked_signal.connect do
      # Disable both buttons during processing
      btn_run.sensitive = false
      btn_clean.sensitive = false
      text_buffer.text = ""

      # Read slider values from scale adjustments
      weapon_val    = scale_weapon.adjustment.value
      monster_val   = scale_monster.adjustment.value
      ally_val      = scale_ally.adjustment.value
      ammo_val      = scale_ammo.adjustment.value
      nice_item_val = scale_nice.adjustment.value
      pickup_val    = scale_pickup.adjustment.value
      no_cleanup    = chk_skip_cleanup.active?

      # Set verbosity from dropdown (index 0=0, 1=1, 2=2, 3=3)
      Config.log_level = dd_verbosity.selected.to_i32

      # Set GUI output callback so log() routes to the text buffer
      Config.gui_output_callback = ->(line : String) {
        gui_append_output(text_buffer, text_view, line)  # gui.cr
        nil
      }

      # Run pipeline in a background thread so GTK main loop stays responsive
      Thread.new do
        begin
          run_pipeline(  # unwad.cr
            weapon_default:  weapon_val,
            monster_default: monster_val,
            ally_default:    ally_val,
            ammo_default:    ammo_val,
            nice_item_default: nice_item_val,
            pickup_default:  pickup_val,
            flag_no_cleanup: no_cleanup,
            flag_clean_only: false,
          )
          gui_append_output(text_buffer, text_view, "\n=== Processing complete! ===")
        rescue ex
          gui_append_output(text_buffer, text_view, "\n[ERROR] #{ex.message}")
        ensure
          # Re-enable buttons and clear callback on the main thread
          GLib.idle_add do
            btn_run.sensitive = true
            btn_clean.sensitive = true
            Config.gui_output_callback = nil
            false
          end
        end
      end
    end

    btn_clean.clicked_signal.connect do
      # Disable both buttons during processing
      btn_run.sensitive = false
      btn_clean.sensitive = false
      text_buffer.text = ""

      # Set verbosity from dropdown
      Config.log_level = dd_verbosity.selected.to_i32

      # Set GUI output callback
      Config.gui_output_callback = ->(line : String) {
        gui_append_output(text_buffer, text_view, line)  # gui.cr
        nil
      }

      # Run clean-only pipeline in a background thread with default slider values
      Thread.new do
        begin
          run_pipeline(  # unwad.cr
            weapon_default:    0.0,
            monster_default:   1.0,
            ally_default:      1.0,
            ammo_default:      10.0,
            nice_item_default: 0.3,
            pickup_default:    0.3,
            flag_no_cleanup:   false,
            flag_clean_only:   true,
          )
          gui_append_output(text_buffer, text_view, "\n=== Cleanup complete! ===")
        rescue ex
          gui_append_output(text_buffer, text_view, "\n[ERROR] #{ex.message}")
        ensure
          # Re-enable buttons and clear callback on the main thread
          GLib.idle_add do
            btn_run.sensitive = true
            btn_clean.sensitive = true
            Config.gui_output_callback = nil
            false
          end
        end
      end
    end

    # =========================================================================
    # PRESENT WINDOW
    # =========================================================================
    window.child = root_box
    window.present
  end

  exit(app.run)
end
