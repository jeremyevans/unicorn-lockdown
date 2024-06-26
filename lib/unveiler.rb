require 'pledge'
require 'unveil'

# Eagerly require strscan, lazily loaded by rack's multipart parser
require 'strscan'

# Load encodings
"\255".dup.force_encoding('ISO8859-1').encode('UTF-8')
''.dup.force_encoding('UTF-16LE')
''.dup.force_encoding('UTF-16BE')

# Don't run external diff program for failures
Minitest::Assertions.diff = false if defined?(Minitest::Assertions)

# Unveiler allows for testing programs using pledge and unveil.
module Unveiler
  # Use Pledge.unveil to limit access to the file system based on the
  # +unveil+ argument.  Then pledge the process with the given +pledge+
  # permissions.  This will automatically unveil the rack and mail gems
  # if they are loaded.
  def self.pledge_and_unveil(pledge, unveil)
    unveil = Hash[unveil]

    if defined?(Gem) && Gem.respond_to?(:loaded_specs)
      if defined?(Rack) && Gem.loaded_specs['rack']
        unveil['rack'] = :gem
      end
      if defined?(Mail) && Gem.loaded_specs['mail']
        unveil['mail'] = :gem
      end
    end

    # :nocov:
    if defined?(SimpleCov)
    # :nocov:
      # If running coverage tests, add necessary pledges and unveils for
      # coverage testing to work.
      dir = SimpleCov.coverage_dir
      unveil[dir] = 'rwc'

      # Unveil read access to the entire current directory, since any part
      # that has covered code needs to be read to generate the coverage
      # information.
      unveil['.'] = 'r'

      if defined?(Gem)
        # Unveil access to the simplecov-html gem, since that is used by default
        # to build the coverage pages.
        unveil['simplecov-html'] = :gem
      end

      # :nocov:
      # Must create directory before attempting to unveil it.
      # When running unveiler tests, the coverage directory is already created.
      Dir.mkdir(dir) unless File.directory?(dir)
      # :nocov:

      pledge = (pledge.split + %w'rpath wpath cpath flock').uniq.join(' ')
    end

    Pledge.unveil(unveil)
    Pledge.pledge(pledge)
  end
end
