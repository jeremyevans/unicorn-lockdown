require 'simplecov'

SimpleCov.instance_exec do
  enable_coverage :branch
  add_filter "/test/"
  add_group('Missing'){|src| src.covered_percent < 100}
  add_group('Covered'){|src| src.covered_percent == 100}
  enable_for_subprocesses true

  at_fork do |pid|
    command_name "#{SimpleCov.command_name} (subprocess: #{pid})"
    self.print_error_status = false
    formatter SimpleCov::Formatter::SimpleFormatter
    minimum_coverage 0
    start rescue nil
  end

  if ENV['COVERAGE'] == 'subprocess'
    command_name 'spawn'
    at_fork.call(Process.pid)
  else
    ENV['COVERAGE'] = 'subprocess'
    ENV['RUBYOPT'] = "#{ENV['RUBYOPT']} -r ./test/coverage_helper"
    start
  end
end
