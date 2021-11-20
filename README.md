# service_runner
A shim layer between systemd service units of `Type=notify` and docker
containers, with built-in health-checks and monitoring.

## Installation
Download the binary from the releases page, or compile it from source, then
place it anywhere on your system. Since systemd requires you specify the full
path to the executable anyway, it doesn't much matter where or if it's even in
your `$PATH`.

### Compiling from source
```
git clone [git url here?] --depth 1
cd service_runner
docker run --user=$(id -u) --workdir=/project -v $(pwd):/project crystallang/crystal:latest-alpine shards build --static --release --production -Dpreview_mt
```

## Usage
Create a yaml config file for your service:

```yaml
name: crystal-docs
image: nginx
container_create_args:
  - --volume
  - /usr/share/doc/crystal/api:/usr/share/nginx/html:ro

# monitor key is optional. Default is to check every 5 cycles whether the
# container exists.
monitor:
  check_http:
    - path: /index.html
      expected:
        body_file: /usr/share/doc/crystal/api/index.html
      frequency: 30 # every 30 ticks. Required for all checks!
```

Say, for example, I've saved that as /web-services/config/crystal-docs.yaml.
Then, create a systemd service of `Type=notify` like so:

```ini
[Unit]
Description=Host the Crystal API docs.
Requires=docker.service
After=docker.service

[Service]
Type=notify
ExecStart=/path/to/service_runner /web-services/config/%N.yaml

[Install]
WantedBy=multi-user.target
```

And save *that* at `/etc/systemd/system/crystal-docs.service` (or better yet,
save that file to a version-controlled directory and create a symlink to that
location). Execute

```
# systemctl daemon-reload
# systemctl enable --now crystal-docs
```

If the container fails to pull, build, or start, the service will fail.
Otherwise, the service will succeed. Either way, systemd will attempt to load
your service on boot from now on, and JSON-formatted structured logs are stored
using systemd's journalling system and can be accessed through `journalctl` and
filtered with `jq`. For example,

```
journalctl -fexu crystal-docs --output cat |
    grep '{' |
    jq 'select(.source != "monitoring")'
```

I plan to also add influxdb as a logging sink so querying and observing that
data will be simpler soon.

In order to uninstall the service, just run

```
# systemctl disable --now crystal-docs
```

## Development
PRs are welcome. Rather not have the complexity get too crazy and have the project be hard to comprehend, but I can already see some holes in functionality that might need filled in. This is not trying to replace kubernetes or something like that, just provide glue to allow containerized services to be managed by systemd.

### How it works

- When the service runner is launched, it loads the config (duh), then calls
`ServiceRunner::Service#start`.
- Once the image is pulled and ready, a fiber is spawned to pipe
the docker logs output into stdout so that it's maintained by journalctl.
- Then, a monitoring loop is entered at `ServiceRunner::Monitor#runloop`. This
loop does its best to iterate approximately once a second. If all monitoring
checks take longer than 1 second, a warning will be issued.
- When systemd tries to shutdown the service, it sends `Signal::TERM` to the
service. This is trapped in `Service#start` to call `Service#stop`. When stop is called,
  - a sentinel `@stopping` value is set to true. After this is set to true,
    - on the next monitoring "tick", monitoring is stopped and resources are
    cleaned up.
    - After the current read from the docker logs is finished, log piping is
    shut down and resources are cleaned up.
  - While those shutdown procedures are ongoing, the container is stopped and
  removed.
  - the process exits, indicating successful shutdown to systemd.

## Contributing

1. Fork it (<https://github.com/dscottboggs/service_runner/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [D. Scott Boggs](https://github.com/dscottboggs) - creator and maintainer
