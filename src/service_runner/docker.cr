require "./notify"

module ServiceRunner
  record Docker, image : String, name : String do
    Log = ::Log.for "docker-command-runner"

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

    {% for name in %w[start stop remove] %}
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

    def create(args : Array(String))
      runcmd build_create_args args
    end

    def create(args : Array(String), &on_error : Process::Status -> T) : Bool | T forall T
      args = build_create_args args
      runcmd args, &on_error
    end

    def create(*args : String, &on_error : Process::Status -> T) : Bool | T forall T
      create args.to_a, &on_error
    end

    def create(*args : String)
      create args.to_a
    end

    private def build_create_args(args : Array(String)) : Array(String)
      ((%w[create --name] << name) + args) << image
    end

    def image_id : String
      `docker images --quiet --filter reference=#{image}`
    end

    def container_id
      `docker ps --quiet --filter name=#{name}`
    end

    def container_exists? : Bool
      !container_id.empty?
    end

    def image_exists?
      !image_id.empty?
    end

    def notify
      Notify
    end
  end
end
