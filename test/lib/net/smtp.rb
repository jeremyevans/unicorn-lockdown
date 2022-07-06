module Net
  class SMTP
    class << self
      attr_reader :message

      def start(address, **)
        @address = address
        yield self
      end

      def send_message(msg, from, to)
        @message = [msg, from, to, @address]
      end
    end
  end
end
