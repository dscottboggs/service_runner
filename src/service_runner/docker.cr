require "./notify"

module ServiceRunner
  record Docker, service : Service do
    Log = ::Log.for "service_runner.docker_command_runner"

    delegate :name, :image, to: @service

    def runcmd(*args : String, cmd = "docker")
      args = args.to_a
      Log.info &.emit "running command", command: cmd, arguments: args
      runcmd(args, cmd: cmd) { |s| yield s }
    end

    def runcmd(args : Array(String), cmd = "docker")
      status = Process.run cmd, args.to_a
      if status.success?
        true
      else
        yield status
      end
    end

    def runcmd(*args : String, cmd = "docker")
      runcmd args.to_a, cmd: cmd
    end

    def runcmd(args : Array(String), cmd = "docker")
      runcmd args, cmd: cmd, &.success?
    end

    {% for name in %w[start stop rm] %}
      def {{name.id}}
        runcmd("{{name.id}}", name) { |status| yield status }
      end

      def {{name.id}}?
        runcmd "{{name.id}}", name
      end
      def {{name.id}}
        runcmd "{{name.id}}", name do |status|
          notify.error "failed to {{name.id}} #{name}. `docker {{name.id}}` exited with status #{status.exit_status}"
          false
        end
      end
    {% end %}

    def pull
      runcmd("pull", image) { |status| yield status }
    end

    def pull?
      runcmd "pull", image
    end

    def pull
      runcmd("pull", image) do |status|
        notify.error "failed to pull #{image}. `docker pull` exited with status #{status.exit_status}"
        false
      end
    end

    def create
      runcmd build_create_args args
    end

    def create(&on_error : Process::Status -> T) : Bool | T forall T
      args = build_create_args
      runcmd args, &on_error
    end

    private def build_create_args : Array(String)
      pargs = %w[create --name]
      pargs << name
      pargs += service.config.container_create_args
      pargs << image
      if service_args = service.config.service_args
        pargs += service_args
      end
      pargs
    end

    def image_id : String
      `docker images --quiet --filter reference=#{image}`
    end

    def container_id
      `docker ps -a --quiet --filter name=#{name}`
    end

    def container_exists? : Bool
      !container_id.empty?
    end

    def container_running?
      !`docker ps --quiet --filter name=#{name}`.empty?
    end

    def image_exists?
      !image_id.empty?
    end

    def notify
      Notify
    end
  end
end
