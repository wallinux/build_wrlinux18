# tools.mk

# Tools used
# Define V=1 to echo everything
V	?= 0
ifneq ($(V),1)
Q=@
MAKE	:= $(Q)make -s
endif

CD	:= $(Q)cd
CHMOD	:= $(Q)chmod
CP	:= $(Q)cp
ECHO	:= @/bin/echo -e
FIND	:= $(Q)find
GIT	:= $(Q)git
GREP	:= $(Q)grep
IF	:= $(Q)if
LN	:= $(Q)ln -sfn
MAKE	?= $(Q)make
MKDIR	:= $(Q)mkdir -p
MV	:= $(Q)mv
RM	:= $(Q)rm -f
RSYNC	:= $(Q)rsync
SCP	?= $(Q)scp $(SCPOPTS)
SED	:= $(Q)sed -i
SSH	?= $(Q)ssh $(SSHOPTS)
SSHPASS	?= $(Q)sshpass
XTERM	?= $(Q)x-terminal-emulator

STAMPSDIR ?= $(BUILDDIR)/.stamps
vpath % $(BUILDDIR)/.stamps
define rmstamp
	$(RM) $(STAMPSDIR)/$(1)
endef
MKSTAMP	= $(MKDIR) $(STAMPSDIR); touch $(STAMPSDIR)/$@

%.force:
	$(call rmstamp,$*)
	$(MAKE) $*

ifeq ($(USER),jenkins)
 RED     = @#
 GREEN   = @#
 YELLOW  = @#
 BLUE    = @#
 NORMAL  = @#
else
 RED     = @tput setaf 1
 GREEN   = @tput setaf 2
 YELLOW  = @tput setaf 3
 BLUE    = @tput setaf 4
 NORMAL  = @tput sgr0
endif

define run-note
	$(GREEN)
	$(ECHO) $(1)
	$(NORMAL)
endef

ifeq ($(V),1)
  ifeq ($(USER),jenkins)
   TRACE   = @(echo ------ $@)
  else
   TRACE   = @(tput setaf 1; echo ------ $@; tput sgr0)
 endif
else
 TRACE   = @#
endif

.PHONY:: *.help

define run-help
	$(GREEN)
	$(ECHO) -e "\n----- $@ -----"
	@grep ":" $(1) | grep -v "^#" | grep -e "\#" | sed 's/:/#/' | cut -d'#' -f1,3 | sed 's/^/ /' | sort | column -s'#' -t
	$(NORMAL)

endef
