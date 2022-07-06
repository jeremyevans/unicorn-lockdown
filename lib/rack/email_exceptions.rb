require 'net/smtp'

# Rack::EmailExceptions is designed to be the first middleware loaded in production
# applications.  It rescues errors and emails about them.  It's very similar to the
# Roda email_error plugin, except that it catches errors raised outside of the
# application, such as by other middleware.  There should be very few of these types
# of errors, but it is important to be notified of them if they occur.
module Rack
  class EmailExceptions
    # Store the prefix to use in the email in addition to the next application.
    def initialize(app, prefix, email)
      @app = app
      @prefix = prefix
      @email = email
    end

    # Rescue any errors raised by calling the next application, and if there is an
    # error, email about it before reraising it.
    def call(env)
      @app.call(env)
    rescue StandardError, ScriptError => e
      body = <<END
From: #{@email}\r
To: #{@email}\r
Subject: [#{@prefix}] Unhandled Error Raised by Rack App or Middleware\r
\r
\r
Error: #{e.class}: #{e.message}

Backtrace:

#{e.backtrace.join("\n")}

ENV:

#{env.map{|k, v| "#{k.inspect} => #{v.inspect}"}.sort.join("\n")}
END

      # :nocov:
      # Don't verify localhost hostname, to avoid SSL errors raised in newer versions of net/smtp
      smtp_params = Net::SMTP.method(:start).parameters.include?([:key, :tls_verify]) ? {tls_verify: false, tls_hostname: 'localhost'} : {}
      # :nocov:

      Net::SMTP.start('127.0.0.1', **smtp_params){|s| s.send_message(body, @email, @email)}

      raise
    end
  end
end
