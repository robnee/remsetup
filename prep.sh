#!/bin/bash
#
# last delta : $LastChangedDate$
# rev        : $Rev$

# Get the date info
day=`date +%A`
dom=`date +%d`
dow=`date +%w`
mon=`date +%B`
ymd=`date +%Y-%m-%d`
start_time=`date +'%Y-%m-%d %H:%M:%S'`

TARGETDEV=/dev/sdb
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

if [ "$#" -ne 1 ]; then
    echo "usage: prep.sh <raspbian zip file>"
	exit
fi

if [ ! -f "$1" ]; then
	echo "$1 does not exist"
	exit
fi

if [ -f $MNTDIR ] || [ -d $MNTDIR ]; then
	echo "$MNTDIR already exists"
	exit
fi

# Check if this is an image file
filetype=`file "$1" | grep -o "DOS/MBR"`
if [ "$filetype" != "DOS/MBR" ]; then
	echo "$1 does not appear to be image file"
	exit
fi

imgsize=`du --block-size=1MB $1 | cut -f1`
echo $1 size $imgsize

echo --------------------------------------------------------------------------------
echo Setup workspace
echo --------------------------------------------------------------------------------

echo "Img file      : $1"
echo "Img size      ; $imgsize MB"
echo "Target        : $TARGETDEV"
echo

echo "flashing image..."
sudo dd if=$1 status=progress of=$TARGETDEV bs=1M

echo "configuring wifi and ssh..."
if [ ! -d $MNTDIR ]; then
	mkdir $MNTDIR
fi

sudo mount -t vfat ${TARGETDEV}1 $MNTDIR -o rw,umask=0000

sudo df

touch $MNTDIR/ssh
cat > $WPAFILE <<WPA
network={
	ssid="$WPASSID"
	psk= "$WPAPSK"
}
WPA

ls -l $MNTDIR
cat $WPAFILE

sudo umount $MNTDIR

rm -rf $MNTDIR

echo "done"
