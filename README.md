# Build wrlinux18 qemuarm64

1. Add hostconfig file where the wrlinux 18 installation is located

```
host$ cat hostconfig-arn-build3.mk
# arn-build3 host config file
#
WIND_INSTALL_DIR        ?= /wr/installs/wrl-18-mirror
```
2. build kernel and image
```
host$ make all
```
3. run qemu
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
