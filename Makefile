
docker_args := --user=$(shell id -u) --workdir=/project -v $(shell dirname ${PWD})/log-influx_backend.cr:/log-influx_backend.cr -v $(PWD):/project crystallang/crystal:latest-alpine
build_opts ?=
shards_args := -Dpreview_mt --stats --progress $(build_opts)

all:	devbuild	install

/etc/systemd/system/service_runner@.service:
	sudo ln -s $(PWD)/service_runner@.service /etc/systemd/system/

bin/service_runner:
	make devbuild

prodbuild: clean
	docker run $(docker_args) \
		shards build --static --release --production $(shards_args)

devbuild:	clean
	shards build $(shards_args)
	
install:	bin/service_runner	/etc/systemd/system/service_runner@.service
	sudo cp bin/service_runner /usr/local/bin/

clean:
	-rm bin/service_runner

uninstall:		clean
	sudo systemctl disable --now service_runner@*.service
	sudo rm /etc/systemd/system/service_runner@.service

start-service:
	sudo systemctl start service_runner@monitoring.influxdb.service

stop-service:
	sudo systemctl stop service_runner@monitoring.influxdb.service