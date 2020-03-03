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
	parted $dev resizepart $num $size

	e2fsck -f ${dev}${num}
	resize2fs ${dev}${num}

	config_count=$(( $config_count + 1 ))
}

#-------------------------------------------------------------------------------

do_boot_cmdline()
{
	local file=$BOOT/cmdline.txt

	# Check for and disable init_resize script
	grep --no-messages "init_resize" $file
	if [ $? -eq 0 ]; then
		echo -e "\nupdate $file to remove init_resize.sh ..."

		cp -f $file $file.orig
		sed s/init=.*init_resize.sh// $file | tee $file

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

get_timezone()
{
	local file=$ROOT/etc/timezone
	CUR_TIMEZONE=$(<$file)
}

set_timezone()
{
	local tz=$1

	local file=$ROOT/etc/timezone

	get_timezone

	if [ "$tz" != "$CUR_TIMEZONE" ]; then
		echo "Set $file from $CUR_TIMEZONE to $tz ..."

		echo $tz > $file
		rm --force --verbose $ROOT/etc/localtime
		ln --symbolic --verbose /usr/share/zoneinfo/$tz $ROOT/etc/localtime

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already set to $tz"
	fi
}

#-------------------------------------------------------------------------------

get_hostname()
{
	local file=$ROOT/etc/hostname
	CUR_HOSTNAME=$(<$file)
}

set_hostname()
{
	local new_hostname=$1

	local file=$ROOT/etc/hostname
	local hosts=$ROOT/etc/hosts

	get_hostname

	if [ "$new_hostname" != "$CUR_HOSTNAME" ]; then
		echo "Set hostname from $CUR_HOSTNAME to $new_hostname ..."

		echo $new_hostname > $file

		sed s/$CUR_HOSTNAME/$new_hostname/g $hosts > $hosts

		config_count=$(( $config_count + 1 ))
	else
		echo "hostname $new_hostname already configured"
	fi
}

#-------------------------------------------------------------------------------

get_locale()
{
	local file=$ROOT/etc/default/locale
	CUR_LOCALE=`grep LANG $file | cut -d'=' -f2`
}

set_locale()
{
	local locale=$1

	local file=$ROOT/etc/default/locale

	get_locale

	if [ "$locale" != "$CUR_LOCALE" ]; then
		echo "Set $file from $CUR_LOCALE to $locale ..."

		echo LANG=$locale > $file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already set to $locale"
	fi
}

#-------------------------------------------------------------------------------

get_keyboard()
{
	local file=$ROOT/etc/default/keyboard
	. $file
}

set_keyboard()
{
	local model=$1
	local layout=$2

	local file=$ROOT/etc/default/keyboard

	get_keyboard

	if [ "$model" != "$XKBMODEL" ] || [ "$layout" != "$XKBLAYOUT" ]; then
		echo "set $file from $XKBMODEL $XKBLAYOUT to $model $layout ..."

		cp -f $file $file.orig
		cat <<-EOF > $file
		# IR Remote Settings
		XKBMODEL="$model"
		XKBLAYOUT="$layout"
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

get_tvservice()
{
	local file=$ROOT/var/spool/cron/crontabs/root

	if [ -f $file ]; then
		grep --no-messages "tvservice -off" $file
		if [ $? -eq 0 ]; then
			CUR_TVSERVICE="--off"
			return
		fi
	fi

	CUR_TVSERVICE="--preferred"
}

set_tvservice()
{
	local state=$1

	local file=$ROOT/var/spool/cron/crontabs/root

	get_tvservice

	if [ "$state" != "$CUR_TVSERVICE" ]; then
		echo "set $file tvservice to $state ..."

		# append cmd
		echo "@reboot tvservice $state" >> $file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already sets tvservice $state"
	fi
}

#-------------------------------------------------------------------------------

clear_keys()
{
	host=$1
	ip=`arp -a $host | cut -d'(' -f2 | cut -d')' -f1`

	# make the local machine forget past versions
	echo -e "\nclean local keys for $host"
	ssh-keygen -f "/home/$SUDO_USER/.ssh/known_hosts" -R "$host"
	ssh-keygen -f "/home/$SUDO_USER/.ssh/known_hosts" -R "$ip"

	# reset permissions
	chown pi:users /home/$SUDO_USER/.ssh/known_hosts
}

#-------------------------------------------------------------------------------

dump_options()
{
	ROOT=$1

	get_hostname
	get_locale
	get_timezone
	get_keyboard
	get_tvservice

	echo -e "NEWHOST=\"$CUR_HOSTNAME\""
	echo -e "TIMEZONE=\"$CUR_TIMEZONE\""
	echo -e "LOCALE=\"$CUR_LOCALE\""
	echo -e "KEYBOARD=\"$XKBMODEL $XKBLAYOUT\""
	echo -e "TVSERVICE=\"$CUR_TVSERVICE\""

	exit
}

#-------------------------------------------------------------------------------

usage()
{
	echo
    echo "usage: prep.sh [ -d <root> ] <raspbian img file> <block device to write image to>"
	echo
	show_avail_devices ""
	exit 1
}

#-------------------------------------------------------------------------------
# main

# check for options
verbose=0
while getopts "hvd:" opt; do
	case "$opt" in
	h|\?)
		usage
		;;
	v)  verbose=1
		;;
	d)  dump_options $OPTARG
		;;
	esac
done

# shift so that $@, $1, etc. refer to the non-option arguments
shift "$((OPTIND-1))"

if [ "$#" -ne 2 ]; then
	usage
fi

img=$1
dev=$2

if [ `id -u` -ne "0" ]; then
	echo "must run as root"
	exit 1
fi

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
echo "Hostname         : $NEWHOST"
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
dd if=$img status=progress of=$dev bs=1M

do_resize $dev ${ROOTNUM} $PARTSIZE

echo -e "\npartitions:"
parted $dev print free

# mount partitions
if [ ! -d $BOOT ]; then
	mkdir --verbose $BOOT
fi
if [ ! -d $ROOT ]; then
	mkdir --verbose $ROOT
fi
mount --verbose --types vfat ${dev}${BOOTNUM} $BOOT --options rw,umask=0000
mount --verbose ${dev}${ROOTNUM} $ROOT --options rw

# config boot filesystem
do_boot_cmdline
do_ssh $SSH
do_wifi "$WPACONFIG"
do_scripts $BOOT/tools

# config root filesystem
set_hostname $NEWHOST
set_timezone $TIMEZONE
set_locale $LOCALE
set_keyboard $KEYBOARD
set_tvservice $TVSERVICE

# Show changed files
echo -e "\nchanged $BOOT files:"
find $BOOT -mtime -1 | xargs ls -ld
echo -e "\nchanged $ROOT files:"
find $ROOT -mtime -1 | xargs ls -ld

# unmount an clean up
echo
umount --verbose $BOOT
umount --verbose $ROOT
rm --recursive --force --verbose $BOOT $ROOT

clear_keys $NEWHOST

echo -e "\ndone"
