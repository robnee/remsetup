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

echo --------------------------------------------------------------------------------
echo Config System
echo --------------------------------------------------------------------------------

echo "Img file      : $1"
echo "Img size      ; $imgsize MB"
echo "Target        : $TARGETDEV"
echo

echo "package install update and install ..."
sudo apt-get -y update
sudo apt-get -y upgrade

sudo apt-get -y install lirc
sudo apt-get -y install git
sudo apt-get -y install subversion

echo "update /boot/config.txt ..."

grep --quiet "gpu_mem=16" /etc/modules
if [ "$?" -ne "0" ]; then
	#sudo cat >> /boot/config.txt <<-EOF
	sudo cat <<-EOF

		# IR Remote Settings
		gpu_mem=16
		dtoverlay=lirc-rpi,gpio_in_pin=23,gpio_out_pin=22,gpio_in_pull=up
EOF
fi

echo "update /etc/modules ..."

grep --quiet "lirc_dev" /etc/modules
if [ "$?" -ne "0" ]; 
	sudo cat >> /etc/modules <<-EOF
		lirc_dev
		lirc_rpi gpio_in_pin=23 gpio_out_pin=22
EOF

echo "done"