require_relative 'test_helper'
require 'net/http'
require 'fileutils'
require 'uri'

ENV['PORT'] ||= '4953'
prefix = ENV['UNICORN_LOCKDOWN_PREFIX'] ||= File.join(Dir.pwd, 'test', 'var')
ENV['UNICORN_LOCKDOWN_WORKER_CRASH_PLEDGE'] = 'inet prot_exec rpath cpath wpath flock'

describe 'unicorn-lockdown' do
  def unicorn(env={})
    env['RACK_ENV'] ||= 'production'
    argv = [ENV['UNICORN'] || 'unicorn', '-I', 'lib', '-I', 'test/lib', '-c', 'test/unicorn.conf', 'test/config.ru']
    Process.spawn(env, *argv, [:out, :err]=>"#{ENV['UNICORN_LOCKDOWN_PREFIX']}/log/unicorn/test-app.log")
    yield
  ensure
    sleep 1
    pkill('-KILL')
  end

  def uri(path)
    URI("http://127.0.0.1:#{ENV['PORT']}#{path}")
  end

  def core_files
    Dir['*.core']
  end

  def pkill(signal)
    system('pkill', signal, '-xf', 'ruby[0-9][0-9]: unicorn-test-app-master .*')
  end

  def pgrep
    system('pgreg', '-xf', 'ruby[0-9][0-9]: unicorn-test-app-master .*')
  end

  def run_tests(env={})
    unicorn(env) do
      sleep 1
      Net::HTTP.get(uri('/')).must_equal 'OK'
      Net::HTTP.get(uri('/veiled_path')).must_equal 'false'
      Net::HTTP.get(uri('/unveiled_path')).must_equal 'true'
      yield if block_given?

      # Prevent coverage in new workers
      pkill('-URG')
    
      unless @skip_exit
        begin
          # Exit worker manually to trigger worker coverage writing
          Net::HTTP.get(uri('/exit'))
        rescue EOFError
        end
      end

      core_files.must_be_empty
      2.times do
        begin
          Net::HTTP.get(uri('/pledge_violation'))
        rescue EOFError
        end
        core_files.wont_be_empty
      end

      # Make sure app still works after worker crash
      Net::HTTP.get(uri('/')).must_equal 'OK'

      # Force normal exiting to trigger master coverage writing
      pkill('-QUIT')

      while pgrep
        sleep(0.1)
      end
    end
  end

  before do
    %w'www www/request-error-data www/request-error-data/test-app www/sockets log log/unicorn'.each do |dir|
      FileUtils.mkdir_p(File.join(prefix, dir))
    end
    if ENV['COVERAGE']
      FileUtils.mkdir_p('coverage')
    end
  end
  after do
    FileUtils.rm_r(prefix)
    core_files.each{|f| File.delete(f)}
  end

  [nil, '/write_request', '/write_request_empty', '/no_request_file'].each do |path|
    it "runs unicorn in a pledged/unveiled mode #{path}" do
      run_tests do
        Net::HTTP.get(uri(path)).must_equal 'WR' if path
      end
    end
  end

  it "runs unicorn in a pledged/unveiled mode with nonempty request file and crash" do
    @skip_exit = true
    run_tests do
      Net::HTTP.get(uri('/write_request')).must_equal 'WR'
    end
  end

  it "runs unicorn in a pledged/unveiled mode without email" do
    run_tests('UNICORN_LOCKDOWN_NO_EMAIL'=>'1')
  end

  it "runs unicorn in a pledged/unveiled mode in development" do
    run_tests('RACK_ENV'=>'development')
  end

  it "runs unicorn in a pledged/unveiled mode without rack" do
    run_tests('UNICORN_LOCKDOWN_NO_RACK'=>'1', 'UNICORN_LOCKDOWN_NO_EMAIL'=>'1')
  end

  it "runs unicorn in a pledged/unveiled mode without rubygems" do
    run_tests('UNICORN_LOCKDOWN_NO_GEM'=>'1')
  end
end if RUBY_VERSION >= '2.3'
