spec = Gem::Specification.new do |s|
  s.name = 'unicorn-lockdown'
  s.version = '0.13.0'
  s.platform = Gem::Platform::RUBY
  s.summary = "Helper library for running Unicorn with fork+exec/unveil/pledge on OpenBSD"
  s.author = "Jeremy Evans"
  s.homepage= 'https://github.com/jeremyevans/unicorn-lockdown'
  s.email = "code@jeremyevans.net"
  s.license = "MIT"
  s.files = ['README.rdoc', 'MIT-LICENSE', 'CHANGELOG'] + Dir['bin/*'] + Dir['files/*'] + Dir['lib/**/*.rb']
  s.bindir = 'bin'
  s.executables << 'unicorn-lockdown-add' << 'unicorn-lockdown-setup'

  s.add_dependency("pledge")
  s.add_dependency("unicorn")
end
