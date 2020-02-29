#!/bin/bash
#
# last delta : $LastChangedDate$
# rev        : $Rev$
#
# Prep the flash card with a clean image.  Enable ssh and provide Wifi credentials
# Get the date info

set -u

start_time=`date +'%Y-%m-%d %H:%M:%S'`

BOOT=/tmp/boot
ROOT=/tmp/root

SCRIPTDIR=$(dirname $0)
CONFIGFILE=./vars

#-------------------------------------------------------------------------------

show_avail_devices()
{
	dev=$1

	lsblk --output NAME,MODEL,TYPE,FSTYPE,RM,SIZE,TRAN,LABEL,MOUNTPOINT $dev
}

#-------------------------------------------------------------------------------

do_resize()
{
	local dev=$1
	local num=$2
	local size=$3

	echo -e "\nresize root filesystem (${dev}${num} $size ..."

	# use losetup to create a block dev out of img and then lsblk to get size
	# of part and size of /dev/sda2 to see if sizes are different

	# resize the main partition
	sudo parted $dev resizepart $num $size

	sudo e2fsck -f ${dev}${num}
	sudo resize2fs ${dev}${num}

	config_count=$(( $config_count + 1 ))
}

#-------------------------------------------------------------------------------

do_boot_cmdline()
{
	local file=$BOOT/cmdline.txt

	# Check for and disable init_resize script
	grep --quiet "init_resize" $file
	if [ $? -eq 0 ]; then
		echo -e "\nupdate $file to remove init_resize.sh ..."

		sudo cp -f $file $file.orig
		sed s/init=.*init_resize.sh// $file | sudo tee $file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured"
	fi
}

#-------------------------------------------------------------------------------

do_ssh()
{
	local ssh=$1

	local file=$BOOT/ssh

	if [ ! -f "$file" ] && [ $ssh == "on" ]; then
		echo -e "Set $file to $ssh"

		touch $file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured"
	fi
}

#-------------------------------------------------------------------------------

do_wifi()
{
	local wpaconfig="$1"

	local file=$BOOT/wpa_supplicant.conf

	if [ ! -f "$file" ]; then
		echo -e "Set $file with credentials ..."

		# Config and enable wifi.  Note: no spaces to either side of equals sign
		cat > $file <<-WPA
		country=US
		ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
		update_config=1
		WPA

		# add the user settings (credentials)
		echo "$wpaconfig" >> $file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured"
	fi
}

#-------------------------------------------------------------------------------

do_scripts()
{
	local file=$1

	if [ ! -d "$file" ]; then
		echo -e "copy scripts to $file ..."

		# copy over config tools
		mkdir --verbose $file
		cp README.md config.sh prep.sh $file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured"
	fi
}

#-------------------------------------------------------------------------------

do_timezone()
{
	local tz=$1

	local file=$ROOT/etc/timezone

	grep --quiet "$tz" $file
	if [ "$?" -ne "0" ]; then
		echo "Set $file to $tz ..."

		# sudo chroot $ROOT timedatectl set-timezone $tz
		echo $tz | sudo dd status=none of=$file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already set to $tz"
	fi
}

#-------------------------------------------------------------------------------

do_hostname()
{
	local file=$ROOT/etc/hostname
	local hosts=$ROOT/etc/hosts

	hostname=$1
	current_hostname=$(<$file)

	if [ "$current_hostname" = "$hostname" ]; then
		echo "Set hostname to $hostname ..."

		echo $hostname | sudo dd status=none of=$file

		sed s/$current_hostname/$hostname/g $hosts | sudo dd status=none of=$hosts

		config_count=$(( $config_count + 1 ))
	else
		echo "hostname $hostname already configured"
	fi
}

#-------------------------------------------------------------------------------

do_locale()
{
	local file=$ROOT/etc/default/locale

	grep --quiet "$1" $file
	if [ "$?" -ne "0" ]; then
		echo "Set $file to $1 ..."

		echo LANG=$1 | sudo dd status=none of=$file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already set to $1"
	fi
}

#-------------------------------------------------------------------------------

do_keyboard()
{
	local file=$ROOT/etc/default/keyboard

	grep --quiet "$1" $file
	if [ "$?" -ne "0" ]; then
		echo "set $file to $1 $2 ..."

		sudo cp -f $file $file.orig
		cat <<-EOF | sudo dd status=none of=$file
		    # IR Remote Settings
		    XKBMODEL="$1"
		    XKBLAYOUT="$2"
		    XKBVARIANT=""
		    XKBOPTIONS=""

		    BACKSPACE="guess"
		EOF

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already set to $1 $2"
	fi
}

#-------------------------------------------------------------------------------

do_tvservice()
{
	local cmd="@reboot tvservice $1"

	local file=$ROOT/var/spool/cron/crontabs/root

	sudo grep --no-messages "tvservice" $file
	if [ "$?" -ne "0" ]; then
		echo "set $file to $cmd ..."

		# append cmd
		echo $cmd | sudo tee --append $file > /dev/null

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already sets $cmd"
	fi
}

#-------------------------------------------------------------------------------
# main

if [ "$#" -ne 2 ]; then
    echo "usage: prep.sh <raspbian img file> <block device to write image to>"
	echo
	show_avail_devices ""
	exit 1
fi

img=$1
dev=$2

if [ ! -f "$img" ]; then
	echo "$img does not exist"
	exit 1
fi

if [ ! -e "$dev" ]; then
	echo "$dev does not exist"
	exit 1
fi

if [ ! -f $CONFIGFILE ]; then
	echo "$CONFIGFILE does not exist"
	exit 1
fi

. $CONFIGFILE

disk=`basename $dev`
imgsize=`du --block-size=1M $img | cut -f1`

echo "--------------------------------------------------------------------------------"
echo "Setup workspace"
echo "--------------------------------------------------------------------------------"
echo "Img file         : $img"
echo "Img size         : $imgsize MiB"
echo "Target           : $dev"
echo "/boot mount      : $BOOT : $BOOTNUM" 
echo "/root mount      : $ROOT : $ROOTNUM $PARTSIZE"
echo "Hostname         : $HOSTNAME"
echo "Locale           : $LOCALE"
echo "Timezone         : $TIMEZONE"
echo "Keyboard Layout  : $KEYBOARD"
echo "SSH              : $SSH"
echo
show_avail_devices $dev

# Make sure dev is a disk and not one of it's partitions/devices
if [ ! -e /sys/block/$disk ]; then
	echo -e "\n$dev does not appear to be a (whole) disk"
	exit 1
fi

# Ensure dev not already mounted
if [ `grep --count $dev /proc/mounts` -gt 0 ]; then
    echo -e "\n$dev is already mounted"
    exit 1
fi

# make sure the mount directories are available
if [ -e $ROOT ] || [ -e $ROOT ]; then
	echo -e "\n$BOOT or $ROOT already exists"
	exit 1
fi

# Check if img is actually an image file
filetype=`file "$img" | grep -o "DOS/MBR"`
if [ "$filetype" != "DOS/MBR" ]; then
	echo -e "\n$img does not appear to be image file"
	exit 1
fi

config_count=0

echo -e "\nflashing $img (${imgsize} MiB) ..."
sudo dd if=$img status=progress of=$dev bs=1M

do_resize $dev ${ROOTNUM} $PARTSIZE

echo -e "\npartitions:"
sudo parted $dev print free

# mount partitions
if [ ! -d $BOOT ]; then
	mkdir --verbose $BOOT
fi
if [ ! -d $ROOT ]; then
	mkdir --verbose $ROOT
fi
sudo mount --verbose --types vfat ${dev}${BOOTNUM} $BOOT --options rw,umask=0000
sudo mount --verbose ${dev}${ROOTNUM} $ROOT --options rw

# config boot filesystem
do_boot_cmdline
do_ssh $SSH
do_wifi "$WPACONFIG"
do_scripts $BOOT/tools

# config root filesystem
do_hostname $NEWHOST
do_timezone $TIMEZONE
do_locale $LOCALE
do_keyboard $KEYBOARD
do_tvservice --off

# Show changed files
echo -e "\nchanged $BOOT files:"
sudo find $BOOT -mtime -1 | xargs ls -ld
echo -e "\nchanged $ROOT files:"
sudo find $ROOT -mtime -1 | xargs sudo ls -ld

# unmount an clean up
echo
sudo umount --verbose $BOOT
sudo umount --verbose $ROOT
rm --recursive --force --verbose $BOOT $ROOT

# make the local machine forget past versions
echo -e "\nclean local keys"
ssh-keygen -f "/home/pi/.ssh/known_hosts" -R "$NEWHOST"

echo -e "\ndone"
