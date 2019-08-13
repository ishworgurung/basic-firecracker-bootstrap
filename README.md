# README

Bootstraps a basic [Firecracker](https://github.com/firecracker-microvm/firecracker) micro VM on Linux with KVM.

Firecracker micro VMs are essentially a *traditional VM + Container*.

```bash
$> ./start_microvm.bash
```

To use the Linux kernel 5.2.8 (x86_64 only) I built, drop the file `vmlinux.bin` in the same directory as `firecracker` binary.

Prepare the rootfs file `rootfs.ext4` formatted as ext4 and keep it in the same dir as `firecracker`. Use the procedure from https://github.com/firecracker-microvm/firecracker/blob/master/docs/rootfs-and-kernel-setup.md#creating-a-rootfs-image to build the rootfs.

