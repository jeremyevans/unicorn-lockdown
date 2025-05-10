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
  sh "#{ruby} #{"-w" if RUBY_VERSION >= '3'} #{'-W:strict_unused_block' if RUBY_VERSION >= '3.4'} test/all.rb"
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
  ENV['GEM'] ||= ruby.sub('ruby', 'gem')
  sh "#{ruby} test/all.rb"
end

### RDoc

desc "Generate rdoc"
task :rdoc do
  rdoc_dir = "rdoc"
  rdoc_opts = ["--line-numbers", "--inline-source", '--title', 'unicorn-lockdown: Helper library for running Unicorn with fork+exec/unveil/pledge on OpenBSD']

  begin
    gem 'hanna'
    rdoc_opts.concat(['-f', 'hanna'])
  rescue Gem::LoadError
  end

  rdoc_opts.concat(['--main', 'README.rdoc', "-o", rdoc_dir] +
    %w"README.rdoc CHANGELOG MIT-LICENSE" +
    Dir["lib/**/*.rb"]
  )

  FileUtils.rm_rf(rdoc_dir)

  require "rdoc"
  RDoc::RDoc.new.document(rdoc_opts)
end
