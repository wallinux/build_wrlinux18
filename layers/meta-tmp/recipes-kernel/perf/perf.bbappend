
#### TMP DBG
PACKAGECONFIG = "scripting tui libunwind dwarf"
INHIBIT_PACKAGE_DEBUG_SPLIT="0"
EXTRA_OEMAKE += ' V=1'
#EXTRA_OEMAKE += ' EXTRA_CFLAGS="-marm"'
ARM_INSTRUCTION_SET = "arm"
#### TMP DBG

EXTRA_OEMAKE += '\
	     CCLD="${CC}" \
	     PYTHON="python" \
	     LDSHARED="${CC} -shared" \
	     LIBUNWIND_DIR=${STAGING_EXECPREFIXDIR} \
'

PERF_SRC += "\
	 scripts/ \
	 arch/${ARCH} \
	 arch/${ARCH}/Makefile \
"

do_configure_prepend () {
    # unistd.h can be out of sync between libc-headers and the captured version in the perf source
    # so we copy it from the sysroot unistd.h to the perf unistd.h
    install -D -m0644 ${STAGING_INCDIR}/asm-generic/unistd.h ${S}/tools/include/uapi/asm-generic/unistd.h
    install -D -m0644 ${STAGING_INCDIR}/asm-generic/unistd.h ${S}/include/uapi/asm-generic/unistd.h
}
