require "yaml"
require "../monitoring/config"

class ServiceRunner::Service
  class Config
    include YAML::Serializable
    property image : String,
      name : String,
      container_create_args : Array(String),
      service_args : Array(String)?
    property monitor : Monitoring::Config { Monitoring::Config.new }
  end
end
