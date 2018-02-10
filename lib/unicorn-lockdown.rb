# unicorn-lockdown is designed to be used with Unicorn's chroot support, and
# handles:
# * pledging the app to restrict allowed syscalls at the appropriate point
# * handling notifications of worker crashes
# * forcing loading of some common autoloaded constants
# * stripping path prefixes from the reloader in development mode

require 'pledge'

# Loading single_byte encoding
"\255".force_encoding('ISO8859-1').encode('UTF-8')

# Load encodings
''.force_encoding('UTF-16LE')
''.force_encoding('UTF-16BE')

class Unicorn::HttpServer
  # The file name in which to store request information. The
  # /var/www/requests folder is currently accessable only
  # to root.
  def request_filename(pid)
    "/var/www/requests/#{Unicorn.app_name}.#{pid}.txt"
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

  # The user and group name to run as.
  attr_accessor :user_name

  # The pledge string to use.
  attr_accessor :pledge

  # The address to email for crash and unhandled exception notifications
  attr_accessor :email

  # Helper method to write request information to the request logger.
  # +email_message+ should be an email message including headers and body.
  # This should be called at the top of the Roda route block for the
  # application.
  def write_request(email_message)
    request_logger.seek(0, IO::SEEK_SET)
    request_logger.truncate(0)
    request_logger.syswrite(email_message)
    request_logger.fsync
  end

  # Helper method that sets up all necessary code for chroot/pledge support.
  # This should be called inside the appropriate unicorn.conf file.
  # The configurator should be self in the top level scope of the
  # unicorn.conf file, and this takes options:
  #
  # Options:
  # :app :: The name of the application (required)
  # :email : The email to notify for worker crashes
  # :user :: The user/group to run as (required)
  # :pledge :: The string to use when pledging
  def lockdown(configurator, opts)
    Unicorn.app_name = opts.fetch(:app)
    Unicorn.user_name = opts.fetch(:user)
    Unicorn.email = opts[:email]
    Unicorn.pledge = opts[:pledge]

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

        # Set the request logger for the worker process after forking. The
        # process is still root here, so it can open the file in write mode.
        Unicorn.request_logger = File.open(server.request_filename($$), "wb")
        Unicorn.request_logger.sync = true
      end

      if wrap_app = Unicorn.email && ENV['RACK_ENV'] == 'production'
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

        # Before chrooting, reference all constants that use autoload
        # that are probably needed at runtime.  This must be done
        # before chrooting as attempting to load the constants after
        # chrooting will break things.
        #
        # This part is the most prone to breakage, as new versions
        # of the rack or mail libraries (or new libraries that
        # use autoload) could break things, as well as existing
        # applications using new features at runtime that were
        # not loaded at load time.
        Rack::Multipart
        Rack::Multipart::Parser
        Rack::Multipart::Generator
        Rack::Multipart::UploadedFile
        Rack::CommonLogger
        Rack::Mime
        Rack::Auth::Digest::Params
        if ENV['RACK_ENV'] == 'development'
          Rack::Lint
          Rack::ShowExceptions
        end
        if defined?(Mail)
          Mail::Address
          Mail::AddressList
          Mail::Parsers::AddressListsParser
          Mail::ContentTransferEncodingElement
          Mail::ContentDispositionElement
          Mail::MessageIdsElement
          Mail::MimeVersionElement
          Mail::OptionalField
          Mail::ContentTypeElement
          Mail::SMTP
        end

        # Strip path prefixes from the reloader.  This is only
        # really need in development mode for code reloading to work.
        pwd = Dir.pwd
        Unreloader.strip_path_prefix(pwd) if defined?(Unreloader)

        # Drop privileges.  This must be done after chrooting as
        # chrooting requires root privileges.
        worker.user(Unicorn.user_name, Unicorn.user_name, pwd)

        if Unicorn.pledge
          # Pledge after dropping privileges, because dropping
          # privileges requires a separate pledge.
          Pledge.pledge(Unicorn.pledge)
        end
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
                # Load net/smtp early, before chrooting. 
                require 'net/smtp'

                # When setting the email, first get the contents of the email
                # from the request file.
                body = File.read(file)

                # Then get information from /etc and drop group privileges
                uid = Etc.getpwnam(Unicorn.user_name).uid
                gid = Etc.getgrnam(Unicorn.user_name).gid
                if gid && Process.egid != gid
                  Process.initgroups(Unicorn.user_name, gid)
                  Process::GID.change_privilege(gid)
                end

                # Then chroot
                Dir.chroot(Dir.pwd)
                Dir.chdir('/')

                # Then drop user privileges
                Process.euid != uid and Process::UID.change_privilege(uid)

                # Then use a restrictive pledge
                Pledge.pledge('inet prot_exec')

                # If body empty, crash happened before a request was received,
                # try to at least provide the application name in this case.
                if body.empty?
                  body = "Subject: [#{Unicorn.app_name}] Unicorn Worker Process Crash\r\n\r\nNo email content provided for app: #{Unicorn.app_name}"
                end

                # Finally send an email to localhost via SMTP.
                Net::SMTP.start('127.0.0.1'){|s| s.send_message(body, Unicorn.email, Unicorn.email)}
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
