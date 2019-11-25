# cannolo

A bash tool to automatically shrink, flash and expand a disk image on an external device. 

## Dependencies

Before launching the script make sure to have on your system

```
parted growroot awk tune2fs resize2fs fallocate
```

## Usage 

Available options (also listed when the script is launched with `-h` or `--help`):

**--no_bake**: passed image will not be shrinked nor modified in any way. Otherwise it will be resized to be as much small as possible.

**--post-install**: a script to be executed on the new disk, using it as root partition. Warning: Some systemd tools such as hostnamectl, localectl and timedatectl can not be used, as they require an active dbus connection and this option uses internally `chroot`(see [chroot on the ArchWiki](https://wiki.archlinux.org/index.php/Chroot)).

**--hostname**: the new hostname on the passed disk

**--shutdown**: shutdown the machine immediately after finishing the script execution

**--swap**: add a swap to the primary OS on the new disk. Needs a partition size that can be accepted from the `fallocate` command. From [its man page](http://man7.org/linux/man-pages/man1/fallocate.1.html)

```
The length and offset arguments may be followed by the multiplicative suffixes KiB (=1024), MiB (=1024*1024), and so on for GiB, TiB, PiB, EiB, ZiB, and YiB (the "iB" is optional, e.g., "K" has the same meaning as "KiB") or the suffixes KB (=1000), MB (=1000*1000), and so on for GB, TB, PB, EB, ZB, and YB.
```

## Supported schemes

This script has been tested on simple BIOS partition schemes, containing only one primary partition with the operative system (both for x86 and x86_64 architectures).

