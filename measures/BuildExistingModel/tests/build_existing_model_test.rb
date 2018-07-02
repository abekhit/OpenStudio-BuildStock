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
    num_rows = 16
    Parallel.each([*1..num_rows], in_threads: 96) do |building_id|
      puts "#{building_id} / #{num_rows}"
      args_hash = {}
      args_hash["workflow_json"] = "measure-info.json"
      args_hash["number_of_buildings_represented"] = "80000000"
      args_hash["building_id"] = "#{building_id}"
      runners << _test_measure(args_hash)
    end
    CSV.open(File.join(File.dirname(__FILE__), "results.csv"), "w") do |csv|
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

  private
  
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
