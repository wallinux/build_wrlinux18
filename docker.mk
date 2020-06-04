# docker.mk

ifdef CROPS
DOCKER_DISTRO		?= crops_poky
DOCKER_DISTRO_VER	?= latest
else
DOCKER_DISTRO		?= ubuntu
DOCKER_DISTRO_VER	?= 18_04
endif
DOCKER_DT		?= $(DOCKER_DISTRO)-$(DOCKER_DISTRO_VER)
DOCKER_BASE		?= $(shell basename $(TOP))
DOCKER_CONTAINER	?= $(USER)_$(LTS_VER)_$(DOCKER_BASE)_$(DOCKER_DT)
DOCKER_IMAGE_REPO	?= $(USER)_$(LTS_VER)_$(DOCKER_DISTRO)_$(DOCKER_DISTRO_VER)
DOCKER_IMAGE_TAG	?= $(PROJECT)
DOCKER_IMAGE		?= $(DOCKER_IMAGE_REPO):$(DOCKER_IMAGE_TAG)
DOCKER_BUILDDIR		= $(OUTDIR)/build_docker_$(MACHINE)
DOCKER_HOSTNAME		?= $(LTS_VER)_$(DOCKER_DT).eprime.com
DOCKER_CONFIG		?= dockerconfig.mk
DOCKER_BUILDARGS	?=

DOCKER			?= docker
MDOCKER			?= $(Q)$(DOCKER)

define run-docker-exec
	$(MDOCKER) exec -u $(1) $(2) $(DOCKER_CONTAINER) $(3)
endef

DOCKER_CONTAINER_RUNNING = $(eval docker_container_running=$(shell $(DOCKER) inspect -f {{.State.Running}} $(DOCKER_CONTAINER)))
DOCKER_CONTAINER_ID      = $(eval docker_container_id=$(shell $(DOCKER) ps -a -q -f name=$(DOCKER_CONTAINER)))
DOCKER_IMAGE_ID          = $(eval docker_image_id=$(shell $(DOCKER) images -q $(DOCKER_IMAGE) 2> /dev/null))

ifneq ("$(wildcard $(HOME)/dockerhost)","")
DOCKERHOST		?= $(shell cat $$HOME/dockerhost)
endif

DOCKER_MOUNTS		+= -v $(WIND_INSTALL_DIR):$(WIND_INSTALL_DIR):ro
DOCKER_MOUNTS		+= -v $(PWD):$(PWD)
DOCKER_MOUNTS		+= -v $(HOME):$(HOME)

ifneq ($(V),1)
DEVNULL			?= > /dev/null
endif
#######################################################################

.PHONY:: docker.*

docker.%: export BUILDDIR=$(DOCKER_BUILDDIR)

docker.build: Dockerfile-$(LTS_VER).$(DOCKER_DT) # build docker image
	$(TRACE)
ifneq ($(V),1)
	$(eval quiet=-q)
endif
	$(MDOCKER) build $(quiet) $(DOCKER_BUILDARGS) --pull -f $< \
		-t "$(DOCKER_IMAGE)" $(TOP)

docker.prepare.ubuntu::
	$(TRACE)
	$(eval host_timezone=$(shell cat /etc/timezone))
	$(call run-docker-exec, root, , sh -c "echo $(host_timezone) > /etc/timezone" )
	$(call run-docker-exec, root, , ln -sfn /usr/share/zoneinfo/$(host_timezone) /etc/localtime )
	$(call run-docker-exec, root, , dpkg-reconfigure -f noninteractive tzdata 2> /dev/null)
	$(call run-docker-exec, root, , sh -c "ln -sfn /bin/bash /bin/sh" )

docker.prepare.crops_poky::
	$(TRACE)
	$(eval host_timezone=$(shell cat /etc/timezone))
	$(call run-docker-exec, root, , sh -c "apt install -y locales" )
	$(call run-docker-exec, root, , sh -c "DEBIAN_FRONTEND=noninteractive apt install -y tzdata" )
	$(MAKE) docker.prepare.ubuntu

docker.prepare.fedora:
	$(TRACE)
	$(eval host_timezone=$(shell cat /etc/timezone))
	$(call run-docker-exec, root, , sh -c "echo $(host_timezone) > /etc/timezone" )

docker.prepare:
	$(TRACE)
	$(MDOCKER) start $(DOCKER_CONTAINER) $(DEVNULL)
	$(call run-docker-exec, root, , groupadd -f -g $(shell id -g) $(shell id -gn) )
	$(call run-docker-exec, root, , useradd --shell /bin/sh -M -d $(HOME) -u $(shell id -u) $(USER) -g $(shell id -g) )
	$(MAKE) docker.prepare.$(DOCKER_DISTRO)
	$(MAKE) docker.stop

DOCKER_OPTS ?= --ipc host --net host --privileged

docker.make:
	$(TRACE)
	$(DOCKER_IMAGE_ID)
	$(IF) [ -z $(docker_image_id) ]; then make --no-print-directory docker.build; fi
	$(MDOCKER) create -P --name $(DOCKER_CONTAINER) \
		$(DOCKER_MOUNTS) \
		$(DOCKER_OPTS) \
		-h $(DOCKER_HOSTNAME) \
		-e INSIDE_DOCKER=yes \
		-i $(DOCKER_IMAGE) $(DEVNULL)
	$(MAKE) docker.prepare

docker.config:
	$(TRACE)
	$(eval hostconfig=hostconfig-$(DOCKER_HOSTNAME).mk)
	$(GREP) -v -e "^\#" hostconfig-$(HOSTNAME).mk > $(hostconfig)
	$(IF) [ -e hostconfig-$(DOCKERHOST).mk ]; then \
		echo "# $(DOCKER_CONFIG)" > $(DOCKER_CONFIG); \
		grep "^WIND_INSTALL_DIR" hostconfig-$(DOCKERHOST).mk >> $(DOCKER_CONFIG); \
		echo "# end" >> $(DOCKER_CONFIG); \
	else \
		rm -f dockerconfig.mk; \
	fi

docker.create: # create docker container
	$(TRACE)
	$(MAKE) docker.config
	$(DOCKER_CONTAINER_ID)
	$(IF) [ -z $(docker_container_id) ]; then make --no-print-directory docker.make; fi

docker.start: docker.create # start docker container
	$(TRACE)
	$(MDOCKER) start $(DOCKER_CONTAINER) $(DEVNULL)

docker.stop: # stop docker container
	$(TRACE)
	$(MDOCKER) stop -t 1 $(DOCKER_CONTAINER) $(DEVNULL) || true

docker.rm: docker.stop # remove docker container
	$(TRACE)
	$(MDOCKER) rm $(DOCKER_CONTAINER) $(DEVNULL)

docker.rmi: # remove docker image
	$(TRACE)
	$(MDOCKER) rmi $(DOCKER_IMAGE)

docker.shell: docker.make.config docker.start # start docker shell as $(USER)
	$(TRACE)
	$(call run-docker-exec, $(USER), -it, /bin/sh -c "cd $(TOP); exec /bin/bash")

docker.rootshell: docker.start # start docker shell as root
	$(TRACE)
	$(call run-docker-exec, root, -it, /bin/sh -c "cd /root; exec /bin/bash")

docker.make.config::
	$(TRACE)
	$(eval makeconfig=$(OUTDIR)/tmp/$(MACHINE)-dockerconfig.mk)
	$(MKDIR) $(OUTDIR)/tmp
	$(ECHO) "# $(makeconfig)" > $(makeconfig)
	$(ECHO) "V = $(V)" >> $(makeconfig)
	$(ECHO) "PROJECT = $(PROJECT)" >> $(makeconfig)
	$(ECHO) "MACHINE = $(MACHINE)" >> $(makeconfig)
	$(ECHO) "TARGET = $(TARGET)" >> $(makeconfig)
	$(ECHO) "TESTSUITE = $(TESTSUITE)" >> $(makeconfig)
	$(ECHO) "BUILDDIR = $(DOCKER_BUILDDIR)" >> $(makeconfig)

docker.make.%: docker.start docker.make.config # Run make inside docker, e.g. make docker.make.all"
	$(call run-docker-exec, $(USER), -t, make -s -C $(TOP) $* MACHINE=$(MACHINE) PROJECT=$(PROJECT) )

docker.clean: # stop and remove docker container and remove configs
	$(MAKE) docker.rm
	$(RM) $(DOCKER_CONFIG)
	$(RM) hostconfig-$(DOCKER_HOSTNAME).mk

docker.distclean: docker.rmi

docker.help:
	$(DOCKER_IMAGE_ID)
	$(DOCKER_CONTAINER_ID)
	$(DOCKER_CONTAINER_RUNNING)
	$(call run-help, docker.mk)
	$(GREEN)
	$(ECHO) "\n DOCKER_DISTRO=$(DOCKER_DISTRO):$(DOCKER_DISTRO_VER)"
	$(ECHO) " IMAGE=$(DOCKER_IMAGE) id=$(docker_image_id)"
	$(ECHO) " CONTAINER=$(DOCKER_CONTAINER) id=$(docker_container_id) running=$(docker_container_running)"
	$(ECHO) " BUILDDIR=$(BUILDDIR)"
	$(ECHO) " DOCKERHOST=$(DOCKERHOST)"
	$(ECHO) " MACHINE=$(MACHINE)"
	$(NORMAL)

#######################################################################

help:: docker.help
