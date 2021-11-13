require "yaml"
require "json"
require "http/client"
require "./config"

module ServiceRunner::Monitoring
  struct Monitor
    struct DoneSignal; end

    TICK = 1.second

    property service, config
    property concurrent_jobs : Atomic(Int32) = Atomic.new 0
    property job_count : Atomic(UInt64) = Atomic.new 0u64

    def seconds_today
      (Time.local - Time.local.at_beginning_of_day).total_seconds.floor.to_i
    end

    def initialize(@service : Service, @config : Monitoring::Config)
    end

    def self.my(service)
      new(service, Monitoring::Config.from_service_config service.name).runloop
    end

    protected def runloop
      until service.stopping?
        job_count.add 1
        done = Channel(DoneSignal).new
        start = Time.monotonic

        spawn run_checks start, done, job_count.get

        select
        when done.receive
          duration = Time.monotonic - start
          # sleep for some approximately consistent amount of time.
          sleep TICK - duration
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
        Log.error &.emit <<-HERE, duration: duration.total_seconds, configured_tick_length: TICK.total_seconds, currently_running_concurrent_jobs: concurrent_jobs.get
            checks took too long. recommend reducing possible runtime of
            configured checks, or increasing tick length to avoid the
            possibility of DENIAL OF SERVICE due to checks running concurrently
            and building up.
          HERE
      else
        done.send DoneSignal.new
      end
      concurrent_jobs.sub 1
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
        if body = conf.expected.body
          if body == result.body?
            Log.info &.emit "http check ok", config: conf.to_json
          else
            Log.error &.emit "http check failed", config: conf.to_json,
              status_code: result.status_code,
              body: result.body?
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
      `docker inspect #{service.name} --format "{{.NetworkSettings.Networks.web.IPAddress}}"`
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
