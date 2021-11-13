require "log"
require "json"
require "./json_formatter"

module ServiceRunner
  Log = ::Log.for "logging"

  ::Log.setup do |log_settings|
    stdout = ::Log::IOBackend.new formatter: JSONFormatter
    stderr = ::Log::IOBackend.new STDERR, formatter: JSONFormatter
    log_settings.bind source: "*", level: :debug, backend: stdout
    log_settings.bind source: "docker-logs.stderr",
      level: :debug, backend: stderr
  end
end
