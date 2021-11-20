require "log"
require "json"

require "log-influx_backend"

require "./log/json_formatter"
require "./config"

module ServiceRunner
  Log                 = ::Log.for "service_runner"
  BEFORE_DATABASE_LOG = ::Log::MemoryBackend.new

  setup_logs

  def self.setup_logs(with_influx = false)
    ::Log.setup do |log_settings|
      stdout = ::Log::IOBackend.new formatter: JSONFormatter
      stderr = ::Log::IOBackend.new STDERR, formatter: JSONFormatter
      log_settings.bind source: "service_runner.*", level: :info, backend: stdout
      log_settings.bind source: "service_runner.docker_logs.stdout",
        level: :debug, backend: stdout
      log_settings.bind source: "service_runner.docker_logs.stderr",
        level: :debug, backend: stderr
      log_settings.bind source: "service_runner.monitoring.*", level: :warn, backend: stdout
      if with_influx
        influx = ::Log::InfluxBackend.new config.influxdb.token,
          config.influxdb.org, config.influxdb.bucket, config.influxdb.location
        BEFORE_DATABASE_LOG.close
        BEFORE_DATABASE_LOG.entries.each { |entry| influx.dispatch entry }
        BEFORE_DATABASE_LOG.entries.clear
        log_settings.bind source: "service_runner.*", level: :debug, backend: influx
      else
        log_settings.bind source: "service_runner.*", level: :debug, backend: BEFORE_DATABASE_LOG
        spawn do
          wait_for_http_connection
          setup_logs with_influx: true
        end
      end
    end
  end

  def self.wait_for_http_connection
    loop do
      Log.debug { "waiting for connection to be up" }
      begin
        if HTTP::Client.get("#{config.influxdb.location}/ping").success?
          Log.trace &.emit "successfully connected to #{config.influxdb.location}"
          return
        else
          Log.debug &.emit "connection to #{config.influxdb.location} received error response"
          sleep 1
        end
      rescue exception : Socket::ConnectError | IO::Error
        Log.debug &.emit "InfluxDB service is not yet up", location: config.influxdb.location
        sleep 1
      end
    end
  ensure
    Log.debug { "connected to influxdb" }
  end
end
