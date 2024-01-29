require "file"
require "file_utils"
require "regex"
require "compress/zip"

def add_files_to_zip(zip : Compress::Zip::Writer, base_directory : String, directory : String)
  Dir.each_child(directory) do |entry|
    entry_path = File.join(directory, entry)
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


directories_to_compress = Dir.glob("./Processing_PK3/*")
directories_to_compress.each do |directory|
  puts "Directory: #{directory}"
  zip_file = "./Completed/" + directory.split("/").last + ".pk3"
  puts "Zip File: #{zip_file}"
  Compress::Zip::Writer.open(zip_file) do |zip|
    add_files_to_zip(zip, directory, directory)
  end
end

exit(0)

exit(0)

file_text = File.read("./Processing_PK3/BloodFiend/ZSCRIPT.txt")

puts file_text

matches = file_text.scan(/^\h*class\N*\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi)

matches.each do |match|
  puts "Match:"
  puts "---------"
  puts match[0].to_s.lines.first
end

entries = Dir.glob("./Processing_PK3/**/*").select { |entry| entry =~ /\/sprites\//i }

puts entries

exit(0)
match = file_text.match(/^\s*class\N*\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi).to_s

puts "-----"
puts "Match"
puts "-----"
puts match

states = match.match(/^\s*states\N*\s*(\{(?:([^\{\}]*)|(?:(?2)(?1)(?2))*)\})/mi).to_s
puts "------"
puts "States"
puts "------"
puts states
