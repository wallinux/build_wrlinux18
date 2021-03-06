# Platform Makefile

default: help

# Default settings
HOSTNAME		?= $(shell hostname)
USER			?= $(shell whoami)
HOST_ARCH		?= $(shell uname -m)

# Don't inherit path from environment any extra PATHs needs to go into one of the *config-*.mk
export PATH		:= /bin:/usr/bin
export SHELL		:= /bin/bash

configure:: Makefile.configure
	$(TRACE)
	$(MKSTAMP)

# Optional configuration
-include hostconfig-$(HOSTNAME).mk
-include userconfig-$(USER).mk

TOP			:= $(shell pwd)
PROJECT			?= build_wrlinux18
WIND_INSTALL_DIR	?= /opt/projects/ericsson/installs/wrlinux_lts18
WIND_VER		?= 18
LTS_VER			?= lts$(WIND_VER)
RCPL			?= 16
DISTRO_VERSION		= 10.$(WIND_VER).44.$(RCPL)
RCPL_LONG		= $(shell printf "%04d" $(RCPL))
WIND_REL		= WRLINUX_10_$(WIND_VER)_LTS_RCPL$(RCPL_LONG)
OUTDIR			?= $(TOP)/out_$(LTS_VER).$(RCPL)

MACHINE			?= qemuarm64
IMAGE			?= wrlinux-image-glibc-small
DISTRO			?= wrlinux

LAYERS			+= $(TOP)/layers/meta-tmp

PACKAGES		+= perf openssh rsync make
PACKAGES		+= perf-dbg gdb

ifeq ($(MACHINE),qemuarm64)
PACKAGES		+= lib32-glibc lib32-libgcc lib32-libunwind
QEMUPARAMS		= '-smp 2'
endif

BUILDDIR		?= $(OUTDIR)/build_$(MACHINE)

SSTATE_LOCAL_DIR	?= $(OUTDIR)/sstate-cache

SETUP_OPTS		+= --dl-layers
SETUP_OPTS		+= --accept-eula yes
SETUP_OPTS		+= --distros $(DISTRO)
SETUP_OPTS		+= --repo-force-sync
ifneq ($(TEMPLATES),)
SETUP_OPTS		+= --templates $(TEMPLATES)
endif
ifneq ($(WRL_LAYERS),)
SETUP_OPTS		+= --layers $(WRL_LAYERS)
endif

include tools.mk

##########################################################################
BBPREP			= $(CD) $(OUTDIR); \
			  source ./environment-setup-x86_64-wrlinuxsdk-linux; \
			  source ./oe-init-build-env $(BUILDDIR) > /dev/null;

define bitbake
	$(BBPREP) bitbake $(1)
endef

define bitbake-task
	$(BBPREP) bitbake $(1) -c $(2)
endef

define bitbake-sdk
	$(BBPREP) bitbake $(1) -c populate_sdk
endef

define bbterm
	$(ECHO) Starting $(1) in $(OUTDIR)
	$(Q)gnome-terminal --working-directory=$(OUTDIR) -- bash -c \
		"source ./environment-setup-x86_64-wrlinuxsdk-linux; \
		source ./oe-init-build-env $(BUILDDIR) > /dev/null; \
		$(1)"
endef

##########################################################################
.PHONY:: help all kernel clean distclean bbs make/* update
.FORCE:

Makefile.help:
	$(call run-help, Makefile)
	$(GREEN)
	$(ECHO) "\n   DISTRO=$(DISTRO) WIND_VER=$(WIND_VER) RCPL=$(RCPL)"
	$(ECHO) "   MACHINE=$(MACHINE)"
	$(ECHO) "   IMAGE=$(IMAGE)"
	$(ECHO) "   WIND_INSTALL_DIR=$(WIND_INSTALL_DIR)"
	$(ECHO) "   BUILDDIR=$(BUILDDIR)"
	$(NORMAL)

help:: Makefile.help

all:: configure # build image and SDK
	$(TRACE)
	$(MAKE) image
	$(MAKE) sdk

all.32:: configure # build 32 bit image and SDK
	$(TRACE)
	$(MAKE) image.32
	$(MAKE) sdk

ALL:
	$(TRACE)
	$(MAKE) image
	$(MAKE) image.32
	$(MAKE) sdk
	$(MAKE) sdk.install

image: configure # build image
	$(TRACE)
	$(call bitbake,$(IMAGE))

image.32: configure # build 32 bit image
	$(TRACE)
	$(call bitbake,lib32-$(IMAGE))

kernel: configure # build kernel
	$(TRACE)
	$(call bitbake,virtual/kernel)

kernel.clean: configure # clean kernel
	$(TRACE)
	$(call bitbake-task,virtual/kernel,cleanall)

kernel.rebuild: # rebuild kernel
	$(TRACE)
	$(MAKE) kernel.clean
	$(MAKE) kernel

bbs: configure # start bbshell
	$(TRACE)
	-$(BBPREP) bash

bbsterm: configure # start gnome-terminal in build directory
	$(TRACE)
	$(call bbterm,bash)

$(OUTDIR):
	$(TRACE)
	$(MKDIR) $@

setup: $(OUTDIR)/wrlinux-x
$(OUTDIR)/wrlinux-x: | $(OUTDIR)
	$(TRACE)
	-$(GIT) clone --branch $(WIND_REL) $(WIND_INSTALL_DIR)/wrlinux-x $@
	$(CD) $(OUTDIR); REPO_MIRROR_LOCATION=$(WIND_INSTALL_DIR) ./wrlinux-x/setup.sh $(SETUP_OPTS)

add_layers:
	$(BBPREP) $(foreach layer, $(LAYERS), echo "Adding layer $(layer)"; bitbake-layers add-layer -F $(layer);)

builddir: $(BUILDDIR)
$(BUILDDIR): | $(LAYERS)
	$(TRACE)
	$(BBPREP)
	$(MAKE) add_layers

Makefile.configure:: setup | $(WIND_INSTALL_DIR)
	$(TRACE)
	$(MAKE) $(BUILDDIR)
	$(eval localconf=$(BUILDDIR)/conf/local.conf)
	$(SED) s/^MACHINE.*/MACHINE\ =\ \"$(MACHINE)\"/g $(localconf)
	$(SED) s/^\#BB_FETCH_PREMIRRORONLY.*/BB_FETCH_PREMIRRORONLY\ =\ \"1\"/g $(localconf)
ifneq ($(SSTATE_LOCAL_DIR),)
	$(SED) "s|^\#SSTATE_DIR.*|SSTATE_DIR = \"$(SSTATE_LOCAL_DIR)\"|" $(localconf)
endif

ifeq ($(MACHINE),qemuarm64)
	$(GREP) -q MULTILIBS $(localconf); \
		if [ $$? = 1 ]; then \
			echo "MULTILIBS = \"multilib:lib32\"" >> $(localconf); \
			echo "DEFAULTTUNE_virtclass-multilib-lib32" = \"armv7at-neon\" >> $(localconf); \
		fi
endif
	$(GREP) -q "SKIP_META_GNOME_SANITY_CHECK" $(localconf) || \
		echo "SKIP_META_GNOME_SANITY_CHECK = \"1\"" >> $(localconf)
	$(GREP) -q "IMAGE_INSTALL_append" $(localconf) || \
		echo "IMAGE_INSTALL_append = \"$(PACKAGES)\"" >> $(localconf)
	$(MKSTAMP)

clean:: # clean build directory
	$(TRACE)
	$(RM) -r $(BUILDDIR)

distclean:: # clean out directory
	$(TRACE)
	$(RM) -r $(OUTDIR)

##########################################################################
SDK_FILE		?= $(BUILDDIR)/tmp-glibc/deploy/sdk/$(DISTRO)-$(DISTRO_VERSION)-glibc-$(HOST_ARCH)-$(subst -,_,$(MACHINE))-$(IMAGE)-sdk.sh
SDK_DIR			?= $(OUTDIR)/sdk/$(MACHINE)

.PHONY:: sdk sdk.*

sdk: $(SDK_FILE) # build sdk
$(SDK_FILE): configure
	$(TRACE)
	$(call bitbake-sdk,$(IMAGE))

sdk.install: | $(SDK_DIR) # install sdk
$(SDK_DIR): | $(SDK_FILE)
	$(TRACE)
	$(Q)$(SDK_FILE) -y -d $@

sdk.clean: # remove installed sdk
	$(TRACE)
	$(RM) -r $(SDK_DIR)

##########################################################################
runqemu: # run qemu 64 bit multilib userspace
	$(TRACE)
	-$(BBPREP) runqemu $(MACHINE) nographic slirp qemuparams=$(QEMUPARAMS) tmp-glibc/deploy/images/$(MACHINE)/$(IMAGE)-$(MACHINE).qemuboot.conf

runqemu.32: # run qemu with 32 bit userspace
	$(TRACE)
	-$(BBPREP) runqemu $(MACHINE) nographic slirp qemuparams=$(QEMUPARAMS) tmp-glibc/deploy/images/$(MACHINE)/lib32-$(IMAGE)-$(MACHINE).qemuboot.conf

runqemuterm: # new terminal, run qemu 64 bit multilib userspace
	$(TRACE)
	$(call bbterm,runqemu $(MACHINE) nographic slirp qemuparams=$(QEMUPARAMS) tmp-glibc/deploy/images/$(MACHINE)/$(IMAGE)-$(MACHINE).qemuboot.conf)

runqemuterm.32: # new terminal, run qemu with 32 bit userspace
	$(TRACE)
	$(call bbterm,runqemu $(MACHINE) nographic slirp qemuparams=$(QEMUPARAMS) tmp-glibc/deploy/images/$(MACHINE)/lib32-$(IMAGE)-$(MACHINE).qemuboot.conf)

SSHPORT ?= 2222
qemu.ssh:
	$(TRACE)
	$(SSH) -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@localhost -p $(SSHPORT)

qemu.sshfs.mount:
	$(TRACE)
	$(MKDIR) $(MACHINE).sshfs
	$(Q)sshfs -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $(SSHPORT) root@localhost:  $(MACHINE).sshfs

qemu.sshfs.umount:
	$(TRACE)
	$(Q)fusermount -u $(MACHINE).sshfs
	$(Q)rmdir $(MACHINE).sshfs

#-include docker.mk
#-include podman.mk
-include container.mk
