require_relative 'test_helper'

describe 'Unveiler' do
  require_relative '../lib/unveiler'
  current_path = File.realpath(__FILE__)
  after do
    Dir['*.core'].each{|f| File.delete(f)}
  end

  def unveiler(status, promises, unveils, code, *args)
    argv = [RUBY, *args, '-I', 'lib', '-e', "require 'unveiler'; Unveiler.pledge_and_unveil(#{promises.inspect}, #{unveils.inspect}); #{code}"]
    system(*argv).must_equal status
  end

  it "should unveil and pledge to given directories" do
    unveiler(true, "rpath wpath cpath", {'.'=>'rwc'}, (<<-RUBY))
      raise 'cannot read' unless File.read('Rakefile').is_a?(String)
      dir = File.dirname(File.dirname(#{current_path.inspect}))
      raise "should be visible: \#{dir}" unless File.directory?(dir)
      dir = File.dirname(dir)
      raise "should not be visible: \#{dir}" if File.directory?(dir)
    RUBY
    unveiler(false, "", {}, <<-RUBY) unless ENV['COVERAGE']
      File.binwrite('a', 'a')
    RUBY
  end

  it "should handle case where rubygems is not loaded" do
    args = ['--disable-gems', '-I', File.join(Gem.loaded_specs['pledge'].full_gem_path, 'lib')]
    if ENV['COVERAGE']
      %w'simplecov docile simplecov-html'.each do |gem|
        args << '-I' << File.join(Gem.loaded_specs[gem].full_gem_path, 'lib')
      end
    end
    unveiler(true, "rpath wpath cpath", {'.'=>'rwc'}, (<<-RUBY), *args)
      raise 'cannot read' unless File.read('Rakefile').is_a?(String)
      dir = File.dirname(File.dirname(#{current_path.inspect}))
      raise "should be visible: \#{dir}" unless File.directory?(dir)
      dir = File.dirname(dir)
      raise "should not be visible: \#{dir}" if File.directory?(dir)
    RUBY
  end

  begin
    require 'rack'
    require 'mail'
  rescue LoadError
  else
    it "should automatically unveil rack and mail directories if they have been required" do
      rack_path = Gem.loaded_specs['rack'].full_gem_path
      mail_path = Gem.loaded_specs['mail'].full_gem_path

      unveiler(true, "rpath wpath cpath", {'.'=>'rwc'}, (<<-RUBY), '-r', 'mail', '-r', 'rack')
        [#{rack_path.inspect}, #{mail_path.inspect}].each do |path|
          raise 'should be visible' unless File.directory?(path)
          raise 'should not be visible' if File.directory?(File.dirname(path))
        end
      RUBY
    end
  end
end
