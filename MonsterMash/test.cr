require "file"
require "file_utils"
require "regex"

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
