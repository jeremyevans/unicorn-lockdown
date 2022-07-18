Gem::Specification.new do |s|
  s.name = 'unicorn-lockdown'
  s.version = '1.0.0'
  s.platform = Gem::Platform::RUBY
  s.summary = "Helper library for running Unicorn with fork+exec/unveil/pledge on OpenBSD"
  s.author = "Jeremy Evans"
  s.homepage= 'https://github.com/jeremyevans/unicorn-lockdown'
  s.email = "code@jeremyevans.net"
  s.license = "MIT"
  s.files = ['README.rdoc', 'MIT-LICENSE', 'CHANGELOG'] + Dir['bin/*'] + Dir['files/*'] + Dir['lib/**/*.rb']
  s.bindir = 'bin'
  s.executables << 'unicorn-lockdown-add' << 'unicorn-lockdown-setup'

  s.metadata          = { 
    'bug_tracker_uri'   => 'https://github.com/jeremyevans/unicorn-lockdown/issues',
    'changelog_uri'     => 'https://github.com/jeremyevans/unicorn-lockdown/blob/master/CHANGELOG',
    'mailing_list_uri'  => 'https://github.com/jeremyevans/unicorn-lockdown/discussions',
    "source_code_uri"   => 'https://github.com/jeremyevans/unicorn-lockdown'
  }

  s.required_ruby_version = ">= 2.0.0"
  s.add_dependency("pledge")
  s.add_dependency("unicorn")

  s.add_development_dependency("rack")
  s.add_development_dependency("mail")
  s.add_development_dependency("roda")
  s.add_development_dependency("minitest-global_expectations")
end
