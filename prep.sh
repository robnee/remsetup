#!/bin/bash
#
# last delta : $LastChangedDate$
# rev        : $Rev$
#
# Prep the flash card with a clean image.  Enable ssh and provide Wifi credentials
# Get the date info

set -u

STARTTIME=/tmp/start_time
touch $STARTTIME

#-------------------------------------------------------------------------------

show_changes()
{
	local path=$1
	local start_time=$2

	echo -e "\nchanged $path files:"
	find $path -newer $start_time | xargs ls -ld
}

#-------------------------------------------------------------------------------

flash_image()
{
	local img=$1
	local dev=$2

	# Check if img is actually an image file
	local filetype=`file "$img" | grep -o "DOS/MBR"`
	if [ "$filetype" != "DOS/MBR" ]; then
		echo -e "\n$img does not appear to be image file"
		exit 1
	fi

	local size=`du --block-size=1M $img | cut -f1`

	echo -e "\nflashing $img (${size} MiB) ..."
	dd if=$img of=$dev status=progress bs=1M
}

#-------------------------------------------------------------------------------

resize_rootfs()
{
	local dev=$1
	local size=$2

	local found=0

	# reread partition table
	# partprobe ${dev}${part_num}
	# loop over partitions and look for rootfs
	lsblk --noheadings --output LABEL,PATH ${dev} | while read line
	do
		local label=$(echo $line | xargs | cut -f1 -d' ')
		local partname=$(echo $line | xargs | cut -f2 -d' ')

		if [ "$label" = "rootfs" ]; then
			echo -e "\nresize root filesystem ($partname $size) ..."

			# resize the main partition
			local partnum=${partname: -1}
			parted $dev resizepart $partnum $size

			e2fsck -f $partname
			resize2fs $partname

			found=1
		fi
	done

	if [ ! $found ]; then
		echo -e "Could not find partition rootfs on ${dev}"
		exit 1
	fi
}

#-------------------------------------------------------------------------------

mount_partitions()
{
	local dev=$1
	local boot=$2
	local root=$3

	# make sure the mount directories are available
	if [ -e $boot ] || [ -e $root ]; then
		echo -e "\n$boot and/or $root already exists"
		exit 1
	fi

	mkdir --verbose $boot
	mkdir --verbose $root

	# loop over partitions and mount as appropriate
	lsblk --noheadings --output LABEL,PATH ${dev} | while read line
	do
		local label=$(echo $line | xargs | cut -f1 -d' ')
		local partname=$(echo $line | xargs | cut -f2 -d' ')

		if [ "$label" = "boot" ]; then
			mount --verbose --types vfat $partname $boot --options rw,umask=0000
		elif [ "$label" = "rootfs" ]; then
			mount --verbose $partname $root --options rw
		fi
	done
}

#-------------------------------------------------------------------------------

add_cmdline()
{
	local file=$1
	local string=$2

	local new_cmd=$(echo $string | cut -f1 -d'=')

	# Check if new_cmd already present
	grep --quiet --no-messages "$cmd" $file
	if [ $? -eq 0 ]; then
		echo -e "update $file to add $new_cmd ..."

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

del_cmdline()
{
	local file=$1
	local pattern=$2

	# Check for and delete a command
	local match=`grep --only-matching --no-messages "$pattern" $file`
	if [ $? -eq 0 ]; then
		echo -e "update $file to remove $match ..."

		cp --no-clobber $file $file.orig
		sed --in-place=.orig s/$pattern// $file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured to disable $pattern"
	fi
}

#-------------------------------------------------------------------------------

add_config()
{
	local file=$1
	local string=$2

	local cmd=$(echo $string | cut -f1 -d',')

	grep --quiet --no-messages "^$cmd" $file
	if [ $? -ne 0 ]; then
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
	local root=$1

	local file=$root/etc/timezone
	CUR_TIMEZONE=$(<$file)
}

set_timezone()
{
	local root=$1
	local tz=$2

	local file=$root/etc/timezone

	get_timezone $root

	if [ "$tz" != "$CUR_TIMEZONE" ]; then
		echo "Set $file from $CUR_TIMEZONE to $tz ..."

		cp --no-clobber $file $file.orig
		echo $tz > $file

		mv --no-clobber --verbose $root/etc/localtime $root/etc/localtime.orig
		rm --force --verbose $root/etc/localtime
		ln --symbolic --verbose /usr/share/zoneinfo/$tz $root/etc/localtime

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already set to $tz"
	fi
}

#-------------------------------------------------------------------------------

get_hostname()
{
	local root=$1

	local file=$root/etc/hostname
	CUR_HOSTNAME=$(<$file)
}

set_hostname()
{
	local root=$1
	local new_hostname=$2

	local file=$root/etc/hostname
	local hosts=$root/etc/hosts

	get_hostname $root

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
	local root=$1

	local file=$root/etc/default/locale
	CUR_LOCALE=`grep LANG $file | cut -d'=' -f2`
}

set_locale()
{
	local root=$1
	local locale=$2

	local file=$root/etc/default/locale

	get_locale $root

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
	local root=$1

	local file=$root/etc/default/keyboard
	. $file
}

set_keyboard()
{
	local root=$1
	local model=$2
	local layout=$3
	local options=$4

	local file=$root/etc/default/keyboard

	get_keyboard $root

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
	local root=$1
	local name=$2
	local desc=$3
	local start=$(echo $4 | sed -e 's/\s*;\s*/\nExecStart=/g')

	local service=/etc/systemd/system/${name}.service
	local wants="multi-user.target"
	local file=$root/$service

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

		ln --symbolic --verbose $service $root/etc/systemd/system/${wants}.wants

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
	root=$1

	get_hostname $root 
	get_locale $root
	get_timezone $root 
	get_keyboard $root

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
	echo "usage: prep.sh [ -d <root> ] [ -f <raspbian img file> ] <block device to write image to>"
	echo
	show_avail_devices ""
	exit 1
}

#-------------------------------------------------------------------------------
# main

# option defaults
verbose=0
config_file=./vars
image_file=""

# check for options
while getopts "hvf:d:c:" opt; do
	case "$opt" in
	h|\?)
		usage
		;;
	v)  verbose=1
		;;
	f)	image_file=$OPTARG
		;;
	d)  dump_options $OPTARG
		;;
	c)	confile_file=$OPTARG
		;;
	esac
done

# shift so that $@, $1, etc. refer to the non-option arguments
shift "$((OPTIND-1))"

if [ "$#" -ne 1 ]; then
	usage
fi

dev=$1

if [ `id -u` -ne "0" ]; then
	echo "must run as root"
	exit 1
fi

if [ "$image_file" != "" ] && [ ! -f "$image_file" ]; then
	echo "$image_file does not exist"
	exit 1
fi

# Config option defaults
BOOT="/tmp/boot"
ROOT="/tmp/root"
WPAFILE="./wpa_supplicant.conf"
NEWHOSTNAME="raspberrypi"
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

if [ -f $config_file ]; then
	. $config_file
else
	echo "$config_file does not exist"
	exit 1
fi

echo "--------------------------------------------------------------------------------"
echo "Setup workspace"
echo "--------------------------------------------------------------------------------"
echo "Image file       : $image_file"
echo "Target           : $dev"
echo "Boot mount       : $BOOT" 
echo "Root mount       : $ROOT : $ROOTSIZE"
echo "Hostname         : $NEWHOSTNAME"
echo "Locale           : $LOCALE"
echo "Timezone         : $TIMEZONE"
echo "Keyboard         : $KEYMODEL $KEYLAYOUT $KEYOPTIONS"
echo "WPA config file  : $WPAFILE"
echo "SSH              : $SSH"
echo "GPU Memory       : $GPUMEM"
echo "WiFi Power Save  : $WIFIPOWERSAVE"
echo "HDMI Output      : $HDMI"
echo "Bluetooth        : $BLUETOOTH"
echo

if [ ! -e "$dev" ]; then
	echo "$dev does not exist"
	exit 1
fi

lsblk --output NAME,MODEL,TYPE,FSTYPE,RM,SIZE,TRAN,LABEL,MOUNTPOINT $dev
if [ $? -ne 0 ]; then
	echo could not scan $dev
	exit 1
fi

# Make sure dev is a disk and not one of it's partitions/devices
disk=`basename $dev`
if [ ! -e /sys/block/$disk ]; then
	echo -e "\n$dev does not appear to be a (whole) disk"
	exit 1
fi

# Ensure dev not already mounted
if [ `grep --count $dev /proc/mounts` -gt 0 ]; then
	echo -e "\n$dev is already mounted"
	exit 1
fi

# Flash an image to device if requested
if [ "$image_file" != "" ]; then
	flash_image $image_file $dev
fi

# Reread the partition table
partprobe $dev

# Resize rootfs if requested
if [ "$ROOTSIZE" != "" ]; then
	resize_rootfs $dev $ROOTSIZE 
fi

# Display partition info
echo -e "\npartitions:"
parted $dev print free

mount_partitions $dev $BOOT $ROOT

echo
echo config...
	
config_count=0

# config boot filesystem
if [ "$SSH" = "on" ]; then
	copy_file /dev/null "$BOOT/ssh"
fi
if [ "$WPAFILE" != "" ]; then
	copy_file "$WPAFILE" "$BOOT/wpa_supplicant.conf"
fi
if [ "$GPUMEM" != "" ]; then
	add_config "$BOOT/config.txt" "gpu_mem=$GPUMEM"
fi
if [ $BLUETOOTH = "off" ]; then
	add_config "$BOOT/config.txt" "dtoverlay=pi3-disable-bt"
fi
if [ "$ROOTSIZE" != "" ]; then
	del_cmdline "$BOOT/cmdline.txt" "init=[^=]*init_resize.sh"
fi

# config root filesystem
set_hostname $ROOT $NEWHOSTNAME
set_timezone $ROOT $TIMEZONE
set_locale $ROOT $LOCALE
set_keyboard "$ROOT" "$KEYMODEL" "$KEYLAYOUT" "$KEYOPTIONS"
if [ "$HDMI" = "off" ]; then
	add_startup $ROOT "disablehdmi" "Disable HDMI output" "/usr/bin/tvservice --off"
fi
if [ "$WIFIPOWERSAVE" = "off" ]; then
	add_startup $ROOT "wifipowersave" "Disable WiFi power saving" "/sbin/iw dev wlan0 set power_save off;/sbin/iw dev wlan0 get power_save"
fi

# copy over tools
do_scripts $BOOT/tools

# Show changed files
show_changes $BOOT $STARTTIME
show_changes $ROOT $STARTTIME

echo
umount --verbose $BOOT
umount --verbose $ROOT
rm --recursive --force --verbose $BOOT $ROOT

clear_keys $NEWHOSTNAME

rm --force $STARTTIME

echo -e "\ndone"
