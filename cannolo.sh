#!/bin/bash
set -e

# space left free on the primary partition after shrinking (expressed in number of blocks)
FREE_BLOCKS=100

usage(){
	echo Usage: $0 IMAGE DISK_DEVICE
	echo "Shrink the given image, copy it to the given disk and expand it to fill all the space"
	echo 
	echo IMAGE: a disk image
	echo 'DISK_DEVICE: a disk device file, such as /dev/sdb'
}

while getopts ":h" opt; do
	case "${opt}" in
    		h) 
			# print help and exit
	    		usage
			exit 0
			;;

    		*)
		        # same as -h	
	    		usage
			exit 1
      	    		;;

  	esac
done

# parse the 2 remaining mandatory arguments
shift $((OPTIND-1))
img_file=$1
disk=$2

# check mandatory arguments
if [ -z $img_file ]
then
	echo "Please provide an image"
	exit 1
fi

if [ -z $disk ]
then
	echo "Please provide a disk"
	exit 1
fi

# require root privileges
if (( EUID != 0 )); then
	echo "You need to be running as root."
	exit -3
fi

echo Selected image: $img_file
echo 

# print disk initial state
fdisk -l $img_file
echo

# 
# calculating number, start, size and end of the new primary partition
# 

# TODO: assert there is only one primary partition
primary_partition_n=$(parted $img_file --script print | awk '$5=="primary" { print $1 }')
echo "Number of the primary partition: $primary_partition_n"

# gathering data
parted_output=$(parted -ms "$img_file" unit B print | tail -n 1)
part_start=$(echo "$parted_output" | awk -v partition_n="$primary_partition_n" -F ':' '$1==partition_n {print $2}' | tr -d 'B')

loopback=$(losetup -f --show -o "$part_start" "$img_file")
tune2fs_output=$(tune2fs -l "$loopback")
block_size=$(echo "$tune2fs_output" | grep '^Block size:' | tr -d ' ' | cut -d ':' -f 2)
block_count=$(echo "$tune2fs_output" | grep '^Block count:' | tr -d ' ' | cut -d ':' -f 2)
part_size=$(($block_count * $block_size))

echo
echo "Checking file system"
sudo e2fsck -pf $loopback

echo "File system check passed"

# estimate the minimum number of blocks needed to store the data on the image
minimum_blocks=$(resize2fs -P $loopback 2> /dev/null | awk '{ print $NF }')

# resize filesystem
resize2fs -pM $loopback

# unallocate mounted loop device
losetup --detach $loopback

# leave some free blocks in the partition and calculate the new size
new_block_count=$(($minimum_blocks + $FREE_BLOCKS))
part_new_size=$(($new_block_count * $block_size))
part_new_end=$(($part_new_size + $part_start))

echo 
echo "Start of the partition: $part_start"
echo "Size of the partition: $part_size"
echo "New size of the partition: $part_new_size"
echo "New end of the partition: $part_new_end"

if [ $part_size -le $part_new_size ]
then
	echo "Partition is already shrinked"
else
	echo "Shrinking partition..."
	yes | parted ---pretend-input-tty $img_file unit B resizepart $primary_partition_n $part_new_end
fi

echo "Image successfully shrinked"

# reducing img file size
truncate_point=$part_new_end
echo
echo "Truncating img at $truncate_point"
truncate -s $part_new_end $img_file

echo
echo "Copying image to disk"
dd if="$img_file" of="$disk" status=progress
echo

echo "Expanding primary partition"
growpart $disk $primary_partition_n

# resize filesystem to fit newly extended partition
resize2fs "$disk"$primary_partition_n

echo 'Done!'
