require "./docker"
require "./notify"
require "./monitor"
require "./log"

module ServiceRunner
  class Service
    property name : String, image : String

    def initialize(name = nil, image = nil)
      @name = name || ENV["service_name"]? || fatal "service name must be specified as $service_name"
      @image = image || ENV["service_image"]? || fatal "service image name must be specified as $service_image"
    end

    record Done
    DockerLogs = ::Log.for "docker-logs.stdout"
    DockerErr  = ::Log.for "docker-logs.stderr"
    Log        = ::Log.for "service-runner"
    property docker : Docker { Docker.new image, name }
    getter? stopping : Bool = false # belt and suspenders but w/e
    getter done_stopping : Channel(Done) = Channel(Done).new

    def start(create_args = ARGV)
      notify.status = "stopping #{name}"
      docker.stop?
      notify.status = "removing #{name}"
      docker.remove?
      notify.status = "pulling image #{image}"
      docker.pull || exit 1
      notify.status = "creating container"
      docker.create create_args do |status|
        notify.error "docker create exited with code #{status.exit_status}"
      end
      docker.start || exit 2
      Signal::TERM.trap do
        stop
      end
      notify.ready
      Monitoring::Monitor.my self
    end

    def stop
      Log.warn &.emit "stopping service", service: name
      @stopping = true
      notify.stopping
      notify.status = "stopping #{name}"
      docker.stop
      notify.status = "removing #{name}"
      docker.remove?
      done_stopping.receive
      exit 0
    end

    def pipe_logs
      process = Process.new "docker",
        input: :close,
        output: :pipe,
        error: :pipe,
        args: ["logs", "-f", name]
      pipe_logs process, process.output, DockerLogs
      pipe_logs process, process.output, DockerErr
    end

    def pipe_logs(process, io, logchannel)
      spawn do # log stdout
        until process.terminated? || io.closed? || stopping?
          if line = io.gets
            logchannel.info &.emit line: line
          end
        end
        Log.debug { "stopping log pipe" }
        # whichever signal caused the loop to end (process term or io closed),
        # the other one will need cleaned up. If @stopping is what breaks the
        # loop, they'll both need cleaned up.
        if process.exists?
          process.terminate
          Log.debug &.emit "finished docker logs command", status: process.wait.exit_status
        end
        io.close unless io.closed?
        Log.debug { "done stopping log pipe, sending signal" }
        done_stopping.send Done.new
      end
    end

    def self.start
      new.start
    end

    def notify
      Notify
    end

    def fatal(msg)
      Log.fatal { msg }
      exit 1
    end
  end
end
