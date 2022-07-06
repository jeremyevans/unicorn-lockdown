require 'etc'

prefix = ENV['UNICORN_LOCKDOWN_BIN_PREFIX']
request_dir = "#{prefix}/var/www/request-error-data"
socket_dir = "#{prefix}/var/www/sockets"
unicorn_log_dir = "#{prefix}/var/log/unicorn"
nginx_log_dir = "#{prefix}/var/log/nginx"
rc_unicorn_file = "#{prefix}/etc/rc.d/rc.unicorn"

unicorn_group = '_unicorn'
root_id = 0
daemon_id = 1
www_id = 67

if Process.uid == 0
  # :nocov:
  chown = lambda{|*a| File.chown(*a)}
  # :nocov:
else
  chown = lambda{|*a| }
end

# Add _unicorn group if it doesn't exist
group = begin
  Etc.getgrnam(unicorn_group)
rescue ArgumentError
  # :nocov:
  args = ['groupadd', unicorn_group]
  puts "Running: #{args.join(' ')}"
  system(*args) || raise("Error while running: #{args.join(' ')}")
  Etc.getgrnam(unicorn_group)
  # :nocov:
end
unicorn_group_id = group.gid

# Setup requests directory to hold per-request information for crash notifications
unless File.directory?(request_dir)
  puts "Creating #{request_dir}"
  Dir.mkdir(request_dir)
  File.chmod(0710, request_dir)
  chown.(root_id, unicorn_group_id, request_dir)
end

# Setup sockets directory to hold nginx connection sockets
unless File.directory?(socket_dir)
  puts "Creating #{socket_dir}"
  Dir.mkdir(socket_dir)
  File.chmod(0770, socket_dir)
  chown.(www_id, unicorn_group_id, socket_dir)
end

# Setup log directory to hold unicorn application logs
unless File.directory?(unicorn_log_dir)
  puts "Creating #{unicorn_log_dir}"
  Dir.mkdir(unicorn_log_dir)
  File.chmod(0755, unicorn_log_dir)
  chown.(root_id, daemon_id, unicorn_log_dir)
end

# Setup log directory to hold nginx logs
unless File.directory?(nginx_log_dir)
  puts "Creating #{nginx_log_dir}"
  Dir.mkdir(nginx_log_dir)
  File.chmod(0775, nginx_log_dir)
  chown.(www_id, root_id, nginx_log_dir)
end

# Setup rc.unicorn file
unless File.file?(rc_unicorn_file)
  puts "Creating #{rc_unicorn_file}"
  File.binwrite(rc_unicorn_file, File.binread(File.join(File.dirname(__dir__), 'files', 'rc.unicorn')))
  File.chmod(0644, rc_unicorn_file)
  chown.(root_id, root_id, rc_unicorn_file)
end
