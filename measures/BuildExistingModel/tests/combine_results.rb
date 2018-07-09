require "csv"

def csv_headers
  header = []
  CSV.foreach(File.join(File.dirname(__FILE__), "1_results.csv")) do |sample|
    if header.empty?
      header = sample
    else
      break
    end
  end
  return header
end

files = Dir[File.join(File.dirname(__FILE__), "*_results.csv")]
file_contents = files.map { |f| CSV.read(f) }

csv_string = CSV.generate do |csv|
  csv << csv_headers
  file_contents.each do |file|
    file.shift
    file.each do |row|
      csv << row
    end
  end
end

File.open(File.join(File.dirname(__FILE__), "results.csv"), "w") { |f| f << csv_string }