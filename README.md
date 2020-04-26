# Build wrlinux18 qemuarm64

1. Add hostconfig file where the wrlinux 18 installation is located

```
host$ cat hostconfig-arn-build3.mk
# arn-build3 host config file
#
WIND_INSTALL_DIR        ?= /wr/installs/wrl-18-mirror
```
2a. build kernel, 64-bit multilib rootfs image and sdk
```
host$ make all
```
2a. build kernel, 32 bit rootfs image and SDK
```
host$ make all.32
```
3a. run qemu with 64 bit multilib rootfs
```
host$ make runqemu
```
3b. run qemu with 32 bit rootfs
```
host$ make runqemu
```
4a. cp files from host to qemu
```
qemu$ scp <user>@<hostip>:<file> .
```

4b. cp files to qemu from host.
Check which port is for port forwarding. Check the log from step 3. Normally the post is 2222

```
host$ scp  -P 2222 <file> root@localhost:
```
