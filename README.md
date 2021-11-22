# service_runner
A shim layer between systemd service units of `Type=notify` and docker
containers, with built-in health-checks and monitoring.

## Installation
Download the binary from the releases page, or compile it from source, then
place it anywhere on your system. Since systemd requires you specify the full
path to the executable anyway, it doesn't much matter where or if it's even in
your `$PATH`.

### Compiling from source
Compiling with static linking requires docker on systems without musl libc. If
your system uses musl libc, docker won't be used. Root privileges through `sudo` are also required. You're encouraged to review the Makefile.

```shell
$ git clone [git url here?] --depth 1
$ cd service_runner
$ make prodbuild install
```

#### Building with dynamic linking
If you can't use docker or native musl libc, and you don't require static
linking (linked libraries must be the same version on the machine you're
building on and the machine you're running it on), you can run
`make dynamic-prodbuild` instead.

#### Building without influxdb
If you don't need InfluxDB, you can build the application without that by adding `buildOpts=-Dno_influxdb` to the `make` command. For example:

```shell
$ make prodbuild build_opts=-Dno_influxdb
```

### Installing from prebuilt binaries.
There are also pre-built binaries hosted by github. You can download the latest from
the web page with your browser and place it in `/usr/local/bin/service_runner`,
or run this command.

```shell
# curl -L -o/usr/local/bin/service_runner $(
  curl -H "Accept: application/vnd.github.v3+json"\
    https://api.github.com/repos/dscottboggs/service_runner/releases/latest \
  | jq -r '.assets | .[] | select(.name="service_runner") | .browser_download_url'
)
```
If you don't need InfluxDB, use this command instead:
```shell
# curl -L -o/usr/local/bin/service_runner $(
  curl -H "Accept: application/vnd.github.v3+json"\
    https://api.github.com/repos/dscottboggs/service_runner/releases/latest \
  | jq -r '.assets | .[] | select(.name="service_runner-no_influxdb") | .browser_download_url'
)
```

This script needs to be run from a SystemD service. Write a service file or
download it from the repository.
```shell
$ curl -L https://raw.githubusercontent.com/dscottboggs/service_runner/master/service_runner%40.service | sudo tee /etc/systemd/system/service_runner@.service
# systemctl daemon-reload
```

## Usage
Before we start, it's good practice to have a no-shell non-root user to run
services as.

```shell
# useradd --home-dir /server-acct --shell /bin/nologin --uid=(some free UID) \
          --user-group --groups=docker server-acct
```

I created a ZFS dataset dedicated to this:

```shell
# zfs create pool/srv
# zfs set mountpoint=/srv
# mkdir /srv/config
# chown -R server-acct:server-acct /srv
```

Create a yaml config file for your service:

```shell
$ sudoedit -u server-acct /srv/config/crystal-docs.yaml
```

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

Now you're ready to enable the service. This will start up when you turn on the
machine from now on, assuming it succeeds.

```shell
# systemctl enable --now service_runner@crystal-docs
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

In order to uninstall the service, just run

```
# systemctl disable --now service_runner@crystal-docs
```

## Uninstallation
If you installed from source, uninstallation is as simple as

```shell
$ make uninstall
```

from the repository directory. You will be prompted for root privileges.

If you installed from pre-built binaries and don't have the repository cloned
to your system, you can instead run the commands the makefile would run:

```shell
# systemctl disable --now service_runner@*.service
# rm /etc/systemd/system/service_runner@.service
# rm /usr/local/bin/service_runner
```

## Development
PRs are welcome. Rather not have the complexity get too crazy and have the project be hard to comprehend, but I can already see some holes in functionality that might need filled in. This is not trying to replace Kubernetes or something like that, just provide glue to allow containerized services to be managed by systemd.

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
- If InfluxDB is enabled, it loads the configuration on start from `/etc/service_runner/config.yaml`, and connects to InfluxDB. Until a successful connection is made, all log entries are loaded into an `IO::MemoryBackend`, then once the connection is made, the logger is reconfigured to use InfluxDB and all prior log messages are dumped to the InfluxDB backend.

### See also
A logging [ backend for InfluxDB ](https://github.com/dscottboggs/crystal-log-influx_backend) was created for this project.

## Contributing

1. Fork it (<https://github.com/dscottboggs/service_runner/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [D. Scott Boggs](https://github.com/dscottboggs) - creator and maintainer
