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

MNTDIR=./mnt
WPAFILE=$MNTDIR/wpa_supplicant.conf
LOGDIR=./logs
LOGFILE=$LOGDIR/$ymd.log

# for better security set these in environment rather than hardcoded here
#WPASSID=
#WPAPSK=

SCRIPTDIR=$(dirname $0)

#-------------------------------------------------------------------------------

# . $SCRIPTDIR/lib.sh

#-------------------------------------------------------------------------------

if [ "$#" -ne 2 ]; then
    echo "usage: prep.sh <raspbian img file> <block device to write image to>"
	exit 1
fi

if [ ! -f "$1" ]; then
	echo "$1 does not exist"
	exit 1
fi

dev=$2

echo available devices
lsblk --list --scsi --noheadings --output NAME,TYPE,TRAN

if [ ! -e "$dev" ]; then
	echo "$2 does not exist"
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
filetype=`file "$1" | grep -o "DOS/MBR"`
if [ "$filetype" != "DOS/MBR" ]; then
	echo "$1 does not appear to be image file"
	exit 1
fi

imgsize=`du --block-size=1MB $1 | cut -f1`
echo $1 size $imgsize

echo --------------------------------------------------------------------------------
echo Setup workspace
echo --------------------------------------------------------------------------------

echo "Img file         : $1"
echo "Img size         : $imgsize MB"
echo "Target           : $dev"
echo "SSH              : on"
echo "WiFi credentials : $WPASSID /" `echo $WPAPSK | cut -c1-3`"..."
echo

if [ "$WPASSID" == "" ] || [ "$WPAPSK" == "" ]; then
	read -p "WiFi credentials not set.  Continue? [y|N]" yn
	case $yn in
		([Yy]* ) break;;
		([Nn]* ) exit;;
		("" ) exit;;
	esac
fi

echo "flashing image..."
sudo dd if=$1 status=progress of=$dev bs=1M

echo "configuring wifi and ssh..."
if [ ! -d $MNTDIR ]; then
	mkdir --verbose $MNTDIR
fi

sudo mount --verbose --types vfat ${dev}1 $MNTDIR --options rw,umask=0000

sudo df

# Enable ssh
touch $MNTDIR/ssh

# Config and enable wifi.  Note: no spaces to either side of equals sign
cat > $WPAFILE <<WPA
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
network={
	ssid="$WPASSID"
	psk="$WPAPSK"
	key_mgmt=WPA-PSK
}
WPA

# copy over config files
mkdir --verbose $MNTDIR/tools
cp README.md config.sh prep.sh $MNTDIR/tools

ls -l $MNTDIR
cat $WPAFILE

sudo umount $MNTDIR

rm --recursive --force --verbose $MNTDIR

echo "done"
