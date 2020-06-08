# container.mk

ifdef CROPS
CONTAINER_DISTRO	?= crops_poky
CONTAINER_DISTRO_VER	?= latest
else
CONTAINER_DISTRO	?= ubuntu
CONTAINER_DISTRO_VER	?= 18_04
endif
CONTAINER_DT		?= $(CONTAINER_DISTRO)-$(CONTAINER_DISTRO_VER)
CONTAINER_BASE		?= $(shell basename $(TOP))
CONTAINER_NAME		?= $(USER)_$(LTS_VER)_$(CONTAINER_BASE)_$(CONTAINER_DT)
CONTAINER_IMAGE_REPO	?= $(USER)_$(LTS_VER)_$(CONTAINER_DISTRO)_$(CONTAINER_DISTRO_VER)
CONTAINER_IMAGE_TAG	?= $(PROJECT)
CONTAINER_IMAGE		?= $(CONTAINER_IMAGE_REPO):$(CONTAINER_IMAGE_TAG)
CONTAINER_BUILDDIR	= $(OUTDIR)/build_container_$(MACHINE)
CONTAINER_HOSTNAME	?= $(LTS_VER)_$(CONTAINER_DT).eprime.com
CONTAINER_CONFIG	?= containerconfig.mk
CONTAINER_BUILDARGS	?=

CONTAINER		?= docker
MCONTAINER		?= $(Q)$(CONTAINER)

define run-container-exec
	$(MCONTAINER) exec -u $(1) $(2) $(CONTAINER_NAME) $(3)
endef

CONTAINER_NAME_RUNNING	= $(eval container_name_running=$(shell $(CONTAINER) inspect -f {{.State.Running}} $(CONTAINER_NAME)))
CONTAINER_NAME_ID	= $(eval container_name_id=$(shell $(CONTAINER) ps -a -q -f name=$(CONTAINER_NAME)))
CONTAINER_IMAGE_ID	= $(eval container_image_id=$(shell $(CONTAINER) images -q $(CONTAINER_IMAGE) 2> /dev/null))

ifneq ("$(wildcard $(HOME)/containerhost)","")
CONTAINERHOST		?= $(shell cat $$HOME/containerhost)
endif

CONTAINER_MOUNTS	+= -v $(WIND_INSTALL_DIR):$(WIND_INSTALL_DIR):ro
CONTAINER_MOUNTS	+= -v $(PWD):$(PWD)
CONTAINER_MOUNTS	+= -v $(HOME):$(HOME)

ifneq ($(V),1)
DEVNULL			?= > /dev/null
endif
#######################################################################

.PHONY:: container.*

container.%: export BUILDDIR=$(CONTAINER_BUILDDIR)

container.build: Dockerfile-$(LTS_VER).$(CONTAINER_DT) # build container image
	$(TRACE)
ifneq ($(V),1)
	$(eval quiet=-q)
endif
	$(MCONTAINER) build $(quiet) $(CONTAINER_BUILDARGS) --pull -f $< \
		-t "$(CONTAINER_IMAGE)" $(TOP)

container.prepare.ubuntu::
	$(TRACE)
	$(eval host_timezone=$(shell cat /etc/timezone))
	$(call run-container-exec, root, , sh -c "echo $(host_timezone) > /etc/timezone" )
	$(call run-container-exec, root, , ln -sfn /usr/share/zoneinfo/$(host_timezone) /etc/localtime )
	$(call run-container-exec, root, , dpkg-reconfigure -f noninteractive tzdata 2> /dev/null)
	$(call run-container-exec, root, , sh -c "ln -sfn /bin/bash /bin/sh" )

container.prepare.crops_poky::
	$(TRACE)
	$(call run-container-exec, root, , sh -c "apt install -y locales" )
	$(call run-container-exec, root, , sh -c "DEBIAN_FRONTEND=noninteractive apt install -y tzdata" )
	$(MAKE) container.prepare.ubuntu

container.prepare.fedora:
	$(TRACE)
	$(eval host_timezone=$(shell cat /etc/timezone))
	$(call run-container-exec, root, , sh -c "echo $(host_timezone) > /etc/timezone" )

container.prepare:
	$(TRACE)
	$(MCONTAINER) start $(CONTAINER_NAME) $(DEVNULL)
	$(call run-container-exec, root, , groupadd -f -g $(shell id -g) $(shell id -gn) )
	$(call run-container-exec, root, , useradd --shell /bin/sh -M -d $(HOME) -u $(shell id -u) $(USER) -g $(shell id -g) )
	$(MAKE) container.prepare.$(CONTAINER_DISTRO)
	$(MAKE) container.stop

CONTAINER_OPTS ?= --ipc host --net host --privileged

container.make:
	$(TRACE)
	$(CONTAINER_IMAGE_ID)
	$(IF) [ -z $(container_image_id) ]; then make --no-print-directory container.build; fi
	$(MCONTAINER) create -P --name $(CONTAINER_NAME) \
		$(CONTAINER_MOUNTS) \
		$(CONTAINER_OPTS) \
		-h $(CONTAINER_HOSTNAME) \
		-e INSIDE_CONTAINER=yes \
		-i $(CONTAINER_IMAGE) $(DEVNULL)
	$(MAKE) container.prepare

container.config:
	$(TRACE)
	$(eval hostconfig=hostconfig-$(CONTAINER_HOSTNAME).mk)
	$(GREP) -v -e "^\#" hostconfig-$(HOSTNAME).mk > $(hostconfig)
	$(IF) [ -e hostconfig-$(CONTAINERHOST).mk ]; then \
		echo "# $(CONTAINER_CONFIG)" > $(CONTAINER_CONFIG); \
		grep "^WIND_INSTALL_DIR" hostconfig-$(CONTAINERHOST).mk >> $(CONTAINER_CONFIG); \
		echo "# end" >> $(CONTAINER_CONFIG); \
	else \
		rm -f containerconfig.mk; \
	fi

container.create: # create container container
	$(TRACE)
	$(MAKE) container.config
	$(CONTAINER_NAME_ID)
	$(IF) [ -z $(container_name_id) ]; then make --no-print-directory container.make; fi

container.start: container.create # start container container
	$(TRACE)
	$(MCONTAINER) start $(CONTAINER_NAME) $(DEVNULL)

container.stop: # stop container container
	$(TRACE)
	$(MCONTAINER) stop -t 1 $(CONTAINER_NAME) $(DEVNULL) || true

container.rm: container.stop # remove container container
	$(TRACE)
	$(MCONTAINER) rm $(CONTAINER_NAME) $(DEVNULL)

container.rmi: # remove container image
	$(TRACE)
	$(MCONTAINER) rmi $(CONTAINER_IMAGE)

container.logs: # show container log
	$(TRACE)
	$(MCONTAINER) logs $(CONTAINER_NAME)

container.shell: container.make.config container.start # start container shell as $(USER)
	$(TRACE)
	$(call run-container-exec, $(USER), -it, /bin/sh -c "cd $(TOP); exec /bin/bash")

container.rootshell: container.start # start container shell as root
	$(TRACE)
	$(call run-container-exec, root, -it, /bin/sh -c "cd /root; exec /bin/bash")

container.make.config::
	$(TRACE)
	$(eval makeconfig=$(OUTDIR)/tmp/$(MACHINE)-containerconfig.mk)
	$(MKDIR) $(OUTDIR)/tmp
	$(ECHO) "# $(makeconfig)" > $(makeconfig)
	$(ECHO) "V = $(V)" >> $(makeconfig)
	$(ECHO) "PROJECT = $(PROJECT)" >> $(makeconfig)
	$(ECHO) "MACHINE = $(MACHINE)" >> $(makeconfig)
	$(ECHO) "TARGET = $(TARGET)" >> $(makeconfig)
	$(ECHO) "TESTSUITE = $(TESTSUITE)" >> $(makeconfig)
	$(ECHO) "BUILDDIR = $(CONTAINER_BUILDDIR)" >> $(makeconfig)

container.make.%: container.start container.make.config # Run make inside container, e.g. make container.make.all"
	$(call run-container-exec, $(USER), -t, make -s -C $(TOP) $* MACHINE=$(MACHINE) PROJECT=$(PROJECT) )

container.clean: # stop and remove container container and remove configs
	$(MAKE) container.rm
	$(RM) $(CONTAINER_CONFIG)
	$(RM) hostconfig-$(CONTAINER_HOSTNAME).mk

container.distclean: container.rmi

container.help:
	$(CONTAINER_IMAGE_ID)
	$(CONTAINER_NAME_ID)
	$(CONTAINER_NAME_RUNNING)
	$(call run-help, container.mk)
	$(GREEN)
	$(ECHO) "\n CONTAINER_DISTRO=$(CONTAINER_DISTRO):$(CONTAINER_DISTRO_VER)"
	$(ECHO) " IMAGE=$(CONTAINER_IMAGE) id=$(container_image_id)"
	$(ECHO) " CONTAINER=$(CONTAINER_NAME) id=$(container_name_id) running=$(container_name_running)"
	$(ECHO) " BUILDDIR=$(BUILDDIR)"
	$(ECHO) " CONTAINERHOST=$(CONTAINERHOST)"
	$(ECHO) " MACHINE=$(MACHINE)"
	$(NORMAL)

#######################################################################

help:: container.help
