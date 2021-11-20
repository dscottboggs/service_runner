module ServiceRunner::Monitoring
  module Check::HTTP
    include Check

    def run(config) : Nil
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
  end
end
