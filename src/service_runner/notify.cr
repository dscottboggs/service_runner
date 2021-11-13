require "socket"
require "./log"

module ServiceRunner
  def self.notify
    Notify
  end

  class Notify
    # :nodoc:
    INSTANCE = Notify.new
    Log      = ::Log.for "notifier"

    {% for method in [:notify, :ready, :error, :stopping] %}
    def self.{{method.id}}(*args, **kwargs)
      INSTANCE.{{method.id}} *args, **kwargs
    end
    {% end %}

    def self.status=(status)
      INSTANCE.status = status
    end

    def initialize
      socket_path = ENV["NOTIFY_SOCKET"]? || begin
        Log.fatal { "$NOTIFY_SOCKET must be set (this application is designed to by run by a systemd unit of Type=notify)" }
        exit 1
      end
      socket_path = "\0#{socket_path[1..]}" if socket_path[0] == '@'
      @socket = UNIXSocket.new socket_path, :dgram
    end

    private def notify(message : String)
      Log.info &.emit "sending systemd message", content: message
      @socket.puts message
    end

    def ready
      notify "READY=1"
    end

    def status=(status)
      notify "STATUS=#{status}"
    end

    def error(message, status : Errno = Errno::EINVAL)
      error message, status.value
    end

    def error(message, status : Int32)
      notify "STATUS=#{message}"
      notify "ERRNO=#{status}"
    end

    def stopping
      notify "STOPPING=1"
    end
  end
end
