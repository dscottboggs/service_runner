require "yaml"

module ServiceRunner
  class_property config : Config do
    filepath = if loc = ENV["service_runner_global_config"]?
                 loc
                 # elsif File.exists? loc = XDG::CONFIG::HOME / "service_runner" / "global_config.yaml"
                 #   loc
               else
                 dirs : Array(Path) = XDG::CONFIG::DIRS
                 dirs << Path["/etc"]
                 dirs.each.select do |dir|
                   File.exists? dir / "service_runner" / "global_config.yaml"
                 end.first do
                   # block invoked on failure of #first: no config file found
                   STDERR.puts "error, no configuration file found in #{XDG::CONFIG::DIRS}"
                   exit 1
                 end / "service_runner" / "global_config.yaml"
               end
    File.open filepath, &->Config.from_yaml(File)
  end

  class Config
    include YAML::Serializable

    {% unless flag? :no_influxdb %}
      class InfluxDB
        include YAML::Serializable
        property token : String
        property location : String? { "http://localhost:8086/" }
        property org : String { System.hostname }
        property bucket : String { "monitoring" }
      end

      property influxdb : InfluxDB
    {% end %}
  end
end
