require 'mail' unless ENV['UNICORN_LOCKDOWN_NO_EMAIL']
Object.send(:remove_const, :Rack) if ENV['UNICORN_LOCKDOWN_NO_RACK']
Object.send(:remove_const, :Gem) if ENV['UNICORN_LOCKDOWN_NO_GEM']

run(lambda do |env|
  case env['PATH_INFO']
  when '/'
    [200, {}, ['OK']]
  when '/veiled_path'
    [200, {}, [File.exist?(File.dirname(Dir.pwd))]]
  when '/unveiled_path'
    [200, {}, [File.exist?(__FILE__).to_s]]
  when '/pledge_violation'
    [200, {}, [File.mkfifo('test/fifo').to_s]]
  when '/write_request'
    Unicorn.write_request('nonempty')
    [200, {}, ['WR']]
  when '/write_request_empty'
    Unicorn.write_request('')
    [200, {}, ['WR']]
  when '/no_request_file'
    File.delete "test/var/www/request-error-data/test-app/#{$$}.txt"
    [200, {}, ['WR']]
  when '/exit'
    exit(0)
  when '/exit1'
    exit(1)
  else
    [404, {}, ['']]
  end
end)
