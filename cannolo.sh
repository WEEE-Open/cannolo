#!/bin/bash
set -e

# space left free on the primary partition after shrinking (expressed in number of blocks)
FREE_BLOCKS=20

usage(){
	echo "Usage: $0 [OPTION] IMAGE [DISK_DEVICE]"
	echo "Shrink the given image, copy it to the given disk and expand it to fill all the space"
	echo 
	echo "--no-bake: skip image shrinking"
	echo "--post-install: a script to be executed on the new disk (used as primary partition)"
	echo "--hostname: new hostname on the disk"
	echo "--shutdown: shutdown the machine when the process is completed"
	echo "--swap <swap size>: create a swapfile on the primary partition and enable swap on it"
	echo 
	echo IMAGE: a disk image
	echo 'DISK_DEVICE: a disk device file, such as /dev/sdb. If provided, the passed image will be copied to it.' 
}

#
# parse argument
# 

parsed_options=$(getopt -n $0 -o "h" --long "help,no-bake,post-install:,hostname:,shutdown,swap:" -- $@)
eval set -- "$parsed_options"

no_bake=false
shutdown=false

while true
do
	case "$1" in 
		-h|--help)
			usage
			exit 0
			;;
		--no-bake)
			no_bake=true
			shift;;
		--post-install)
			if [ -n "$2" ]
			then
				script=$2
			fi 
			shift 2;;
		--hostname)
			if [ -n "$2" ]
			then
				new_hostname=$2
			fi
			shift 2;;	
		--swap)
			if [ -n "$2" ]
			then
				swap_size=$2
			fi
			shift 2;;
		--shutdown)
			shutdown=true
			shift;;
		--)
			shift
			break;;
	esac
done	

# parse the 2 remaining mandatory arguments
img_file=$1
disk=$2

# check mandatory arguments
if [ -z $img_file ]
then
	tput setaf 1 && echo "Please provide an image"
	exit 1
fi

if [ "$disk" = "/dev/sda" ]
then    
        tput setaf 5 && echo "You selected as disk /dev/sda. This will overwrite the content of the disk. Are you sure?[y/N]"
        read answer

        if [ "$answer" = y ] || [ "$answer" = Y ]
        then    
                echo
        else    
                exit 1
        fi      
fi

# require root privileges
if (( EUID != 0 )); then
	tput setaf 3 && echo "You need to be running as root."
	exit -3
fi

tput setaf 4 && echo Selected image: $img_file
echo 

# print disk initial state
tput setaf 6 && fdisk -l $img_file
echo

# 
# calculating number, start, size and end of the new primary partition
# 

primary_partition_n=$(parted $img_file --script print | awk '$5=="primary" { print $1 }')

# check there is only one primary partition
primary_partitions_count=$(echo $primary_partition_n | wc -l) 
if [[ "$primary_partitions_count" -ne 1  ]]; then
	tput setaf 3 && echo "The image contains an invalid number of primary partitions, exiting..."
	exit 1 
fi

tput setaf 4 && echo "Number of the primary partition: $primary_partition_n"

# gathering data
parted_output=$(parted -ms "$img_file" unit B print | tail -n 1)
part_start=$(echo "$parted_output" | awk -v partition_n="$primary_partition_n" -F ':' '$1==partition_n {print $2}' | tr -d 'B')
part_end=$(echo "$parted_output" | awk -v partition_n="$primary_partition_n" -F ':' '$1==partition_n {print $3}' | tr -d 'B')

loopback=$(losetup -f --show -o "$part_start" "$img_file")
tune2fs_output=$(tune2fs -l "$loopback")
block_size=$(echo "$tune2fs_output" | grep '^Block size:' | tr -d ' ' | cut -d ':' -f 2)
block_count=$(echo "$tune2fs_output" | grep '^Block count:' | tr -d ' ' | cut -d ':' -f 2)
part_size=$(($block_count * $block_size))

echo
tput setaf 4 && echo "Checking file system"
tput setaf 6 && sudo e2fsck -pf $loopback

tput setaf 2 && echo "File system check passed"

if ! $no_bake
then
	# estimate the minimum number of blocks needed to store the data on the image
	minimum_blocks=$(resize2fs -P $loopback 2> /dev/null | awk '{ print $NF }')
	
	# resize filesystem
	tput setaf 6 && resize2fs -pM $loopback
	
	# unallocate mounted loop device
	losetup --detach $loopback
	
	# leave some free blocks in the partition and calculate the new size
	new_block_count=$(($minimum_blocks + $FREE_BLOCKS))
	part_new_size=$(($new_block_count * $block_size))
	part_new_end=$(($part_new_size + $part_start))
	
	echo 
	echo "Minimum size: $(($minimum_blocks * $block_size))"
	echo "Start of the partition: $part_start"
	echo "Size of the partition: $part_size"
	echo "New size of the partition: $part_new_size"
	echo "New end of the partition: $part_new_end"
	
	if [ $part_size -le $part_new_size ]
	then
		tput setaf 4 && echo "Partition is already shrinked"
	else
		tput setaf 3 && echo "Shrinking partition..."
		yes | parted ---pretend-input-tty $img_file unit B resizepart $primary_partition_n $part_new_end
	fi
	
	tput setaf 2 && echo "Image successfully shrinked"

	# reducing img file size
	truncate_point=$(($part_new_end + $FREE_BLOCKS * $block_size))
	echo
	tput setaf 3 && echo "Truncating img at $truncate_point"
	truncate -s $truncate_point $img_file

else
	part_new_end=$part_end
fi


if [ -z $disk ] 
then
	tput setaf 4 && echo "Skipping filling"
	exit 0
else
	echo

	tput setaf 3 && echo "Calculating optimal block size for dd"
	ibs=$(stat -f "$img_file" -c %s)
	obs=$(stat -f "$disk" -c %s)

	echo "Input block size: $ibs"
	echo "Output block size: $obs"

	tput setaf 3 && echo "Copying image to disk"
	dd if="$img_file" ibs="$ibs" of="$disk" obs="$obs" oflag=sync,nocache status=progress
	echo
	
	echo "Expanding primary partition"
	growpart $disk $primary_partition_n
	
	# resize filesystem to fit newly extended partition
	resize2fs "$disk"$primary_partition_n
fi

# 
# mount image and chroot
# 

temp_mount_folder=$(mktemp -d)
mount "$disk"$primary_partition_n $temp_mount_folder
echo 
tput setaf 2 && echo "Disk mounted"

# save PATH and add missing paths (may change on different distributions)
path_old=$PATH
export PATH="$PATH:/bin"

if [ -n "$new_hostname" ]
then
	tput setaf 4 && echo "Changing hostname"
	
	old_hostname=`cat "$temp_mount_folder"/etc/hostname`
	echo "Old hostname: $old_hostname"

	sed -i "s/$old_hostname/$new_hostname/g" "$temp_mount_folder"/etc/hosts
	echo "$new_hostname" > "$temp_mount_folder/etc/hostname"

	tput setaf 2 && echo "Hostname successfully changed"
	echo
fi

# create swapfile if specified appropriate option
if [ -n "$swap_size" ]
then
	swapfile="$temp_mount_folder/swapfile"
	
	# allocate specified space
	fallocate -l "$swap_size" "$swapfile"
	
	# set correct permissions
	chmod 600 "$swapfile"
	
	# set up Linux swap area and collect uuid
	UUID_info=$(mkswap $swapfile | tail -1 | sed 's/^[^(UUID)]*//g')

	# update fstab file
	printf "\n# $UUID_info\n/swapfile swap swap defaults 0 0\n" >> "$temp_mount_folder/etc/fstab"
fi

if [ -n "$script" ]
then
	
	# append static DNS configuration
	printf "nameserver 8.8.8.8\nnameserver8.8.4.4\n" > "$temp_mount_folder/etc/resolv.conf"
	
	tput setaf 2 && echo "Starting script execution"

	# copy and execute actual script
	tput setaf 6 
	cp $script $temp_mount_folder 
	
	script_new_loc="$temp_mount_folder/`basename $script`"
	chmod +x $script_new_loc	
	chroot $temp_mount_folder ./`basename $script`
	rm "$script_new_loc"

	# empty resolv.conf file
	touch "$temp_mount_folder/etc/resolv.conf"
	
fi

# restore PATH
export PATH="$path_old"

umount $temp_mount_folder
rm -r $temp_mount_folder 

echo
tput setaf 2 && echo 'Done!'

if $shutdown 
then
	shutdown now
fi
