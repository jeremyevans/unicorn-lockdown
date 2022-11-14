require "rake/clean"

CLEAN.include ["*.gem", "rdoc", "coverage"]

desc "Build unicorn-lockdown gem"
task :package=>[:clean] do |p|
  sh %{#{FileUtils::RUBY} -S gem build unicorn-lockdown.gemspec}
end

### Specs

desc "Run tests"
task :test do
  ruby = ENV['RUBY'] ||= FileUtils::RUBY 
  ENV['UNICORN'] ||= ruby.sub('ruby', 'unicorn')
  sh "#{ruby} #{"-w" if RUBY_VERSION >= '3'} test/all.rb"
end

task :default => :test

desc "Run tests with coverage"
task :test_cov=>:clean do
  ruby = ENV['RUBY'] ||= FileUtils::RUBY 
  ENV['UNICORN'] ||= ruby.sub('ruby', 'unicorn')
  ENV['COVERAGE'] = '1'
  sh "#{ruby} test/all.rb"
end

desc "Run CI test"
task :test_ci do
  ruby = ENV['RUBY'] ||= FileUtils::RUBY 
  ENV['UNICORN'] ||= ruby.sub('ruby', 'unicorn')
  ENV['UNICORN_LOCKDOWN_CI_TEST'] = 'verbose'
  sh "#{ruby} test/all.rb"
end

### RDoc

require "rdoc/task"

RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = "rdoc"
  rdoc.options += ['--inline-source', '--line-numbers', '--title', 'unicorn-lockdown: Helper library for running Unicorn with fork+exec/unveil/pledge on OpenBSD', '--main', 'README.rdoc', '-f', 'hanna']
  rdoc.rdoc_files.add %w"README.rdoc CHANGELOG MIT-LICENSE lib/**/*.rb"
end
