#!/bin/bash
#
# last delta : $LastChangedDate$
# rev        : $Rev$
#
# config the system.  This file is meant to be copied to the target system (maybe
# via the boot partition) to run on first boot

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

echo --------------------------------------------------------------------------------
echo Config System
echo --------------------------------------------------------------------------------

echo "Img file      : $1"
echo "Img size      ; $imgsize MB"
echo "Target        : $TARGETDEV"
echo

echo
echo "package install update and install ..."

sudo apt-get --yes update
sudo apt-get --yes upgrade

sudo apt-get --yes install lirc
sudo apt-get --yes install git
sudo apt-get --yes install subversion

echo
echo "update /boot/config.txt ..."

grep --quiet "gpu_mem=16" /boot/config.txt
if [ "$?" -ne "0" ]; then
	cat <<-EOF | sudo tee --append /boot/config.txt

		# IR Remote Settings
		gpu_mem=16
		dtoverlay=lirc-rpi,gpio_in_pin=23,gpio_out_pin=22,gpio_in_pull=up
	EOF
else
	echo "/boot/config.txt already configured"
fi

echo
echo "update /etc/modules ..."

grep --quiet "lirc_dev" /etc/modules
if [ "$?" -ne "0" ]; then
	cat <<-EOF | sudo tee --append /etc/modules
		lirc_dev
		lirc_rpi gpio_in_pin=23 gpio_out_pin=22
	EOF
else
	echo "/etc/modules already configured"
fi

echo
echo "done"
