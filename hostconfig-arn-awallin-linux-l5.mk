# arn-awallin-linux-l5 host config file
#
ifndef INSIDE_CONTAINER
SSTATE_SSHFS_REMOTE	?= ab3:/opt/awallin/src/build_wrlinux18/out_lts18.16/sstate-cache
SSTATE_SSHFS_MOUNT	?= $(TOP)/sstate_mirror_mount
SSTATE_MIRROR_URL 	?= file://$(SSTATE_SSHFS_MOUNT)

sshfs.mount:
	$(TRACE)
	$(MKDIR) $(SSTATE_SSHFS_MOUNT)
	$(Q)mountpoint $(SSTATE_SSHFS_MOUNT) || sshfs $(SSTATE_SSHFS_REMOTE) $(SSTATE_SSHFS_MOUNT)

sshfs.umount:
	$(TRACE)
	-$(Q)mountpoint $(SSTATE_SSHFS_MOUNT) && fusermount -u $(SSTATE_SSHFS_MOUNT)

$(HOSTNAME).configure: sshfs.mount # setup remote SSTATE_MIRROR
	$(TRACE)
	$(eval localconf=$(BUILDDIR)/conf/local.conf)
	$(GREP) -q "^SSTATE_MIRRORS" $(localconf) || \
		echo "SSTATE_MIRRORS = \"file://.* $(SSTATE_MIRROR_URL)/PATH\"" >> $(localconf)
	$(GREP) -q "^SSTATE_MIRROR_ALLOW_NETWORK" $(localconf) || \
		echo "SSTATE_MIRROR_ALLOW_NETWORK = \"1\"" >> $(localconf)

$(HOSTNAME).unconfigure: sshfs.umount
	$(TRACE)

configure:: $(HOSTNAME).configure
endif
