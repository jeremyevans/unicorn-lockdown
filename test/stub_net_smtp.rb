# Stub out Net::SMTP
Net.send(:remove_const, :SMTP)
require_relative 'lib/net/smtp'
