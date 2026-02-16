###############################################################################
# helpers.cr — Utility functions for Unwad / Monster Mash
###############################################################################

# Check if a string is a valid integer
def numeric?(str : String) : Bool
  str.to_i? != nil
end

# Safely read a file, returning empty string on failure
def safe_read(path : String) : String
  norm = normalize_path(path)
  if File.exists?(norm)
    File.read(norm)
  else
    log(1, "File not found: #{norm}")
    ""
  end
end

# Normalize path separators to forward slashes (Windows compat)
def normalize_path(path : String) : String
  path.gsub("\\", "/")
end

# Safe directory move: copy then delete.
# FileUtils.mv fails on Windows when directories are locked (e.g., Dropbox sync)
# or when moving across volumes. cp_r + rm_rf is more reliable.
def safe_move_dir(src : String, dest : String)
  src_n = normalize_path(src)
  dest_n = normalize_path(dest)
  log(3, "Moving directory: #{src_n} → #{dest_n}")
  FileUtils.rm_rf(dest_n) if Dir.exists?(dest_n)
  FileUtils.cp_r(src_n, dest_n)
  FileUtils.rm_rf(src_n)
rescue ex
  log(0, "Failed to move '#{src_n}' → '#{dest_n}': #{ex.message}")
  raise ex
end

# Collect all DECORATE files for a wad (main + includes).
# Uses multi-strategy path resolution so it works with both jeutool-extracted
# WADs (files in defs/ with .raw extension) and PK3-extracted content
# (files at WAD root with various extensions like .dec, .txt, or no extension).
def collect_decorate_files(base_path : String) : Array(String)
  file_list = [base_path]
  return file_list unless File.exists?(base_path)

  base_dir = normalize_path(File.dirname(base_path))
  # For files in defs/, the WAD root is one level up
  wad_root = normalize_path(File.dirname(base_dir))

  File.each_line(base_path) do |line|
    if line.strip =~ /^#include\s+/i
      if md = line.match(/"([^"]+)"/)
        include_ref = md[1]

        # Try multiple resolution strategies (first match wins):
        candidates = [
          File.join(base_dir, "#{include_ref.upcase}.raw"),   # defs/NAME.RAW (jeutool)
          File.join(base_dir, include_ref),                    # defs/path/as-is
          File.join(base_dir, include_ref.upcase),             # defs/NAME (no ext)
          File.join(wad_root, include_ref),                    # wad_root/path/as-is (PK3)
          File.join(wad_root, "#{include_ref.upcase}.raw"),    # wad_root/NAME.RAW
          File.join(wad_root, include_ref.upcase),             # wad_root/NAME
        ]

        found = candidates.find { |c| File.exists?(normalize_path(c)) }
        if found
          file_list << normalize_path(found)
        else
          log(1, "Include not resolved: \"#{include_ref}\" (from #{base_path})")
          log(3, "  Searched: #{candidates.map { |c| normalize_path(c) }.join(", ")}")
        end
      end
    end
  end
  file_list.uniq
end

# Match balanced braces starting from a given position in text.
# Returns the substring from the opening '{' to the matching '}'.
def extract_balanced_braces(text : String, start_pos : Int32) : String?
  return nil if start_pos < 0 || start_pos >= text.size
  depth = 0
  i = start_pos
  while i < text.size
    if text[i] == '{'
      depth += 1
    elsif text[i] == '}'
      depth -= 1
      if depth == 0
        return text[start_pos..i]
      end
    end
    i += 1
  end
  nil
end

# Remove the states block from actor text using iterative brace matching.
# V1 used a recursive PCRE regex that doesn't work reliably in Crystal.
def remove_states_block(actor_text : String) : String
  result = actor_text
  # Find "states" keyword followed by "{"
  if md = result.match(/states\s*\{/mi)
    states_start = md.begin(0).not_nil!
    # Find the opening brace
    brace_start = result.index('{', states_start)
    if brace_start
      matched = extract_balanced_braces(result, brace_start)
      if matched
        # Remove "states" keyword + the entire braced block
        states_keyword_start = states_start
        states_end = brace_start + matched.size
        result = result[0...states_keyword_start] + result[states_end..]
      end
    end
  end
  result
end

# Extract the states block text (content between braces after "states")
def extract_states_text(actor_text : String) : String?
  if md = actor_text.match(/states\s*\{/mi)
    states_start = md.begin(0).not_nil!
    brace_start = actor_text.index('{', states_start)
    if brace_start
      matched = extract_balanced_braces(actor_text, brace_start)
      if matched && matched.size > 2
        # Strip outer braces
        return matched[1..-2].strip
      end
    end
  end
  nil
end

# Parse states text into a hash of state_label => state_content
def parse_states(states_text : String?) : Hash(String, String)
  states = Hash(String, String).new
  return states if states_text.nil?

  parts = states_text.not_nil!.split(/^(\S+)\:/m)
  # First element is anything before the first label — discard
  parts.shift if parts.size > 0

  (0...parts.size).step(2) do |i|
    break if i + 1 >= parts.size
    key = parts[i].strip.downcase
    value = parts[i + 1]
    states[key] = value
  end
  states
end

# Delete all contents of a directory without deleting the directory itself
def clear_directory(path : String)
  if Dir.exists?(path)
    Dir.each_child(path) do |child|
      child_path = File.join(path, child)
      if File.directory?(child_path)
        FileUtils.rm_rf(child_path)
      else
        File.delete(child_path)
      end
    end
  end
end
