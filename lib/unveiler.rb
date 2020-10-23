require 'pledge'

# Loading single_byte encoding
"\255".force_encoding('ISO8859-1').encode('UTF-8')

# Load encodings
''.force_encoding('UTF-16LE')
''.force_encoding('UTF-16BE')

# Don't run external diff program for failures
Minitest::Assertions.diff = false if defined?(Minitest::Assertions)

# Unveiler allows for testing programs using pledge and unveil.
module Unveiler
  # Use Pledge.unveil to limit access to the file system based on the
  # +unveil+ argument.  Then pledge the process with the given +pledge+
  # permissions.  This will automatically unveil the rack and mail gems
  # if they are loaded.
  def self.pledge_and_unveil(pledge, unveil)
    require 'unveil'

    unveil = Hash[unveil]

    if defined?(Gem) && Gem.respond_to?(:loaded_specs)
      if defined?(Rack) && Gem.loaded_specs['rack']
        unveil['rack'] = :gem
      end
      if defined?(Mail) && Gem.loaded_specs['mail']
        unveil['mail'] = :gem
      end
    end

    Pledge.unveil(unveil)

    unless defined?(SimpleCov)
      # If running coverage tests, don't run pledged as coverage
      # testing can require many additional permissions.
      Pledge.pledge(pledge)
    end
  end
end
