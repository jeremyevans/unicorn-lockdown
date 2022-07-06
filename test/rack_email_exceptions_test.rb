require_relative 'test_helper'
require_relative '../lib/rack/email_exceptions'
require_relative 'stub_net_smtp'

describe Rack::EmailExceptions do
  it  "should email for exceptions raised by app" do
    app = Rack::EmailExceptions.new(proc{|env| raise "bad"}, 'PREFIX', 'foo@example.com')
    proc{app.call({'test_key'=>'test_value'})}.must_raise(RuntimeError)
    msg, from, to, address = Net::SMTP.message
    address.must_equal '127.0.0.1'
    from.must_equal 'foo@example.com'
    to.must_equal 'foo@example.com'
    msg.must_match(/From.*To.*Subject.*Error.*Backtrace.*ENV.*"test_key" => "test_value"/m)
  end
end
