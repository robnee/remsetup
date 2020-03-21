#!/bin/bash
#
# last delta : $LastChangedDate$
# rev        : $Rev$
#
# Prep the flash card with a clean image.  Enable ssh and provide Wifi credentials
# Get the date info

set -u

# create a timestamp file for use with find -newer
STARTTIME=/tmp/start_time
touch $STARTTIME
trap cleanup EXIT

#-------------------------------------------------------------------------------

cleanup()
{
	rm --force $STARTTIME
}

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
	if [ $? -ne "0" ]; then
		exit 1
	fi

	# Reread the partition table
	partprobe $dev
}

#-------------------------------------------------------------------------------

resize_rootfs()
{
	local dev=$1
	local size=$2

	local found=0

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

			# we need to convert --verbose to -v
			local v=${verbose: 1:2}
			e2fsck $v -f $partname
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

	mkdir $verbose $boot
	mkdir $verbose $root

	# loop over partitions and mount as appropriate
	lsblk --noheadings --output LABEL,PATH ${dev} | while read line
	do
		local label=$(echo $line | xargs | cut -f1 -d' ')
		local partname=$(echo $line | xargs | cut -f2 -d' ')

		if [ "$label" = "boot" ]; then
			mount $verbose --types vfat $partname $boot --options rw,umask=0000
		elif [ "$label" = "rootfs" ]; then
			mount $verbose $partname $root --options rw
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

		cp $verbose --no-clobber -$file $file.orig
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

		cp $verbose --no-clobber $file $file.orig
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
		cp $verbose --no-clobber $file $file.orig
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

		cp $verbose --force $data $file

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

		cp $verbose --no-clobber $file $file.orig
		echo $tz > $file

		mv $verbose --no-clobber $root/etc/localtime $root/etc/localtime.orig
		rm $verbose --force $root/etc/localtime
		ln $verbose --symbolic /usr/share/zoneinfo/$tz $root/etc/localtime

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

		cp $verbose --no-clobber $file $file.orig
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

		cp $verbose --no-clobber $file $file.orig
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

		cp $verbose --no-clobber $file $file.orig
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

add_service()
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

		ln $verbose --symbolic $service $root/etc/systemd/system/${wants}.wants

		echo "add service $name $file ..."

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
		mkdir $verbose $file
		cp $verbose README.md config.sh prep.sh lirc.sh $file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured"
	fi
}

#-------------------------------------------------------------------------------

do_config()
{
	local boot=$1
	local root=$2

	config_count=0

	echo
	echo config boot ...

	if [ "$SSH" = "on" ]; then
		copy_file /dev/null "$boot/ssh"
	fi
	if [ "$WPAFILE" != "" ]; then
		copy_file "$WPAFILE" "$boot/wpa_supplicant.conf"
	fi
	if [ "$GPUMEM" != "" ]; then
		add_config "$boot/config.txt" "gpu_mem=$GPUMEM"
	fi
	if [ $BLUETOOTH = "off" ]; then
		add_config "$boot/config.txt" "dtoverlay=pi3-disable-bt"
	fi
	if [ "$ROOTSIZE" != "" ]; then
		del_cmdline "$boot/cmdline.txt" "init=[^=]*init_resize.sh"
	fi

	do_scripts $boot/tools

	echo
	echo config root ...

	set_hostname $root $NEWHOSTNAME
	set_timezone $root $TIMEZONE
	set_locale $root $LOCALE
	set_keyboard "$root" "$KEYMODEL" "$KEYLAYOUT" "$KEYOPTIONS"

	if [ "$HDMI" = "off" ]; then
		add_service $root "disablehdmi" "Disable HDMI output" "/usr/bin/tvservice --off"
	fi
	if [ "$WIFIPOWERSAVE" = "off" ]; then
		add_service $root "wifipowersave" "Disable WiFi power saving" "/sbin/iw dev wlan0 set power_save off;/sbin/iw dev wlan0 get power_save"
	fi
}

#-------------------------------------------------------------------------------

clear_keys()
{
	local host=$1

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

show_options()
{
	local root=$1

	if [ ! -e "$root" ]; then
		echo "$root does not exist"
		exit 1
	fi

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
	echo "usage: prep.sh [ options ] [ <target block device> ]"
	echo
	echo "options:"
	echo "    -i <img file>    : Raspbian image file to flash ro target"
	echo "    -c <config file> : config file (default: ./vars)"
	echo "    -b <boot dir>    : location of boot dir or mount point"
	echo "    -r <root dir>    : location of root dir or mount point"
	echo "    -s               : show target config in config file format"
	echo "    -f               : force/suppress all prompts"
	echo "    -v               : verbose output"
	echo "    -h               : help"
	echo

	lsblk --output NAME,MODEL,TYPE,FSTYPE,RM,SIZE,TRAN,LABEL,MOUNTPOINT
	exit 1
}

#-------------------------------------------------------------------------------
# main

# command line option defaults
config_file=./vars
boot="/tmp/boot"
root="/tmp/root"
image_file=""
verbose=""
force=0

if [ "$#" -eq 0 ]; then
	usage
fi

# check for options
while getopts "hvsfi:c:b:r:" opt; do
	case "$opt" in
	h|\?)
		usage
		;;
	v)  verbose="--verbose"
		;;
	i)	image_file=$OPTARG
		;;
	c)	confile_file=$OPTARG
		;;
	b)	boot=$OPTARG
		;;
	r)	root=$OPTARG
		;;
	f)	force=1
		;;
	s)  show_options $boot
		;;
	esac
done

# shift so that $@, $1, etc. refer to the non-option arguments
shift "$((OPTIND-1))"

if [ "$#" -gt 0 ]; then
	dev=$1
fi

if [ `id -u` -ne "0" ]; then
	echo "must run as root"
	exit 1
fi

# Config option defaults
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
echo "Config file      : $config_file"
echo "Image file       : $image_file"
echo "Target           : $dev"
echo "Boot mount       : $boot" 
echo "Root mount       : $root : $ROOTSIZE"
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

if [ "$dev" != "" ]; then
	# make sure the block device looks valid
	lsblk --output NAME,MODEL,TYPE,FSTYPE,RM,SIZE,TRAN,LABEL,MOUNTPOINT $dev
	if [ $? -ne 0 ]; then
		echo "$dev does not appear to be a valid block device"
		exit 1
	fi

	# ask for confirmation if device has partitions
	partx $dev > /dev/null 2>&1
	if [ $force -eq 0 ] && [ $? -eq 0 ]; then
		echo -n -e "\n$dev appears to contain partitions, OK to overwrite? "
		read response
		if [ "${response^^}" != "Y" ]; then
			exit 0
		fi
	fi

	# Make sure dev is a disk and not one of its partitions/devices
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
		if [ ! -f "$image_file" ]; then
			echo "$image_file does not exist"
			exit 1
		fi

		flash_image $image_file $dev

		# Resize rootfs if requested
		if [ "$ROOTSIZE" != "" ]; then
			resize_rootfs $dev $ROOTSIZE 
		fi
	fi

	# Display partition info
	if [ "$verbose" != "" ]; then
		echo -e "\npartitions:"
		parted $dev print free
	fi

	# Mount partitions
	mount_partitions $dev $boot $root

	do_config $boot $root
	show_changes $boot $STARTTIME
	show_changes $root $STARTTIME

	# Unmount and cleanup
	echo
	umount $verbose $boot
	umount $verbose $root
	rm $verbose --recursive --force $boot $root

elif [ "$boot" != "" ] && [ "$root" != "" ]; then
	# make sure the target directories are available
	if [ ! -e $boot ] || [ ! -e $root ]; then
		echo -e "\n$boot and/or $root does not exist"
		exit 1
	fi

	do_config $boot $root
	show_changes $boot $STARTTIME
	show_changes $root $STARTTIME

else
	echo no target specified
	exit 1
fi

clear_keys $NEWHOSTNAME

echo -e "\ndone"
