Dir['test/*_test.rb'].each{|f| require_relative File.basename(f)}
