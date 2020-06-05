# podman.mk

ifdef CROPS
PODMAN_DISTRO		?= crops_poky
PODMAN_DISTRO_VER	?= latest
else
PODMAN_DISTRO		?= ubuntu
PODMAN_DISTRO_VER	?= 18_04
endif
PODMAN_DT		?= $(PODMAN_DISTRO)-$(PODMAN_DISTRO_VER)
PODMAN_BASE		?= $(shell basename $(TOP))
PODMAN_CONTAINER	?= $(USER)_$(LTS_VER)_$(PODMAN_BASE)_$(PODMAN_DT)
PODMAN_IMAGE_REPO	?= $(USER)_$(LTS_VER)_$(PODMAN_DISTRO)_$(PODMAN_DISTRO_VER)
PODMAN_IMAGE_TAG	?= $(PROJECT)
PODMAN_IMAGE		?= $(PODMAN_IMAGE_REPO):$(PODMAN_IMAGE_TAG)
PODMAN_BUILDDIR		= $(OUTDIR)/build_podman_$(MACHINE)
PODMAN_HOSTNAME		?= $(LTS_VER)_$(PODMAN_DT).eprime.com
PODMAN_CONFIG		?= podmanconfig.mk
PODMAN_BUILDARGS	?=

PODMAN			?= podman
MPODMAN			?= $(Q)$(PODMAN)

define run-podman-exec
	$(MPODMAN) exec -u $(1) $(2) $(PODMAN_CONTAINER) $(3)
endef

PODMAN_CONTAINER_RUNNING = $(eval podman_container_running=$(shell $(PODMAN) inspect -f {{.State.Running}} $(PODMAN_CONTAINER)))
PODMAN_CONTAINER_ID      = $(eval podman_container_id=$(shell $(PODMAN) ps -a -q -f name=$(PODMAN_CONTAINER)))
PODMAN_IMAGE_ID          = $(eval podman_image_id=$(shell $(PODMAN) images -q $(PODMAN_IMAGE) 2> /dev/null))

ifneq ("$(wildcard $(HOME)/podmanhost)","")
PODMANHOST		?= $(shell cat $$HOME/podmanhost)
endif

PODMAN_MOUNTS		+= -v $(WIND_INSTALL_DIR):$(WIND_INSTALL_DIR):ro
PODMAN_MOUNTS		+= -v $(PWD):$(PWD)
PODMAN_MOUNTS		+= -v $(HOME):$(HOME)

ifneq ($(V),1)
DEVNULL			?= > /dev/null
endif
#######################################################################

.PHONY:: podman.*

podman.%: export BUILDDIR=$(PODMAN_BUILDDIR)

podman.build: Dockerfile-$(LTS_VER).$(PODMAN_DT) # build podman image
	$(TRACE)
ifneq ($(V),1)
	$(eval quiet=-q)
endif
	$(MPODMAN) build $(quiet) $(PODMAN_BUILDARGS) --pull -f $< \
		-t "$(PODMAN_IMAGE)" $(TOP)

podman.prepare.ubuntu::
	$(TRACE)
	$(eval host_timezone=$(shell cat /etc/timezone))
	$(call run-podman-exec, root, , sh -c "echo $(host_timezone) > /etc/timezone" )
	$(call run-podman-exec, root, , ln -sfn /usr/share/zoneinfo/$(host_timezone) /etc/localtime )
	$(call run-podman-exec, root, , dpkg-reconfigure -f noninteractive tzdata 2> /dev/null)
	$(call run-podman-exec, root, , sh -c "ln -sfn /bin/bash /bin/sh" )

podman.prepare.crops_poky::
	$(TRACE)
	$(eval host_timezone=$(shell cat /etc/timezone))
	$(call run-podman-exec, root, , sh -c "apt install -y locales" )
	$(call run-podman-exec, root, , sh -c "DEBIAN_FRONTEND=noninteractive apt install -y tzdata" )
	$(MAKE) podman.prepare.ubuntu

podman.prepare.fedora:
	$(TRACE)
	$(eval host_timezone=$(shell cat /etc/timezone))
	$(call run-podman-exec, root, , sh -c "echo $(host_timezone) > /etc/timezone" )

podman.prepare:
	$(TRACE)
	$(MPODMAN) start $(PODMAN_CONTAINER) $(DEVNULL)
	$(call run-podman-exec, root, , groupadd -f -g $(shell id -g) $(shell id -gn) )
	$(call run-podman-exec, root, , useradd --shell /bin/sh -M -d $(HOME) -u $(shell id -u) $(USER) -g $(shell id -g) )
	$(MAKE) podman.prepare.$(PODMAN_DISTRO)
	$(MAKE) podman.stop

PODMAN_OPTS ?= --ipc host --net host --privileged

podman.make:
	$(TRACE)
	$(PODMAN_IMAGE_ID)
	$(IF) [ -z $(podman_image_id) ]; then make --no-print-directory podman.build; fi
	$(MPODMAN) create -P --name $(PODMAN_CONTAINER) \
		$(PODMAN_MOUNTS) \
		$(PODMAN_OPTS) \
		-h $(PODMAN_HOSTNAME) \
		-e INSIDE_CONTAINER=yes \
		-i $(PODMAN_IMAGE) $(DEVNULL)
	$(MAKE) podman.prepare

podman.config:
	$(TRACE)
	$(eval hostconfig=hostconfig-$(PODMAN_HOSTNAME).mk)
	$(GREP) -v -e "^\#" hostconfig-$(HOSTNAME).mk > $(hostconfig)
	$(IF) [ -e hostconfig-$(PODMANHOST).mk ]; then \
		echo "# $(PODMAN_CONFIG)" > $(PODMAN_CONFIG); \
		grep "^WIND_INSTALL_DIR" hostconfig-$(PODMANHOST).mk >> $(PODMAN_CONFIG); \
		echo "# end" >> $(PODMAN_CONFIG); \
	else \
		rm -f podmanconfig.mk; \
	fi

podman.create: # create podman container
	$(TRACE)
	$(MAKE) podman.config
	$(PODMAN_CONTAINER_ID)
	$(IF) [ -z $(podman_container_id) ]; then make --no-print-directory podman.make; fi

podman.start: podman.create # start podman container
	$(TRACE)
	$(MPODMAN) start $(PODMAN_CONTAINER) $(DEVNULL)

podman.stop: # stop podman container
	$(TRACE)
	$(MPODMAN) stop -t 1 $(PODMAN_CONTAINER) $(DEVNULL) || true

podman.rm: podman.stop # remove podman container
	$(TRACE)
	$(MPODMAN) rm $(PODMAN_CONTAINER) $(DEVNULL)

podman.rmi: # remove podman image
	$(TRACE)
	$(MPODMAN) rmi $(PODMAN_IMAGE)

podman.shell: podman.make.config podman.start # start podman shell as $(USER)
	$(TRACE)
	$(call run-podman-exec, $(USER), -it, /bin/sh -c "cd $(TOP); exec /bin/bash")

podman.rootshell: podman.start # start podman shell as root
	$(TRACE)
	$(call run-podman-exec, root, -it, /bin/sh -c "cd /root; exec /bin/bash")

podman.make.config::
	$(TRACE)
	$(eval makeconfig=$(OUTDIR)/tmp/$(MACHINE)-podmanconfig.mk)
	$(MKDIR) $(OUTDIR)/tmp
	$(ECHO) "# $(makeconfig)" > $(makeconfig)
	$(ECHO) "V = $(V)" >> $(makeconfig)
	$(ECHO) "PROJECT = $(PROJECT)" >> $(makeconfig)
	$(ECHO) "MACHINE = $(MACHINE)" >> $(makeconfig)
	$(ECHO) "TARGET = $(TARGET)" >> $(makeconfig)
	$(ECHO) "TESTSUITE = $(TESTSUITE)" >> $(makeconfig)
	$(ECHO) "BUILDDIR = $(PODMAN_BUILDDIR)" >> $(makeconfig)

podman.make.%: podman.start podman.make.config # Run make inside podman, e.g. make podman.make.all"
	$(call run-podman-exec, $(USER), -t, make -s -C $(TOP) $* MACHINE=$(MACHINE) PROJECT=$(PROJECT) )

podman.clean: # stop and remove podman container and remove configs
	$(MAKE) podman.rm
	$(RM) $(PODMAN_CONFIG)
	$(RM) hostconfig-$(PODMAN_HOSTNAME).mk

podman.distclean: podman.rmi

podman.help:
	$(PODMAN_IMAGE_ID)
	$(PODMAN_CONTAINER_ID)
	$(PODMAN_CONTAINER_RUNNING)
	$(call run-help, podman.mk)
	$(GREEN)
	$(ECHO) "\n PODMAN_DISTRO=$(PODMAN_DISTRO):$(PODMAN_DISTRO_VER)"
	$(ECHO) " IMAGE=$(PODMAN_IMAGE) id=$(podman_image_id)"
	$(ECHO) " CONTAINER=$(PODMAN_CONTAINER) id=$(podman_container_id) running=$(podman_container_running)"
	$(ECHO) " BUILDDIR=$(BUILDDIR)"
	$(ECHO) " PODMANHOST=$(PODMANHOST)"
	$(ECHO) " MACHINE=$(MACHINE)"
	$(NORMAL)

#######################################################################

help:: podman.help
