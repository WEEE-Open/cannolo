#!/bin/bash
set -e

# space left free on the primary partition after shrinking (expressed in number of blocks)
FREE_BLOCKS=20

usage(){
	echo "Usage: $0 [OPTION] IMAGE [DISK_DEVICE]"
	echo "Shrink the given image, copy it to the given disk and expand it to fill all the space"
	echo "--no-bake: skip image shrinking"
	echo 
	echo IMAGE: a disk image
	echo 'DISK_DEVICE: a disk device file, such as /dev/sdb. If provided, the passed image will be copied to it.' 
}

#
# parse argument
# 

parsed_options=$(getopt -n $0 -o "h" --long "help,no-bake,no-fill" -- $@)
eval set -- "$parsed_options"

no_bake=false

while true
do
	case "$1" in 
		-h|--help)
			tput set af usage
			exit 0
			;;
		--no-bake)
			no_bake=true
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

# TODO: assert there is only one primary partition
primary_partition_n=$(parted $img_file --script print | awk '$5=="primary" { print $1 }')
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
else
	echo
	tput setaf 3 && echo "Copying image to disk"
	dd if="$img_file" of="$disk" status=progress
	echo
	
	echo "Expanding primary partition"
	growpart $disk $primary_partition_n
	
	# resize filesystem to fit newly extended partition
	resize2fs "$disk"$primary_partition_n
fi

tput setaf 2 && echo 'Done!'
