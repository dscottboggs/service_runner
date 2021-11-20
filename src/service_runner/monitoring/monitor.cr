require "yaml"
require "json"
require "http/client"

require "../log"

# require "./config"

module ServiceRunner::Monitoring
  struct Monitor
    Log = ::Log.for "service_runner.monitoring.monitor"

    struct DoneSignal; end

    TICK = 1.second

    property service : Service
    property concurrent_jobs : Atomic(Int32) = Atomic.new 0
    # 2^64 seconds at 1 second tick is 584 trillion years. 2^32 is 136 years
    property job_count : Atomic(UInt32) = Atomic.new 0u32

    def seconds_today
      (Time.local - Time.local.at_beginning_of_day)
        .total_seconds
        .floor
        .to_i
    end

    def initialize(@service : Service)
    end

    def config
      service.config.monitor
    end

    def self.my(service)
      new(service).runloop
    end

    protected def runloop
      puts "starting monitoring"
      Log.debug { "starting monitoring" }

      until service.stopping?
        job_count.add 1
        done = Channel(Exception | DoneSignal).new
        start = Time.monotonic

        Fiber.yield
        spawn run_checks start, done, job_count.get

        select
        when signal = done.receive
          case signal
          in DoneSignal
            Fiber.yield
            duration = Time.monotonic - start
            # sleep for some approximately consistent amount of time.
            Log.debug &.emit "checks completed", duration: duration.to_s
            sleep TICK - duration
          in Exception
            Log.error exception: signal, &.emit "error running monitoring check", service: service.name
          end
        when timeout TICK
          done.close
        end
      end
    end

    def run_checks(start, done, job_count)
      concurrent_jobs.add 1
      check_container_present if (job_count % 5) == 0
      {% for kind in %w[http internal_command shell_command exe] %}
      config.check_{{kind.id}}.each do |check|
        check_{{kind.id}} check if (job_count % check.frequency) == 0
      end
      {% end %}
      if done.closed?
        duration = Time.monotonic - start
        Log.warn &.emit <<-HERE, duration: duration.total_seconds, configured_tick_length: TICK.total_seconds, currently_running_concurrent_jobs: concurrent_jobs.get
            checks took too long. recommend reducing possible runtime of
            configured checks, or increasing tick length to avoid the
            possibility of DENIAL OF SERVICE due to checks running concurrently
            and building up.
          HERE
      else
        done.send DoneSignal.new
      end
      concurrent_jobs.sub 1
    rescue e
      done.send e
    end

    private def check_http(conf)
      client = HTTP::Client.new host: conf.host || default_http_check_host, port: conf.port
      path = conf.path
      if query = conf.query_parameters
        path += "?#{query}"
      end
      headers = if h = conf.headers
                  HTTP::Headers.new.merge! h
                end
      result = client.exec conf.method, path, headers, conf.body
      if result.status_code == conf.expected.status
        if ebody = conf.expected.body_text
          if ebody == (abody = result.body)
            Log.info &.emit "http check ok", config: conf.to_json
          else
            Log.error &.emit "http check failed", config: conf.to_json,
              status_code: result.status_code,
              body: abody
          end
        else
          Log.info &.emit "http check ok", status: result.status_code, config: conf.to_json
        end
      else
        Log.error &.emit "http check failed", config: conf.to_json,
          status_code: result.status_code,
          body: result.body?
      end
    end

    private def default_http_check_host : String
      docker_public_network_ip = `docker inspect #{service.name} --format "{{.NetworkSettings.Networks.#{config.public_network_name}.IPAddress}}"`.strip
      if docker_public_network_ip == "<no value>"
        # todo check if service.name is resolvable
        "localhost"
      else
        docker_public_network_ip
      end
    end

    private def check_container_present
      name = config.check_container_present

      id = case name
           when String then `docker ps --quiet --filter name=#{name}`
           when false  then nil
           when true   then service.docker.container_id
           end || return

      if id.empty?
        Log.error &.emit "container is not running",
          container: {name: name}
      else
        Log.debug &.emit "container is running",
          container: {name: service.name, id: id}
      end
    end

    private def process_subprocess_result(conf, status : Process::Status, output : String, errtxt : String, kind : String)
      if (
           status.exit_status != conf.expected.status
         ) || (
           conf.expected.stdout.nil?
         ) || (
           conf.expected.stdout != output
         ) || (
           conf.expected.stderr.nil?
         ) || (
           conf.expected.stderr != errtxt
         )
        Log.error &.emit "#{kind} check failed",
          config: conf.to_json,
          status: status.to_s,
          output: output,
          stderr_output: errtxt
      else
        Log.info &.emit "#{kind} check succeeded", config: conf.to_json
      end
    end

    private def process_subprocess(conf, process, kind)
      output, errtxt = String::Builder.new, String::Builder.new
      if process.exists?
        if input = conf.stdin_string
          process.input << input
        elsif input = conf.stdin_file
          File.open input do |file|
            IO.copy file, process.input
          end
        end
        spawn IO.copy process.output, output
        spawn IO.copy process.error, errtxt
      end
      process_subprocess_result conf, process.wait, output.to_s,
        errtxt.to_s, kind
    end

    private def check_internal_command(conf)
      args = ["exec"]
      if wd = conf.workdir
        args << "--workdir" << wd
      end
      if env = conf.environment
        env.each do |k, v|
          args << "--env" << "#{k}=#{v}"
        end
      end
      Process.run "docker", args do |process|
        process_subprocess conf, process, "internal command"
      end
    end

    private def check_shell_command(conf)
      Process.run(conf.shell_command,
        shell: true,
        env: conf.environment,
        chdir: conf.workdir
      ) do |process|
        process_subprocess conf, process, "shell command"
      end
    end

    private def check_exe(conf)
      Process.run(
        command: conf.exe,
        args: conf.arguments,
        env: conf.environment,
        chdir: conf.workdir,
      ) do |process|
        process_subprocess conf, process, "executable"
      end
    end
  end
end
