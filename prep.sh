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
WPAFILE=./wpa_supplicant.conf

#-------------------------------------------------------------------------------

show_avail_devices()
{
	dev=$1

	lsblk --output NAME,MODEL,TYPE,FSTYPE,RM,SIZE,TRAN,LABEL,MOUNTPOINT $dev
}

#-------------------------------------------------------------------------------

show_changes()
{
	local path=$1

	echo -e "\nchanged $path files:"
	find $path -mtime -1 | xargs ls -ld
}

#-------------------------------------------------------------------------------

resize_rootfs()
{
	local dev=$1
	local size=$2

	local label='rootfs'
	local part_num=2

	# reread partition table
	partprobe ${dev}2

	# confirm partition number
	if [ "`lsblk --noheading --output LABEL ${dev}${part_num}`" = "$label" ]; then
		echo -e "\nresize root filesystem (${dev}${part_num} $size) ..."

		# resize the main partition
		parted $dev resizepart $part_num $size

		e2fsck -f ${dev}${part_num}
		resize2fs ${dev}${part_num}

		config_count=$(( $config_count + 1 ))
	else
		echo -e "${dev}${part_num} does not appear to be $label"
		exit 1
	fi
}

#-------------------------------------------------------------------------------

do_disable_resize()
{
	local file=$BOOT/cmdline.txt

	# Check for and disable init_resize script
	grep --quiet --no-messages "init_resize" $file
	if [ $? -eq 0 ]; then
		echo -e "\nupdate $file to remove init_resize.sh ..."

		sed --in-place=.orig s/init=.*init_resize.sh// $file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured to disable init_resize"
	fi
}

#-------------------------------------------------------------------------------

mount_partitions()
{
	local dev=$1
	local boot=$2
	local root=$3

	if [ ! -d $boot ]; then
		mkdir --verbose $boot
	fi
	if [ ! -d $root ]; then
		mkdir --verbose $root
	fi

	# confirm partition number
	if [ `lsblk --noheading --output LABEL ${dev}1` = "boot" ]; then
		local bootfs=${dev}1
		local rootfs=${dev}2
	else
		local bootfs=${dev}2
		local rootfs=${dev}1
	fi

	mount --verbose --types vfat $bootfs $boot --options rw,umask=0000
	mount --verbose $rootfs $root --options rw
}

#-------------------------------------------------------------------------------

do_boot_config()
{
	local memk=$1

	local file=$BOOT/config.txt

	grep --quiet --no-messages "gpu_mem=$memk" $file
	if [ "$?" -ne "0" ]; then
		echo "update $file to gpu_mem=$memk ..."

		# append to file
		cp --no-clobber $file $file.orig
		cat >> $file <<-EOF

			# set memory used by gpu (prep.sh)
			gpu_mem=$memk
		EOF

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured gpu_mem=$memk"
	fi
}

#-------------------------------------------------------------------------------

do_bluetooth()
{
	local bt=$1

	local file=$BOOT/config.txt
	local off_cmd="dtoverlay=pi3-disable-bt"

	# if the command isn't present and off is requested
	grep --quiet --no-messages "$off_cmd" $file
	if [ "$?" -ne "0" ] && [ $bt == "off" ]; then
		echo "update $file to $off_cmd ..."

		# append to file
		cp --no-clobber --verbose $file $file.orig
		cat >> $file <<-EOF

			# disable bluetooth
			$off_cmd
		EOF

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured $off_cmd"
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
	local wpafile=$1

	local file=$BOOT/wpa_supplicant.conf

	if [ -f $wpafile ]; then
		if [ ! -f $file ]; then
			echo -e "copy $wpafile to $file ..."

			cp --verbose --force $wpafile $file

			config_count=$(( $config_count + 1 ))
		else
			echo "$file already configured"
		fi
	else
		echo "\nWARNING: no $wpafile found wifi will not connect on boot\n"
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

		sed --in-place=.orig s/$CUR_HOSTNAME/$new_hostname/g $hosts

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

		cp --no-clobber $file $file.orig
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

do_scripts()
{
	local file=$1

	if [ ! -d "$file" ]; then
		echo -e "copy scripts to $file ..."

		# copy over config tools
		mkdir --verbose $file
		cp README.md config.sh prep.sh lirc.sh $file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured"
	fi
}

#-------------------------------------------------------------------------------

clear_keys()
{
	host=$1

	# make the local machine forget past versions
	echo -e "\nclean local keys for $host"
	ssh-keygen -f "/home/$SUDO_USER/.ssh/known_hosts" -R "$host"

	# try to forget by ip address too (only works if host is up)
	# ip=`arp -a $host | cut -d'(' -f2 | cut -d')' -f1`
	# ssh-keygen -f "/home/$SUDO_USER/.ssh/known_hosts" -R "$ip"

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

	echo -e "NEWHOSTNAME=\"$CUR_HOSTNAME\""
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

# option defaults
verbose=0
config_file=./vars

# check for options
while getopts "hvd:c:" opt; do
	case "$opt" in
	h|\?)
		usage
		;;
	v)  verbose=1
		;;
	d)  dump_options $OPTARG
		;;
	c)	confile_file=$OPTARG
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

if [ ! -f $config_file ]; then
	echo "$config_file does not exist"
	exit 1
fi

# Config option defaults
NEWHOSTNAME=raspberrypi
GPUMEM=64
SSH=on
BLUETOOTH=on
TIMEZONE=$(</etc/timezone)
LOCALE="C.UTF-8"
KEYBOARD="pc101 us"
TVSERVICE="--off"
PARTSIZE=""

. $config_file

disk=`basename $dev`
imgsize=`du --block-size=1M $img | cut -f1`

echo "--------------------------------------------------------------------------------"
echo "Setup workspace"
echo "--------------------------------------------------------------------------------"
echo "Img file         : $img"
echo "Img size         : $imgsize MiB"
echo "Target           : $dev"
echo "Boot mount       : $BOOT" 
echo "Root mount       : $ROOT : $PARTSIZE"
echo "Hostname         : $NEWHOSTNAME"
echo "Locale           : $LOCALE"
echo "Timezone         : $TIMEZONE"
echo "Keyboard Layout  : $KEYBOARD"
echo "Bluetooth        : $BLUETOOTH"
echo "SSH              : $SSH"
echo "GPU Memory       : $GPUMEM"
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

if [ "$PARTSIZE" != "" ]; then
	resize_rootfs $dev $PARTSIZE
fi

echo -e "\npartitions:"
parted $dev print free

mount_partitions $dev $BOOT $ROOT

echo
echo config...

# config boot filesystem
do_boot_config $GPUMEM
do_ssh $SSH
do_wifi $WPAFILE
do_bluetooth $BLUETOOTH

if [ "$PARTSIZE" != "" ]; then
	do_disable_resize
fi

# config root filesystem
set_hostname $NEWHOSTNAME
set_timezone $TIMEZONE
set_locale $LOCALE
set_keyboard $KEYBOARD
set_tvservice $TVSERVICE

# copy over tools
do_scripts $BOOT/tools

# Show changed files
show_changes $BOOT
show_changes $ROOT

echo
umount --verbose $BOOT
umount --verbose $ROOT
rm --recursive --force --verbose $BOOT $ROOT

clear_keys $NEWHOSTNAME

echo -e "\ndone"
