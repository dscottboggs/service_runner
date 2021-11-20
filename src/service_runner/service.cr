require "xdg"
require "./docker"
require "./notify"
require "./monitor"
require "./log"
require "./service/config"

module ServiceRunner
  class Service
    property config : Config

    def initialize(config_file_location = ARGV[0]?)
      config_file_location ||= ENV["service_config"]? || fatal "no service config received"
      @config = File.open config_file_location, &->Config.from_yaml(File)
    end

    delegate :image, :name, to: @config
    record Done
    DockerLogs = ::Log.for "service_runner.docker_logs.stdout"
    DockerErr  = ::Log.for "service_runner.docker_logs.stderr"
    Log        = ::Log.for "service_runner.service"
    property docker : Docker { Docker.new self }
    # This seemed to be belt and suspenders but turned out to be crucial.
    getter? stopping : Bool = false
    # a signal for the logging thread to let the stopping thread (spawned by
    # the signal trap) that the logging thread is done cleaning up.
    getter done_stopping : Channel(Done) = Channel(Done).new

    def start
      notify.status = "stopping #{name}"
      docker.stop if docker.container_running?
      notify.status = "removing #{name}"
      docker.rm if docker.container_exists?
      notify.status = "pulling image #{image}"
      docker.pull || fatal "failed to pull image '#{image}'"
      notify.status = "creating container"
      docker.create do |status|
        fatal "docker create exited with code #{status.exit_status}"
      end
      docker.start || fatal "failed to start container"
      Signal::TERM.trap do
        stop
      end
      notify.ready
      pipe_logs
      Monitoring::Monitor.my self
    end

    def stop
      Log.warn &.emit "stopping service", service: name
      @stopping = true
      notify.stopping
      notify.status = "stopping #{name}"
      docker.stop
      notify.status = "removing #{name}"
      docker.rm?
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
      pipe_logs process, process.error, DockerErr
    end

    def pipe_logs(process, io, logchannel)
      spawn do # log stdout
        until process.terminated? || io.closed? || stopping?
          if line = io.gets
            logchannel.info &.emit line: line, service: name
          end
          Fiber.yield
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
      notify.error msg
      exit 1
    end
  end
end
