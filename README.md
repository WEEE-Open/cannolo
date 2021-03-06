# C.A.N.N.O.L.O.

*Catapultatore Automatico Nucleare per il Nostro Opportuno Linux Ordinario*

A bash tool to automatically shrink, flash and expand a disk image on an external device. 

## Dependencies

Before launching the script make sure to have on your system

```
parted growpart awk tune2fs resize2fs fallocate
```

On most Debian based systems all needed dependencies can be installed with 

```
sudo apt install cloud-guest-utils parted
```

## Usage 

Available options (also listed when the script is launched with `-h` or `--help`):

`--no-bake`: passed image will not be shrinked nor modified in any way. Otherwise it will be resized to be as small as possible.

`--post-install <executable script file>`: a script to be executed on the new disk, using it as root partition. Warning: Some systemd tools such as hostnamectl, localectl and timedatectl can not be used, as they require an active dbus connection and this option uses internally `chroot`(see [it on the ArchWiki](https://wiki.archlinux.org/index.php/Chroot)).

`--hostname <PC hostname>`: the new hostname on the passed disk

`--shutdown`: shutdown the machine immediately after finishing the script execution

`--swap <swap size>`: add a swap to the primary OS on the new disk. Needs a partition size that can be accepted by the `fallocate` command.   
Possible suffixes: `K`, `M`, `G`, `T`, `P`, `E`, `Z`, `Y`.  
Only two suffixes of practical use at this point in time: `M` for Megabytes and `G` for Gigabytes.  
From [its man page](http://man7.org/linux/man-pages/man1/fallocate.1.html):  
```
The length and offset arguments may be followed by the multiplicative suffixes KiB (=1024), MiB (=1024*1024), and so on for GiB, TiB, PiB, EiB, ZiB, and YiB (the "iB" is optional, e.g., "K" has the same meaning as "KiB") or the suffixes KB (=1000), MB (=1000*1000), and so on for GB, TB, PB, EB, ZB, and YB.
```

### Examples

A typical usage example

```
sudo ./cannolo.sh xubuntu.img --hostname PC-42 --swap 1G /dev/sdb
```

#### Image creation

This is the procedure I followed

1. I created a disk on VirtualBox with default size (10 GB), default type (`vdi`) but with fixed size (in this case the default option is dynamically allocated, but choosing that option will result in Xubuntu formatting the disk with LVM, probably because it is easier to resize it in future).
2. Install Xubuntu according to instructions:  
  i. Start Xubuntu > F4 > "OEM installation" > Install  
  ii. Name asked in the first screen: `WEEE Open`  
  iii. Automatic partitioning  
  iv. Password: _read the archives_  
3. Execute [pesca](https://github.com/WEEE-Open/pesca) on it
4. Comment or delete the line starting with `/swapfile` in `/etc/fstab`, since by default Xubuntu creates a `swapfile`.  
**ONLY FOR 32 BIT**: Regenerate grub config files with 
    ```
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    ```
    (and if neeeded update the packages, but in this case it is already done by the pesca).  
5. Remove the file `/swapfile` (a reboot may be needed).  
6. Remove the system logs (just run `sudo journalctl --rotate && sudo journalctl --vacuum-time=1s`) and all the files download during the process (basically the `pesca`)  

Then, to create the `.img` just run
```bash
VBoxManage clonemedium --format RAW <file.vdi> <file.img>
```

#### Useful aliases 

The file `env.sh` contains some useful aliases:
- `img2vdi <file.img> <file.vdi>` creates a `vdi` file from the passed `.img`
- `vdi2img <file.vdi> <file.img>` does the exact opposite process

These aliases can be enabled simply by running
```bash
source env.sh
```

## Supported schemes

This script has been tested on simple BIOS partition schemes, containing only one primary partition with the operative system (both for x86 and x86_64 architectures).

