spec = Gem::Specification.new do |s|
  s.name = 'unicorn-lockdown'
  s.version = '0.9.0'
  s.platform = Gem::Platform::RUBY
  s.has_rdoc = false
  s.summary = "Helper library for running Unicorn with chroot/privdrop/fork+exec/pledge on OpenBSD"
  s.author = "Jeremy Evans"
  s.homepage= 'https://github.com/jeremyevans/unicorn-lockdown'
  s.email = "code@jeremyevans.net"
  s.license = "MIT"
  s.files = ['README.rdoc', 'MIT-LICENSE'] + Dir['files/*'] + Dir['lib/**/*.rb']

  s.add_dependency("pledge")
  s.add_dependency("unicorn")
end
