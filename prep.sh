#!/bin/bash
#
# last delta : $LastChangedDate$
# rev        : $Rev$
#
# Prep the flash card with a clean image.  Enable ssh and provide Wifi credentials
# Get the date info
day=`date +%A`
dom=`date +%d`
dow=`date +%w`
mon=`date +%B`
ymd=`date +%Y-%m-%d`
start_time=`date +'%Y-%m-%d %H:%M:%S'`

MNTDIR=./boot
LOGDIR=./logs
LOGFILE=$LOGDIR/$ymd.log

SCRIPTDIR=$(dirname $0)

WPAFILE=$MNTDIR/wpa_supplicant.conf
NETFILE=$SCRIPTDIR/network

#-------------------------------------------------------------------------------

show_avail_devices()
{
	echo available devices:
	lsblk --list --scsi --noheadings --output NAME,TYPE,TRAN
}

#-------------------------------------------------------------------------------
#inactive
do_boot_config()
{
	local file=$MNTDIR/config.txt

	grep --quiet "gpu_mem=16" $file
	if [ "$?" -ne "0" ]; then
		echo "update $file gpio_pin $1 ..."

		sudo cp -f $file $file.orig
		cat <<-EOF | sudo tee --append $file
		EOF

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured"
	fi
}

#-------------------------------------------------------------------------------

do_boot_cmdline()
{
	local file=$MNTDIR/cmdline.txt

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
	local file=$MNTDIR/ssh

	if [ ! -f "$file" ]; then
		echo -e "\nenabling ssh ..."

		touch $file
		ls -l $file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured"
	fi
}

#-------------------------------------------------------------------------------

do_wifi()
{
	local file=$WPAFILE

	if [ ! -f "$file" ]; then
		echo -e "\nenabling wifi ..."

		# Config and enable wifi.  Note: no spaces to either side of equals sign
		cat > $file <<-WPA
		country=US
		ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
		update_config=1
		WPA

		# add the wifi credentials
		if [ -e $NETFILE ]; then
			cat $NETFILE >> $file
		fi

		ls -l $file
	else
		echo "$file already configured"
	fi
}

#-------------------------------------------------------------------------------

do_tools()
{
	# copy over config tools
	mkdir --verbose $MNTDIR/tools
	cp README.md config.sh prep.sh $MNTDIR/tools
}

#-------------------------------------------------------------------------------
# main

if [ "$#" -ne 2 ]; then
    echo "usage: prep.sh <raspbian img file> <block device to write image to>"
	show_avail_devices
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

disk=`basename $dev`

# Make sure it's the disk and not one of it's partitions/devices
if [ ! -e /sys/block/$disk ]; then
	echo "$dev does not appear to be a (whole) disk"
	exit 1
fi

# Ensure it's not already mounted
if [ `grep --count $dev /proc/mounts` -gt 0 ]; then
    echo "$dev is already mounted"
    exit 1
fi

if [ -f $MNTDIR ] || [ -d $MNTDIR ]; then
	echo "$MNTDIR already exists"
	exit 1
fi

# Check if this is an image file
filetype=`file "$img" | grep -o "DOS/MBR"`
if [ "$filetype" != "DOS/MBR" ]; then
	echo "$img does not appear to be image file"
	exit 1
fi

show_avail_devices

imgsize=`du --block-size=1M $img | cut -f1`

echo --------------------------------------------------------------------------------
echo Setup workspace
echo --------------------------------------------------------------------------------

echo "Img file         : $img"
echo "Img size         : $imgsize MiB"
echo "Target           : $dev"
echo "SSH              : on"
echo "WiFi credentials : $NETFILE"
echo

if [ ! -e $NETFILE ]; then
	read -p "WiFi credential file (./network) not found.  Continue? [y|N]" yn
	case $yn in
		([Yy]* ) break;;
		([Nn]* ) exit;;
		("" ) exit;;
	esac
fi

config_count=0

echo "flashing $img (${imgsize} MiB) ..."
sudo dd if=$img status=progress of=$dev bs=1M

echo "mounting boot partition..."
if [ ! -d $MNTDIR ]; then
	mkdir --verbose $MNTDIR
fi
sudo mount --verbose --types vfat ${dev}1 $MNTDIR --options rw,umask=0000
sudo df

#do_boot_config
do_boot_cmdline
do_ssh
do_wifi
do_tools

ls -l $MNTDIR
cat $WPAFILE

sudo umount $MNTDIR

rm --recursive --force --verbose $MNTDIR

echo "done"
