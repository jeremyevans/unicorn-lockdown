require_relative 'test_helper'
require 'roda'

require_relative '../lib/roda/plugins/pg_disconnect'

PG = Sequel = Module.new
Sequel::DatabaseDisconnectError = Sequel::DatabaseConnectionError = PG::ConnectionBad = Class.new(StandardError)

describe Roda::RodaPlugins::PgDisconnect do
  before do
    @quit = []
    @handler = Signal.trap('QUIT'){@quit << true}
  end
  after do
    @handler = Signal.trap('QUIT', @handler)
  end

  it  "should should send QUIT signal if exception is raised" do
    app = Class.new(Roda)
    app.plugin :pg_disconnect
    app.route{raise}
    proc{app.call({})}.must_raise RuntimeError
    @quit.must_be_empty

    app.route{raise PG::ConnectionBad}
    proc{app.call({})}.must_raise PG::ConnectionBad
    @quit.must_equal [true]
  end

  it  "should raise error if trying to load plugin after error_handler" do
    app = Class.new(Roda)
    app.plugin :error_handler
    proc{app.plugin :pg_disconnect}.must_raise Roda::RodaError
  end
end
