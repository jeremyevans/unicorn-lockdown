require_relative 'test_helper'
require 'fileutils'

prefix = ENV['UNICORN_LOCKDOWN_BIN_PREFIX'] ||= File.join(Dir.pwd, 'test')

begin
  Etc.getgrnam('_unicorn')
rescue ArgumentError
  $stderr.puts "Cannot runs unicorn-lockdown bin tests, add _unicorn group as root"
else
require 'etc'
user = Etc.getpwuid.name
describe 'unicorn_lockdown bin' do
  before do
    [ "#{prefix}/var/www", "#{prefix}/var/log", "#{prefix}/etc/rc.d", "#{prefix}/etc/nginx" ].each do |dir|
      FileUtils.mkdir_p(dir)
    end
  end
  after do
    ["#{prefix}/var", "#{prefix}/etc"].each do |dir|
      FileUtils.rm_r(dir)
    end
  end

  it  "unicorn-lockdown-setup and unicorn-lockdown-add create appropriate files and directories" do
    2.times do
      system(RUBY, 'bin/unicorn-lockdown-setup', :out=>'/dev/null').must_equal true
      File.directory?("#{prefix}/var/www/request-error-data").must_equal true
      File.directory?("#{prefix}/var/www/sockets").must_equal true
      File.directory?("#{prefix}/var/log/unicorn").must_equal true
      File.directory?("#{prefix}/var/log/nginx").must_equal true
      File.file?("#{prefix}/etc/rc.d/rc.unicorn").must_equal true
      File.binread("#{prefix}/etc/rc.d/rc.unicorn").must_equal(File.binread("files/rc.unicorn"))
    end

    r, w = IO.pipe
    system(RUBY, 'bin/unicorn-lockdown-add', '-h', :out=>w).must_equal true
    w.close
    r.read.must_include('Usage: unicorn-lockdown-add -o owner -u user [options] app_name')

    r, w = IO.pipe
    system(RUBY, 'bin/unicorn-lockdown-add', :out=>w, :err=>w).must_equal false
    w.close
    output = r.read
    output.must_include('Must pass -o and -u options when calling unicorn_lockdown_add')
    output.must_include('Usage: unicorn-lockdown-add -o owner -u user [options] app_name')

    2.times do
      system(RUBY, 'bin/unicorn-lockdown-add', '-o', user, '-u', user, 'test-app', :out=>'/dev/null').must_equal true
      File.directory?("#{prefix}/var/www/request-error-data/test-app").must_equal true
      File.directory?("#{prefix}/var/www/test-app").must_equal true
      File.directory?("#{prefix}/var/www/test-app/public").must_equal true

      File.file?("#{prefix}/var/log/nginx/test-app.access.log").must_equal true
      File.size("#{prefix}/var/log/nginx/test-app.access.log").must_equal 0
      File.file?("#{prefix}/var/log/nginx/test-app.error.log").must_equal true
      File.size("#{prefix}/var/log/nginx/test-app.error.log").must_equal 0
      File.file?("#{prefix}/var/log/unicorn/test-app.log").must_equal true
      File.size("#{prefix}/var/log/unicorn/test-app.log").must_equal 0

      File.file?("#{prefix}/etc/rc.d/unicorn_test_app").must_equal true
      File.binread("#{prefix}/etc/rc.d/unicorn_test_app").must_equal(<<END)
#!/bin/ksh

daemon_user=billg
unicorn_app=test-app
unicorn_dir=/home/billg/unicorn-lockdown/test/var/www/test-app

. /etc/rc.d/rc.unicorn
END

      File.file?("#{prefix}/var/www/test-app/unicorn.conf").must_equal true
      File.binread("#{prefix}/var/www/test-app/unicorn.conf").must_equal(<<END)
require 'unicorn-lockdown'

Unicorn.lockdown(self,
  :app=>"test-app",

  # Update this with correct email
  :email=>'root',

  # More pledges may be needed depending on application
  :pledge=>'rpath prot_exec inet unix flock',
  :master_pledge=>'rpath prot_exec cpath wpath inet proc exec',
  :master_execpledge=>'stdio rpath prot_exec inet unix cpath wpath unveil flock',

  # More unveils may be needed depending on application
  :unveil=>{
    'views'=>'r'
  },
  :dev_unveil=>{
    'models'=>'r'
  },
)
END

      File.file?("#{prefix}/etc/nginx/test-app.conf").must_equal true
      File.binread("#{prefix}/etc/nginx/test-app.conf").must_equal(<<END)
upstream test-app_unicorn {
    server unix:/sockets/test-app.sock fail_timeout=0;
}
server {
    server_name test-app;
    access_log /home/billg/unicorn-lockdown/test/var/log/nginx/test-app.access.log main;
    error_log /home/billg/unicorn-lockdown/test/var/log/nginx/test-app.error.log warn;
    root /home/billg/unicorn-lockdown/test/var/www/test-app/public;
    error_page   500 503 /500.html;
    error_page   502 504 /502.html;
    proxy_set_header  X-Real-IP  $remote_addr;
    proxy_set_header  X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header  Host $http_host;
    proxy_redirect    off;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options deny;
    add_header X-XSS-Protection "1; mode=block";
    try_files $uri @test-app_unicorn;
    location @test-app_unicorn {
        proxy_pass http://test-app_unicorn;
    }
}
END
    end

    system(RUBY, 'bin/unicorn-lockdown-add', '-o', user, '-u', user, '-c', 'c.ru', '-d', 'ta', '-f', 'u/u.conf', '--uid', Process.uid.to_s, 'test-app2', :out=>'/dev/null').must_equal true

    File.directory?("#{prefix}/var/www/request-error-data/test-app2").must_equal true
    File.directory?("#{prefix}/var/www/ta").must_equal true
    File.directory?("#{prefix}/var/www/ta/public").must_equal true

    File.file?("#{prefix}/var/log/nginx/test-app2.access.log").must_equal true
    File.size("#{prefix}/var/log/nginx/test-app2.access.log").must_equal 0
    File.file?("#{prefix}/var/log/nginx/test-app2.error.log").must_equal true
    File.size("#{prefix}/var/log/nginx/test-app2.error.log").must_equal 0
    File.file?("#{prefix}/var/log/unicorn/test-app2.log").must_equal true
    File.size("#{prefix}/var/log/unicorn/test-app2.log").must_equal 0

    File.file?("#{prefix}/etc/rc.d/unicorn_test_app2").must_equal true
    File.binread("#{prefix}/etc/rc.d/unicorn_test_app2").must_equal(<<END)
#!/bin/ksh

daemon_user=billg
unicorn_app=test-app2
unicorn_dir=/home/billg/unicorn-lockdown/test/var/www/ta
unicorn_conf=u/u.conf
rackup_file=c.ru

. /etc/rc.d/rc.unicorn
END

    File.file?("#{prefix}/var/www/ta/u/u.conf").must_equal true
    File.binread("#{prefix}/var/www/ta/u/u.conf").must_equal(<<END)
require 'unicorn-lockdown'

Unicorn.lockdown(self,
  :app=>"test-app2",

  # Update this with correct email
  :email=>'root',

  # More pledges may be needed depending on application
  :pledge=>'rpath prot_exec inet unix flock',
  :master_pledge=>'rpath prot_exec cpath wpath inet proc exec',
  :master_execpledge=>'stdio rpath prot_exec inet unix cpath wpath unveil flock',

  # More unveils may be needed depending on application
  :unveil=>{
    'views'=>'r'
  },
  :dev_unveil=>{
    'models'=>'r'
  },
)
END

    File.file?("#{prefix}/etc/nginx/test-app2.conf").must_equal true
    File.binread("#{prefix}/etc/nginx/test-app2.conf").must_equal(<<END)
upstream test-app2_unicorn {
    server unix:/sockets/test-app2.sock fail_timeout=0;
}
server {
    server_name test-app2;
    access_log /home/billg/unicorn-lockdown/test/var/log/nginx/test-app2.access.log main;
    error_log /home/billg/unicorn-lockdown/test/var/log/nginx/test-app2.error.log warn;
    root /home/billg/unicorn-lockdown/test/var/www/ta/public;
    error_page   500 503 /500.html;
    error_page   502 504 /502.html;
    proxy_set_header  X-Real-IP  $remote_addr;
    proxy_set_header  X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header  Host $http_host;
    proxy_redirect    off;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options deny;
    add_header X-XSS-Protection "1; mode=block";
    try_files $uri @test-app2_unicorn;
    location @test-app2_unicorn {
        proxy_pass http://test-app2_unicorn;
    }
}
END
  end
end
end
