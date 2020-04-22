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
4. cp files from host to qemu
```
qemu$ scp -a <user>@<hostip>:<path> .
```
