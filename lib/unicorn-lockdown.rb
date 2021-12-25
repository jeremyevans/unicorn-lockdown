# unicorn-lockdown is designed to handle fork+exec, unveil, and pledge support
# when using Unicorn, including:
# * restricting file system access using unveil
# * pledging the app to restrict allowed syscalls at the appropriate point
# * handling notifications of worker crashes (which are likely due to pledge
#   violations)

require 'pledge'
require 'unveil'

# Load common encodings
"\255".force_encoding('ISO8859-1').encode('UTF-8')
''.force_encoding('UTF-16LE')
''.force_encoding('UTF-16BE')

class Unicorn::HttpServer
  # The file name in which to store request information.
  # The /var/www/request-error-data/$app_name folder is accessable
  # only to the user of the application.
  def request_filename(pid)
    "/var/www/request-error-data/#{Unicorn.app_name}/#{pid}.txt"
  end

  unless ENV['UNICORN_WORKER']
    alias _original_spawn_missing_workers spawn_missing_workers

    # This is the master process, set the master pledge before spawning
    # workers, because spawning workers will also need to be done at runtime.
    def spawn_missing_workers
      if pledge = Unicorn.master_pledge
        Unicorn.master_pledge = nil
        Pledge.pledge(pledge, Unicorn.master_execpledge)
      end
      _original_spawn_missing_workers
    end
  end

  # Override the process name for the unicorn processes, both master and
  # worker.  This gives all applications a consistent prefix, which can
  # be used to pkill processes by name instead of using pidfiles.
  def proc_name(tag)
    ctx = self.class::START_CTX
    $0 = ["unicorn-#{Unicorn.app_name}-#{tag}"].concat(ctx[:argv]).join(' ')
  end
end

#
class << Unicorn
  # The Unicorn::HttpServer instance in use.  This is only set once when the
  # unicorn server is started, before forking the first worker.
  attr_accessor :server

  # The name of the application.  All applications are given unique names.
  # This name is used to construct the log file, listening socket, and process
  # name.
  attr_accessor :app_name

  # A File instance open for writing.  This is unique per worker process.
  # Workers should write all new requests to this file before handling the
  # request.  If a worker process crashes, the master process will send an
  # notification email with the previously logged request information,
  # to enable programmers to debug and fix the issue.
  attr_accessor :request_logger

  # The pledge string to use for the master process's spawned processes by default.
  attr_accessor :master_execpledge

  # The pledge string to use for the master process.
  attr_accessor :master_pledge

  # The pledge string to use for worker processes.
  attr_accessor :pledge

  # The hash of unveil paths to use.
  attr_accessor :unveil

  # The hash of additional unveil paths to use if in the development environment.
  attr_accessor :dev_unveil

  # The address to email for crash and unhandled exception notifications.
  attr_accessor :email

  # Helper method to write request information to the request logger.
  # +email_message+ should be an email message including headers and body.
  # This should be called at the top of the Roda route block for the
  # application (or at some early point before processing in other web frameworks).
  def write_request(email_message)
    request_logger.seek(0, IO::SEEK_SET)
    request_logger.truncate(0)
    request_logger.syswrite(email_message)
    request_logger.fsync
  end

  # Helper method that sets up all necessary code for unveil/pledge support.
  # This should be called inside the appropriate unicorn.conf file.
  # The configurator should be self in the top level scope of the
  # unicorn.conf file, and this takes options:
  #
  # Options:
  # :app (required) :: The name of the application
  # :email : The email to notify for worker crashes
  # :pledge :: The string to use when pledging worker processes after loading the app
  # :master_pledge :: The string to use when pledging the master process before
  #                   spawning worker processes
  # :master_execpledge :: The pledge string for processes spawned by the master
  #                       process (i.e. worker processes before loading the app)
  # :unveil :: A hash of unveil paths, passed to Pledge.unveil.
  # :dev_unveil :: A hash of unveil paths to use in development, in addition
  #                to the ones in :unveil.
  def lockdown(configurator, opts)
    Unicorn.app_name = opts.fetch(:app)
    Unicorn.email = opts[:email]
    Unicorn.master_pledge = opts[:master_pledge]
    Unicorn.master_execpledge = opts[:master_execpledge]
    Unicorn.pledge = opts[:pledge]
    Unicorn.unveil = opts[:unveil]
    Unicorn.dev_unveil = opts[:dev_unveil]

    configurator.instance_exec do
      listen "/var/www/sockets/#{Unicorn.app_name}.sock"

      # Buffer all client bodies in memory.  This assumes an Nginx limit of 10MB,
      # by using 11MB this ensures that client bodies are always buffered in
      # memory, preventing file uploading causing a program crash if the
      # pledge does not allow wpath and cpath.
      client_body_buffer_size(11*1024*1024)

      # Run all worker processes with unique memory layouts
      worker_exec true

      # Only change the log path if daemonizing.
      # Otherwise, continue to log to stdout/stderr.
      if Unicorn::Configurator::RACKUP[:daemonize]
        stdout_path "/var/log/unicorn/#{Unicorn.app_name}.log"
        stderr_path "/var/log/unicorn/#{Unicorn.app_name}.log"
      end

      after_fork do |server, worker|
        server.logger.info("worker=#{worker.nr} spawned pid=#{$$}")

        # Set the request logger for the worker process after forking.
        Unicorn.request_logger = File.open(server.request_filename($$), "wb")
        Unicorn.request_logger.sync = true
      end

      if wrap_app = Unicorn.email
        require 'rack/email_exceptions'
      end

      after_worker_ready do |server, worker|
        server.logger.info("worker=#{worker.nr} ready")

        # If an notification email address is setup, wrap the entire app in
        # a middleware that will notify about any exceptions raised when
        # processing that aren't caught by other middleware.
        if wrap_app
          server.instance_exec do
            @app = Rack::EmailExceptions.new(@app, Unicorn.app_name, Unicorn.email)
          end
        end

        unveil = if Unicorn.dev_unveil && ENV['RACK_ENV'] == 'development'
          Unicorn.unveil.merge(Unicorn.dev_unveil)
        else
          Hash[Unicorn.unveil]
        end

        # Don't allow loading files in rack and mail gems if not using rubygems
        if defined?(Gem) && Gem.respond_to?(:loaded_specs)
          # Allow read access to the rack gem directory, as rack autoloads constants.
          if defined?(Rack) && Gem.loaded_specs['rack']
            unveil['rack'] = :gem
          end

          # If using the mail library, allow read access to the mail gem directory,
          # as mail autoloads constants.
          if defined?(Mail) && Gem.loaded_specs['mail']
            unveil['mail'] = :gem
          end
        end

        # Restrict access to the file system based on the specified unveil.
        Pledge.unveil(unveil)

        # Pledge after unveiling, because unveiling requires a separate pledge.
        Pledge.pledge(Unicorn.pledge)
      end

      # the last time there was a worker crash and the request information
      # file was empty.  Set by default to 10 minutes ago, so the first
      # crash will always receive an email.
      last_empty_crash = Time.now - 600

      after_worker_exit do |server, worker, status|
        m = "reaped #{status.inspect} worker=#{worker.nr rescue 'unknown'}"
        if status.success?
          server.logger.info(m)
        else
          server.logger.error(m)
        end

        # Email about worker process crashes.  This is necessary so that
        # programmers are notified about any pledge violations.  Pledge
        # violations immediately abort the process, and are bugs in the
        # application that should be fixed.  This can also catch other
        # crashes such as SIGSEGV or SIGBUS.
        file = server.request_filename(status.pid)
        if File.exist?(file)
          if !status.success? && Unicorn.email
            if File.size(file).zero?
              # If a crash happens and the request information file is empty,
              # it is generally because the crash happened during initialization,
              # in which case it will generally continue to crash in a loop until the
              # problem is fixed.  In that case, only send an email if there hasn't
              # been a similar crash in the last 5 minutes.  This rate-limits the
              # crash notification emails to 1 every 5 minutes instead of potentially
              # multiple times per second.
              if Time.now - last_empty_crash > 300
                last_empty_crash = Time.now
              else
                skip_email = true
              end
            end

            unless skip_email
              # If the request filename exists and the worker process crashed,
              # send a notification email.
              Process.waitpid(fork do
                # Load net/smtp early
                require 'net/smtp'

                # When setting the email, first get the contents of the email
                # from the request file.
                body = File.read(file)

                # Then use a restrictive pledge
                Pledge.pledge('inet prot_exec')

                # If body empty, crash happened before a request was received,
                # try to at least provide the application name in this case.
                if body.empty?
                  body = "Subject: [#{Unicorn.app_name}] Unicorn Worker Process Crash\r\n\r\nNo email content provided for app: #{Unicorn.app_name}"
                end

                # Don't verify localhost hostname, to avoid SSL errors raised in newer versions of net/smtp
                smtp_params = Net::SMTP.method(:start).parameters.include?([:key, :tls_verify]) ? {tls_verify: false, tls_hostname: 'localhost'} : {}

                # Finally send an email to localhost via SMTP.
                Net::SMTP.start('127.0.0.1', **smtp_params){|s| s.send_message(body, Unicorn.email, Unicorn.email)}
              end)
            end
          end

          # Remove any request logger file if it exists.
          File.delete(file)
        end
      end
    end
  end
end
