require_relative '../../../test/minitest_helper'
require 'openstudio'
require 'openstudio/ruleset/ShowRunnerOutput'
require 'minitest/autorun'
require_relative '../measure.rb'
require 'fileutils'

class BuildExistingModelTest < MiniTest::Test

  def test_create_results_csv_from_registered_values
    # this test applies all the residential measures using the build existing model measure
    # but exports the registered values to csv BEFORE running any simulations
    require 'parallel'

    runners = []
    characteristics_dir = File.absolute_path(File.join(File.dirname(__FILE__), "..", "..", "..", "lib", "housing_characteristics"))
    buildstock_csv = File.absolute_path(File.join(characteristics_dir, "buildstock.csv"))
    num_nodes, num_cores = nodes_and_cores_counts

    puts "Num Nodes: #{num_nodes}"
    if num_nodes > 1
      node_rank = ENV["PBS_ARRAYID"].to_i
      split_csv(buildstock_csv, num_nodes)
      new_buildstock_csv = File.join(File.dirname(buildstock_csv), "#{node_rank}_buildstock.csv")
    else
      node_rank = 1
      new_buildstock_csv = buildstock_csv
    end

    building_ids = []
    CSV.foreach(new_buildstock_csv, headers:true) do |sample|
      building_ids << sample[0].to_i
    end

    puts "Current Node Rank: #{node_rank}"
    puts "Num Cores: #{num_cores}"
    puts "Num Building IDs: #{building_ids.length}"

    results_filename = File.join(File.dirname(__FILE__), "#{node_rank}_results.csv")

    if File.exists? results_filename

      puts "File #{results_filename} already exists."
      return

    end      

    Parallel.each(building_ids, in_processors: num_cores, progress: "Progress Update") do |building_id|
      puts "\nBuilding ID: #{building_id}"
      args_hash = {}
      args_hash["workflow_json"] = "measure-info.json"
      args_hash["number_of_buildings_represented"] = "80000000"
      args_hash["building_id"] = "#{building_id}"
      args_hash["buildstock_csv"] = File.basename(new_buildstock_csv)
      begin
        runners << _test_measure(args_hash)
      rescue
      end
    end

    unless runners.empty?
      puts "Writing #{results_filename}."
      CSV.open(results_filename, "w") do |csv|
        row = []
        result = runners[0].result
        result.stepValues.each do |arg|
          row << arg.name
        end
        csv << row
        runners.each do |runner|
          row = []
          result = runner.result
          result.stepValues.each do |arg|
            row << arg.valueAsVariant.to_s
          end
          csv << row
        end
      end
    end

  end

  private
  
  def split_csv(filename, num_nodes, header_lines=1)

    file = File.open(filename, "r")
    size = (file.readlines.size / num_nodes).ceil

    (1..num_nodes).each do |i|
      new_filename = File.join(File.dirname(filename), "#{i}_#{File.basename(filename)}")
      unless File.exist? new_filename
        CSV.open(new_filename, "w") do |csv|
          counter = 0
          CSV.foreach(filename, headers:false) do |row|
            counter += 1
            if counter == 1
              csv << row
              next
            end
            next if (counter-1) <= (i-1) * size
            csv << row
            break if (counter-1) >= i * size
          end
        end
      end
    end
  
  end
  
  def nodes_and_cores_counts
    case RbConfig::CONFIG['host_os']
    when /linux/
      puts "Platform: linux"
      num_nodes = 1
      if ENV.keys.include? "NUM_NODES"
        num_nodes = ENV["NUM_NODES"].to_i
        puts "From Env Var: #{num_nodes} Nodes"
      end
      num_cores = `cat /proc/cpuinfo | grep processor | wc -l`.to_i
    when /mswin|mingw/
      puts "Platform: mswin, mingw"
      num_nodes = 1
      require 'win32ole'
      wmi = WIN32OLE.connect("winmgmts://")
      cpu = wmi.ExecQuery("select NumberOfCores from Win32_Processor")
      num_cores = cpu.to_enum.first.NumberOfCores
    end
    return num_nodes, num_cores
  end
  
  def _test_measure(args_hash, num_infos=0, num_warnings=0)
    # create an instance of the measure
    measure = BuildExistingModel.new

    # check for standard methods
    assert(!measure.name.empty?)
    assert(!measure.description.empty?)
    assert(!measure.modeler_description.empty?)

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)
    
    model = OpenStudio::Model::Model.new
    
    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)

    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      if args_hash.has_key?(arg.name)
        assert(temp_arg_var.setValue(args_hash[arg.name]))
      end
      argument_map[arg.name] = temp_arg_var
    end

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result
    
    # show_output(result)

    # assert that it ran correctly
    assert_equal("Success", result.value.valueName)
    assert(result.info.size > 0)

    return runner
  end

end
