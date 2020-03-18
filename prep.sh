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

add_boot_cmdline()
{
	local string=$1
	local new_cmd=$(echo $string | cut -f1 -d'=')

	local file=$BOOT/cmdline.txt

	# Check if new_cmd already present
	grep --quiet --no-messages "$cmd" $file
	if [ $? -eq 0 ]; then
		echo -e "\nupdate $file to add $new_cmd ..."

		# rebuild the cmdline in order to handle a changed command
		local cmdline=""
		for arg in $(<$file)
		do
			local name=$(echo $arg | cut -f1 -d'=')
			local value=""
			if [ "$name" != "$arg" ]; then
				value="=$(echo $arg | cut -f2 -d'=')"
			fi

			if [ "$name" = "$new_cmd" ]; then
				cmdline="$cmdline $string"
			else
				cmdline="$cmdline $name$value"
			fi
		done

		cp --no-clobber -$file $file.orig
		echo $cmdline > $file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured to with $cmd"
	fi
}

#-------------------------------------------------------------------------------

del_boot_cmdline()
{
	local pattern=$1

	local file=$BOOT/cmdline.txt

	# Check for and delete a command
	local match=`grep --only-matching --no-messages "$pattern" $file`
	if [ $? -eq 0 ]; then
		echo -e "\nupdate $file to remove $match ..."

		cp --no-clobber $file $file.orig
		sed --in-place=.orig s/$pattern// $file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured to disable $pattern"
	fi
}

#-------------------------------------------------------------------------------

add_boot_config()
{
	local string=$1
	local cmd=$(echo $string | cut -f1 -d',')

	local file=$BOOT/config.txt

	grep --quiet --no-messages "^$cmd" $file
	if [ "$?" -ne "0" ]; then
		echo "update $file to $string ..."

		# append to file
		cp --no-clobber $file $file.orig
		cat >> $file <<-EOF

			# set by prep.sh
			$string
		EOF

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured $string"
	fi
}

#-------------------------------------------------------------------------------

copy_file()
{
	local data=$1
	local file=$2

	if [ ! -e "$file" ]; then
		echo -e "create $file ..."

		cp --verbose --force $data $file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already exists"
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

		cp --no-clobber $file $file.orig
		echo $tz > $file

		mv --no-clobber --verbose $ROOT/etc/localtime $ROOT/etc/localtime.orig
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

		cp --no-clobber $file $file.orig
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

		cp --no-clobber $file $file.orig
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
	local options=$3

	local file=$ROOT/etc/default/keyboard

	get_keyboard

	if [ "$model" != "$XKBMODEL" ] || [ "$layout" != "$XKBLAYOUT" ] || [ "$options" != "$XKBOPTIONS" ]; then
		echo "set $file from $XKBMODEL $XKBLAYOUT to $model $layout $options ..."

		cp --no-clobber $file $file.orig
		cat <<-EOF > $file
		# IR Remote Settings
		XKBMODEL="$model"
		XKBLAYOUT="$layout"
		XKBVARIANT=""
		XKBOPTIONS="$options"

		BACKSPACE="guess"
		EOF

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already set to $model $layout $options"
	fi
}

#-------------------------------------------------------------------------------

add_startup()
{
	local name=$1
	local desc=$2
	local start=$(echo $3 | sed -e 's/\s*;\s*/\nExecStart=/g')

	local service=/etc/systemd/system/${name}.service
	local wants="multi-user.target"
	local file=$ROOT/$service

	if [ ! -e $file ]; then
		# create service file
		cat <<-EOF > $file
		[Unit]
		Description=$desc

		[Service]
		Type=oneshot
		RemainAfterExit=True
		ExecStart=$start

		[Install]
		WantedBy=$wants
		EOF

		ln --symbolic --verbose $service $ROOT/etc/systemd/system/${wants}.wants

		echo "service $name $file ..."

		config_count=$(( $config_count + 1 ))
	else
		echo "service $name $file already exists"
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

	echo -e "NEWHOSTNAME=\"$CUR_HOSTNAME\""
	echo -e "TIMEZONE=\"$CUR_TIMEZONE\""
	echo -e "LOCALE=\"$CUR_LOCALE\""
	echo -e "KEYMODEL=\"$XKBMODEL\""
	echo -e "KEYLAYOUT=\"$XKBLAYOUT\""
	echo -e "KEYOPTIONS=\"$XKBOPTIONS\""

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
SSH=on
TIMEZONE=$(</etc/timezone)
LOCALE="C.UTF-8"
KEYMODEL="pc101"
KEYLAYOUT="us"
KEYOPTIONS=""
HDMI=""
BLUETOOTH=""
WIFIPOWERSAVE=""
GPUMEM=""
ROOTSIZE=""

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
echo "Root mount       : $ROOT : $ROOTSIZE"
echo "Hostname         : $NEWHOSTNAME"
echo "Locale           : $LOCALE"
echo "Timezone         : $TIMEZONE"
echo "Keyboard         : $KEYMODEL $KEYLAYOUT $KEYOPTIONS"
echo "SSH              : $SSH"
echo "GPU Memory       : $GPUMEM"
echo "WiFi Power Save  : $WIFIPOWERSAVE"
echo "HDMI Output      : $HDMI"
echo "Bluetooth        : $BLUETOOTH"
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

if [ "$ROOTSIZE" != "" ]; then
	resize_rootfs $dev $ROOTSIZE
fi

echo -e "\npartitions:"
parted $dev print free

mount_partitions $dev $BOOT $ROOT

echo
echo config...

# config boot filesystem
if [ "$SSH" = "on" ]; then
	copy_file /dev/null "$BOOT/ssh"
fi
if [ "$WPAFILE" != "" ]; then
	copy_file "$WPAFILE" "$BOOT/wpa_supplicant.conf"
fi
if [ "$GPUMEM" != "" ]; then
	add_boot_config "gpu_mem=$GPUMEM"
fi
if [ $BLUETOOTH = "off" ]; then
	add_boot_config "dtoverlay=pi3-disable-bt"
fi
if [ "$ROOTSIZE" != "" ]; then
	del_boot_cmdline "init=[^=]*init_resize.sh"
fi

# config root filesystem
set_hostname $NEWHOSTNAME
set_timezone $TIMEZONE
set_locale $LOCALE
set_keyboard "$KEYMODEL" "$KEYLAYOUT" "$KEYOPTIONS"
if [ "$HDMI" = "off" ]; then
	add_startup "disablehdmi" "Disable HDMI output" "/usr/bin/tvservice --off"
fi
if [ "$WIFIPOWERSAVE" = "off" ]; then
	add_startup "wifipowersave" "Disable WiFi power saving" "/sbin/iw dev wlan0 set power_save off;/sbin/iw dev wlan0 get power_save"
fi

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
