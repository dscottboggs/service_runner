require "yaml"
require "json"
require "uri"
require "http/headers"

module ServiceRunner
  module Monitoring
    BASE_DIR = Path["/web-services"]
    Log      = ::Log.for "service_runner.monitoring"

    struct Config
      include YAML::Serializable
      include JSON::Serializable

      def initialize; end

      # set to false to cancel a regular check for a container with the same name
      # as the service, or a string representing the name of the service to check
      # for
      property check_container_present : String | Bool { true }
      # a list of HTTP queries to check
      property check_http : Array(HTTPResult) { [] of HTTPResult }
      # a list of commands to run inside the container as a check
      property check_internal_command : Array(InternalCommand) { [] of InternalCommand }
      # list of shell commands to check
      property check_shell_command : Array(ShellResult) { [] of ShellResult }
      # list of commands to execute with specific arguments. Shell substitution
      # is not available in this mode.
      property check_exe : Array(ExecutionResult) { [] of ExecutionResult }

      property public_network_name : String { "public" }

      def self.from_service_config(name : String)
        File.open ENV["tech.tams.monitoring_config"]? || BASE_DIR / "monitor-config" / "#{name}.yml" do |file|
          from_yaml file
        end
      end

      abstract struct Result
        include YAML::Serializable
        include JSON::Serializable

        # how frequently to run the given check.
        property frequency : Int32 = 60
      end

      struct HTTPResult < Result
        property host : String?
        property path : String
        property port : UInt16?
        property method : String { "GET" }
        property query_parameters : Hash(String, Array(String))?
        property headers : Hash(String, Array(String))?
        property body : String?
        property expected : HTTPResult::Expected = HTTPResult::Expected.new
        record Expected, body : String? = nil, body_file : String? = nil {
          include JSON::Serializable
          include YAML::Serializable

          property status : Int32 { 200 }

          def initialize; end

          def body_text
            body || body_file.try &->File.read(String)
          end
        }
      end

      record ExpectedCommandResult,
        status = 0, stdout : String? = nil,
        stderr : String? = nil {
        include JSON::Serializable
        include YAML::Serializable
      }

      struct InternalCommand < Result
        property shell_command : String
        property environment : Process::Env
        property stdin_string : String? = nil
        property stdin_file : String? = nil
        property workdir : String? = nil
        property expected : ExpectedCommandResult = ExpectedCommandResult.new
      end

      struct ShellResult < Result
        property shell_command : String
        property environment : Process::Env
        property stdin_string : String? = nil
        property stdin_file : String? = nil
        property workdir : String? = nil
        property expected : ExpectedCommandResult = ExpectedCommandResult.new
      end

      struct ExecutionResult < Result
        include JSON::Serializable
        include YAML::Serializable
        property exe : String
        property arguments : Array(String)
        property environment : Process::Env
        property stdin_string : String? = nil
        property stdin_file : String? = nil
        property workdir : String? = nil
        property expected : ExpectedCommandResult = ExpectedCommandResult.new
      end
    end
  end
end
