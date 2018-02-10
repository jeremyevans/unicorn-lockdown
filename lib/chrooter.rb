require 'etc'
require 'pledge'

# Loading single_byte encoding
"\255".force_encoding('ISO8859-1').encode('UTF-8')

# Load encodings
''.force_encoding('UTF-16LE')
''.force_encoding('UTF-16BE')

# Don't run external diff program for failures
Minitest::Assertions.diff = false

if defined?(SimpleCov) && Process.euid == 0
  # Prevent coverage testing in chroot mode. Chroot vs
  # non-chroot should not matter in terms of lines covered,
  # and running coverage tests in chroot mode will probable fail
  # when it comes time to write the coverage files.
  SimpleCov.at_exit{}
  raise "cannot run coverage testing in chroot mode"
end

# Chrooter allows for testing programs in both chroot and non
# chroot modes.
module Chrooter
  # If the current user is the super user, change to the given
  # user/group, chroot to the given directory, and pledge
  # the process with the given permissions (if given).
  #
  # If the current user is not the super user, freeze
  # $LOADED_FEATURES to more easily detect problems with
  # autoloaded constants, and just pledge the process with the
  # given permissions (if given).
  #
  # This will reference common autoloaded constants in the
  # rack and mail libraries if they are defined.  Other
  # autoloaded constants should be referenced before calling
  # this method.
  #
  # In general this should be called inside an at_exit block
  # after loading minitest/autorun, so it will run after all
  # specs are loaded, but before running specs.
  def self.chroot(user, pledge=nil, group=user, dir=Dir.pwd)
    # Work around autoload issues in libraries.
    # autoload is problematic when chrooting because if the
    # constant is not referenced before chrooting, an
    # exception is raised if the constant is raised
    # after chrooting.
    #
    # The constants listed here are the autoloaded constants
    # known to be used by any applications.  This list
    # may need to be updated when libraries are upgraded
    # and add new constants, or when applications start
    # using new features.
    if defined?(Rack)
      Rack::MockRequest if defined?(Rack::MockRequest)
      Rack::Auth::Digest::Params if defined?(Rack::Auth::Digest::Params)
      if defined?(Rack::Multipart)
        Rack::Multipart
        Rack::Multipart::Parser
        Rack::Multipart::Generator
        Rack::Multipart::UploadedFile
      end
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
    end

    if Process.euid == 0
      uid = Etc.getpwnam(user).uid
      gid = Etc.getgrnam(group).gid
      if Process.egid != gid
        Process.initgroups(user, gid)
        Process::GID.change_privilege(gid)
      end
      Dir.chroot(dir)
      Dir.chdir('/')
      Process.euid != uid and Process::UID.change_privilege(uid)
      puts "Chrooted to #{dir}, running as user #{user}"
    else
      # Load minitest plugins before freezing loaded features,
      # so they don't break.
      Minitest.load_plugins

      # Emulate chroot not working by freezing $LOADED_FEATURES
      # This allows to more easily catch bugs that only occur
      # when chrooted, such as referencing an autoloaded constant
      # that wasn't loaded before the chroot.
      $LOADED_FEATURES.freeze
    end

    unless defined?(SimpleCov)
      if pledge
        # If running coverage tests, don't run pledged as coverage
        # testing can require many additional permissions.
        Pledge.pledge(pledge)
      end
    end

    nil
  end
end
