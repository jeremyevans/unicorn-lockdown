if ENV.delete('COVERAGE')
  require_relative 'coverage_helper'
end

gem 'minitest'
ENV['MT_NO_PLUGINS'] = '1' # Work around stupid autoloading of plugins
require 'minitest/global_expectations/autorun'

RUBY = ENV['RUBY'] || 'ruby'
