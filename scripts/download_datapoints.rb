#!/usr/bin/env ruby
# CLI tool to allow for recreate the localResults directory
# This provides a critical workaround for BuildStock PAT projects
# Written by Henry R Horsey III (henry.horsey@nrel.gov)
# Created September 8th, 2017
# Last updated on January 5th, 2018 (J Robertson)
# Copywrite the Alliance for Sustainable Energy LLC
# License: BSD3+1

require 'optparse'
require 'fileutils'
require 'zip'
require 'net/http'
require 'openssl'
require 'csv'
require 'parallel'

# Download the results csv if it doesn't already exist
#
# @param local_result_dir [::String] path to the localResults directory
def retrieve_results_csv(local_results_dir, server_dns=nil, analysis_id=nil)
  # Verify localResults directory
  unless File.basename(local_results_dir) == 'localResults'
    fail "ERROR: input #{local_results_dir} does not point to localResults"
  end

  dest = nil
  Dir["#{local_results_dir}/*.csv"].each do |item|
    dest = item
  end

  return unless dest.nil?
  dest = File.join local_results_dir, "results.csv"

  url = URI.parse("#{server_dns}/analyses/#{analysis_id}/download_data.csv?")
  http = Net::HTTP.new(url.host, url.port)
  http.read_timeout = 1000 # seconds

  params = { 'export' => 'true' }
  url.query = URI.encode_www_form(params)
  request = Net::HTTP::Get.new(url.request_uri)

  http.request request do |response|
    total = response.header["Content-Length"].to_i
    if total == 0
      fail "Did not successfully download zip file."
    end
    size = 0
    progress = 0
    open dest, 'wb' do |io|
      response.read_body do |chunk|
        io.write chunk
        size += chunk.size
        new_progress = (size * 100) / total
        unless new_progress == progress
          puts "Downloading %s (%3d%%) " % [dest, new_progress]
        end
        progress = new_progress
      end
    end
  end

end

# Unzip an archive to a destination directory using Rubyzip gem
#
# @param archive [:string] archive path for extraction
# @param dest [:string] path for archived file to be extracted to
def unzip_archive(archive, dest)
  # Adapted from examples at...
  # https://github.com/rubyzip/rubyzip
  # http://seenuvasan.wordpress.com/2010/09/21/unzip-files-using-ruby/
  Zip::File.open(archive) do |zf|
    zf.each do |f|
      f_path = File.join(dest, f.name)
      FileUtils.mkdir_p(File.dirname(f_path))
      zf.extract(f, f_path) unless File.exist?(f_path) # No overwrite
    end
  end
end

def retrieve_dps(local_results_dir)
  dps = []
  Dir["#{local_results_dir}/*.csv"].each do |item|
    rows = CSV.read(item, {:encoding=>'ISO-8859-1'})
    rows.each_with_index do |row, i|
      next if i == 0
      dps << {:_id => row[1]}
    end    
  end
  return dps
end

# Download any datapoint that is not already in the localResults directory
#
# @param local_result_dir [::String] path to the localResults directory
# @return [logical] Indicates if any errors were caught
def retrieve_dp_data(local_results_dir, server_dns=nil, unzip=false)
  # Verify localResults directory
  unless File.basename(local_results_dir) == 'localResults'
    fail "ERROR: input #{local_results_dir} does not point to localResults"
  end

  # Ensure there are datapoints to download
  dps = retrieve_dps(local_results_dir)
  if dps.empty?
    fail "ERROR: No datapoints were found. Unable to download the results csv."
  end
  
  # Only download datapoints which do not already exist
  interval = 1
  report_at = interval
  timestep = Time.now
  num_parallel = Etc.nprocessors
  Parallel.each_with_index(dps, in_threads: num_parallel) do |dp, i|

    dest = File.join local_results_dir, dp[:_id]
    dp[:file] = File.join(dest, 'data_point.zip')
    next if File.exist? dp[:file]
      
    url = URI.parse("#{server_dns}/data_points/#{dp[:_id]}/download_result_file?")
    http = Net::HTTP.new(url.host, url.port)

    params = { 'filename' => 'data_point.zip' }
    url.query = URI.encode_www_form(params)
    request = Net::HTTP::Get.new(url.request_uri)
    
    begin
      http.request request do |response|
        next unless response.kind_of? Net::HTTPSuccess
        if not File.exist? dest
          Dir.mkdir dest
        end
        open dp[:file], 'wb' do |io|
          response.read_body do |chunk|
            io.write chunk
          end
          puts "Worker #{Parallel.worker_number}, DOWNLOADED: #{dp[:file]}"
        end
        
        if unzip
          unzip_archive(dp[:file], dest)
          File.delete(dp[:file])
        end
        
      end
    rescue => error
      puts "Datapoint #{File.basename(File.dirname(dp[:file]))}, ERROR:"
      error.backtrace.each do |trace|
        puts "\t#{trace}"
      end
      next
    end
    
    # Report out progress
    if i.to_f * 100 / dps.length >= report_at
      puts "INFO: Completed #{report_at}%; #{(Time.now - timestep).round}s"
      report_at += interval
      timestep = Time.now
    end
    
  end

end

# Initialize optionsParser ARGV hash
options = {}

# Define allowed ARGV input
# -p --project_dir [string]
# -s --server_dns [string]
# -a --analysis_id [string]
optparse = OptionParser.new do |opts|
  opts.banner = 'Usage:    download_datapoints [-p] <project_dir> [-s] <server_dns> [-a] <analysis_id> [-u] [-h]'

  options[:project_dir] = nil
  opts.on('-p', '--project_dir <dir>', 'specified project DIRECTORY') do |dir|
    options[:project_dir] = dir
  end

  options[:server_dns] = nil
  opts.on('-s', '--server_dns <DNS>', 'specified server DNS') do |dns|
    options[:server_dns] = dns
  end

  options[:analysis_id] = nil
  opts.on('-a', '--analysis_id <id>', 'specified analysis ID') do |id|
    options[:analysis_id] = id
  end

  options[:unzip] = false
  opts.on('-u', '--unzip', 'extract data_point.zip contents') do |zip|
    options[:unzip] = true
  end
  
  opts.on_tail('-h', '--help', 'display help') do
    puts opts
    exit
  end
end

# Execute ARGV parsing into options hash holding symbolized key values
optparse.parse!

# Check inputs for basic compliance criteria
unless Dir.exists?(options[:project_dir])
  fail "ERROR: Could not find #{options[:project_dir]}"
end

# Create the localResults directory should it not exist
local_results_dir = File.join(options[:project_dir], 'localResults')
unless Dir.exists? local_results_dir
  Dir.mkdir local_results_dir
end

# Retrieve the datapoints and indicate success
retrieve_results_csv(local_results_dir, options[:server_dns], options[:analysis_id])
retrieve_dp_data(local_results_dir, options[:server_dns], options[:unzip])