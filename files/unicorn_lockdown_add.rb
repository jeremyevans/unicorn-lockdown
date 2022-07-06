require 'etc'
require 'optparse'

unicorn = ''
rackup = ''
unicorn_file = 'unicorn.conf'
dir = nil
user = nil
new_user_uid = nil
owner = nil
owner_uid = nil
owner_gid = nil

options = OptionParser.new do |opts|
  opts.banner = "Usage: unicorn-lockdown-add -o owner -u user [options] app_name"
  opts.separator "Options:"

  opts.on_tail("-h", "-?", "--help", "Show this message") do
    puts opts
    exit
  end

  opts.on("-c RACKUP_FILE", "rackup configuration file") do |v|
    rackup = "rackup_file=#{v}\n"
  end

  opts.on("-d DIR", "application directory name") do |v|
    dir = v
  end

  opts.on("-f UNICORN_FILE", "unicorn configuration file relative to application directory") do |v|
    unicorn_file = v
    unicorn = "unicorn_conf=#{v}\n"
  end

  opts.on("-o OWNER", "operating system application owner") do |v|
    owner = v
    ent = Etc.getpwnam(v)
    owner_uid = ent.uid
    owner_gid = ent.gid
  end

  opts.on("-u USER", "operating system user to run application") do |v|
    user = v
  end

  opts.on("--uid UID", "user id to use if creating the user when -U is specified") do |v|
    new_user_uid = Integer(v, 10)
  end
end
options.parse!

unless user && owner
  $stderr.puts "Must pass -o and -u options when calling unicorn_lockdown_add"
  puts options
  exit(1)
end

app = ARGV.shift
dir ||= app

root_id = 0
bin_id = 7
www_id = 67

prefix = ENV['UNICORN_LOCKDOWN_BIN_PREFIX']
www_root = "#{prefix}/var/www"
dir = "#{www_root}/#{dir}"
rc_file = "#{prefix}/etc/rc.d/unicorn_#{app.tr('-', '_')}"
nginx_file = "#{prefix}/etc/nginx/#{app}.conf"
unicorn_conf_file = "#{dir}/#{unicorn_file}"
nonroot_dir = "#{prefix}/var/www/request-error-data/#{app}"
unicorn_log_file = "#{prefix}/var/log/unicorn/#{app}.log"
nginx_access_log_file = "#{prefix}/var/log/nginx/#{app}.access.log"
nginx_error_log_file = "#{prefix}/var/log/nginx/#{app}.error.log"

if Process.uid == 0
  # :nocov:
  chown = lambda{|*a| File.chown(*a)}
  # :nocov:
else
  chown = lambda{|*a| }
end

# Add application user if it doesn't exist
passwd = begin
  Etc.getpwnam(user)
rescue ArgumentError
  # :nocov:
  args = ['/usr/sbin/useradd', '-d', '/var/empty', '-g', '=uid', '-G', '_unicorn', '-L', 'daemon', '-s', '/sbin/nologin']
  if new_user_uid
    args << '-u' << new_user_uid.to_s
  end
  args << user
  puts "Running: #{args.join(' ')}"
  system(*args) || raise("Error while running: #{args.join(' ')}")
  Etc.getpwnam(user)
  # :nocov:
end
app_uid = passwd.uid

# Create the subdirectory used for request error info when not running as root
unless File.directory?(nonroot_dir)
  puts "Creating #{nonroot_dir}"
  Dir.mkdir(nonroot_dir)
  File.chmod(0700, nonroot_dir)
  chown.(app_uid, app_uid, nonroot_dir)
end

# Create application public directory if it doesn't exist (needed by nginx)
dirs = [dir, "#{dir}/public"]
dirs.each do |d|
  unless File.directory?(d)
    puts "Creating #{d}"
    Dir.mkdir(d)
    File.chmod(0755, d)
    chown.(owner_uid, owner_gid, d)
  end
end

# DRY up file ownership code
setup_file_owner = lambda do |file|
  File.chmod(0644, file)
  chown.(owner_uid, owner_gid, file)
end

# Setup unicorn configuration file
unless File.file?(unicorn_conf_file)
  unicorn_conf_dir = File.dirname(unicorn_conf_file)
  unless File.directory?(unicorn_conf_dir)
    puts "Creating #{unicorn_conf_dir}"
    Dir.mkdir(unicorn_conf_dir)
    File.chmod(0755, unicorn_conf_dir)
    chown.(owner_uid, owner_gid, unicorn_conf_dir)
  end
  puts "Creating #{unicorn_conf_file}"
  File.binwrite(unicorn_conf_file, <<END)
require 'unicorn-lockdown'

Unicorn.lockdown(self,
  :app=>#{app.inspect},

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
  setup_file_owner.call(unicorn_conf_file)
end

# Setup /etc/nginx/* file for nginx configuration
unless File.file?(nginx_file)
  puts "Creating #{nginx_file}"
  File.binwrite(nginx_file, <<END)
upstream #{app}_unicorn {
    server unix:/sockets/#{app}.sock fail_timeout=0;
}
server {
    server_name #{app};
    access_log #{nginx_access_log_file} main;
    error_log #{nginx_error_log_file} warn;
    root #{dir}/public;
    error_page   500 503 /500.html;
    error_page   502 504 /502.html;
    proxy_set_header  X-Real-IP  $remote_addr;
    proxy_set_header  X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header  Host $http_host;
    proxy_redirect    off;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options deny;
    add_header X-XSS-Protection "1; mode=block";
    try_files $uri @#{app}_unicorn;
    location @#{app}_unicorn {
        proxy_pass http://#{app}_unicorn;
    }
}
END

  setup_file_owner.call(nginx_file)
end

# Setup nginx log file
[nginx_access_log_file, nginx_error_log_file].each do |f|
  unless File.file?(f)
    puts "Creating #{f}"
    File.binwrite(f, '')
    File.chmod(0644, f)
    chown.(www_id, root_id, f)
  end
end

# Setup unicorn log file
unless File.file?(unicorn_log_file)
  puts "Creating #{unicorn_log_file}"
  File.binwrite(unicorn_log_file, '')
  File.chmod(0640, unicorn_log_file)
  chown.(app_uid, Etc.getgrnam('_unicorn').gid, unicorn_log_file)
end

# Setup /etc/rc.d/unicorn_* file for daemon management
unless File.file?(rc_file)
  puts "Creating #{rc_file}"
  File.binwrite(rc_file, <<END)
#!/bin/ksh

daemon_user=#{user}
unicorn_app=#{app}
unicorn_dir=#{dir}
#{unicorn}#{rackup}
. /etc/rc.d/rc.unicorn
END

  File.chmod(0755, rc_file)
  chown.(root_id, bin_id, rc_file)
end
