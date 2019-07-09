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
	sudo cp -f /boot/config.txt /boot/config.txt.orig
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
	sudo cp -f /etc.modules /etc/modules.orig
	cat <<-EOF | sudo tee --append /etc/modules
	
		# IR Remote Settings
		lirc_dev
		lirc_rpi gpio_in_pin=23 gpio_out_pin=22
	EOF
else
	echo "/etc/modules already configured"
fi

echo
echo "update /etc/lirc/hardware.conf ..."

grep --quiet "--listen" /etc/lirc/hardware.conf
if [ "$?" -ne "0" ]; then
	sudo cp -f /etc.modules /etc/lirc/hardware.conf
	
	cat <<-EOF | sudo tee -a /etc/lirc/hardware.conf
		# /etc/lirc/hardware.conf
		#
		# Arguments which will be used when launching lircd
		# todo: look up the meaning of --listen and document here
		#LIRCD_ARGS="--uinput"
		LIRCD_ARGS="--listen"
		
		# Don't start lircmd even if there seems to be a good config file
		# START_LIRCMD=false
		
		# Don't start irexec, even if a good config file seems to exist.
		# START_IREXEC=false
		
		# Try to load appropriate kernel modules
		LOAD_MODULES=true
		
		# Run "lircd --driver=help" for a list of supported drivers.
		# todo: what does this option do?
		DRIVER="default"
		# usually /dev/lirc0 is the correct setting for systems using udev
		DEVICE="/dev/lirc0"
		MODULES="lirc_rpi"
		
		# Default configuration files for your hardware if any
		LIRCD_CONF=""
		LIRCMD_CONF=""
	EOF
else
	echo "/etc/lirc/hardware.conf already configured"
fi

echo
echo "done"
