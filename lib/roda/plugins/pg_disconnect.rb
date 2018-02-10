# frozen-string-literal: true

class Roda
  module RodaPlugins
    # The pg_disconnect plugin recognizes any disconnection type errors, and kills the process
    # if those errors are received.  This is designed to be used only when using Unicorn as the
    # web server, since Unicorn will respawn a new worker process. This kills the process with
    # the QUIT signal, allowing Unicorn to finish handling the current request before exiting.
    #
    # This is designed to be used with applications that cannot connect to the database
    # after application initialization, either because they are using chroot and the database
    # connection socket is outside the chroot, or because they are using a firewall and access
    # to the database server is not allowed from the application the process is running as after
    # privileges are dropped.
    # 
    # This plugin must be loaded before the roda error_handler plugin, and it assumes usage of the
    # Sequel database library with the postgres adapter and pg driver.
    module PgDisconnect
      def self.load_dependencies(app)
        raise RodaError, "error_handler plugin already loaded" if app.method_defined?(:handle_error)
      end

      module InstanceMethods
        # When database connection is lost, kill the worker process, so a new one will be generated.
        # This is necessary because the unix socket used by the database connection is no longer available
        # once the application is chrooted.
        def call
          super
        rescue Sequel::DatabaseDisconnectError, Sequel::DatabaseConnectionError, PG::ConnectionBad
          Process.kill(:QUIT, $$)
          raise
        end
      end
    end

    register_plugin(:pg_disconnect, PgDisconnect)
  end
end

