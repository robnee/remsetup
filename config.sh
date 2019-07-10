#!/bin/bash
#
# last delta : $LastChangedDate$
# rev        : $Rev$
#
# config the system.  This file is meant to be copied to the target system (maybe
# via the boot partition) to run on first boot

#-------------------------------------------------------------------------------

do_packages()
{
	echo
	echo "package install update and install ..."

	sudo apt-get --yes update
	sudo apt-get --yes upgrade

	sudo apt-get --yes install git
	sudo apt-get --yes install subversion
	sudo apt-get --yes install lirc
}

#-------------------------------------------------------------------------------

do_boot_config()
{
	echo
	echo "update /boot/config.txt ..."

	grep --quiet "gpu_mem=16" /boot/config.txt
	if [ "$?" -ne "0" ]; then
		sudo cp -f /boot/config.txt /boot/config.txt.orig
		cat <<-EOF | sudo tee --append /boot/config.txt

			# IR Remote Settings
			gpu_mem=16
			dtoverlay=gpio-ir,gpio_out_pin=22
		EOF

		config_count=$(( $config_count + 1 ))
	else
		echo "/boot/config.txt already configured"
	fi
}

#-------------------------------------------------------------------------------

do_etc_modules()
{
	echo
	echo "update /etc/modules ..."

	#todo: maybe this does nothing?
	grep --quiet "lirc_dev" /etc/modules
	if [ "$?" -ne "0" ]; then
		sudo cp -vf /etc/modules /etc/modules.orig
		cat <<-EOF | sudo tee --append /etc/modules
		
			# IR Remote Settings
			lirc_dev
			lirc_rpi gpio_in_pin=23 gpio_out_pin=22
		EOF

		config_count=$(( $config_count + 1 ))
	else
		echo "/etc/modules already configured"
	fi
}

#-------------------------------------------------------------------------------

do_lirc_hardware()
{
	echo
	echo "update /etc/lirc/hardware.conf ..."

	grep --quiet "listen" /etc/lirc/hardware.conf
	if [ "$?" -ne "0" ]; then
		if [ -e /etc/lirc/hardware.conf ]; then
			sudo cp -vf /etc/lirc/hardware.conf /etc/lirc/hardware.conf.orig
		fi

		cat <<-EOF | sudo tee --append /etc/lirc/hardware.conf
			# /etc/lirc/hardware.conf
			#
			# Arguments which will be used when launching lircd
			#LIRCD_ARGS="--uinput"
			LIRCD_ARGS="--listen"
			
			# Don't start lircmd even if there seems to be a good config file
			# START_LIRCMD=false
			q
			
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

		config_count=$(( $config_count + 1 ))
	else
		echo "/etc/lirc/hardware.conf already configured"
	fi
}

#-------------------------------------------------------------------------------

do_lirc_options()
{
	echo
	echo "create /etc/lirc/lirc_options.conf ..."

	grep --quiet "lirc0" /etc/lirc/lirc_options.conf
	if [ "$?" -ne "0" ]; then
		if [ -e /etc/lirc/lirc_options.conf ]; then
			sudo cp -vf /etc/lirc/lirc_options.conf /etc/lirc/lirc_options.conf.orig
		fi

		cat <<-EOF | sudo tee /etc/lirc/lirc_options.conf
			# IR Remote Settings

			[lircd]
			nodaemon        = False
			driver          = default
			device          = /dev/lirc0
			output          = /var/run/lirc/lircd
			pidfile         = /var/run/lirc/lircd.pid
			plugindir       = /usr/lib/arm-linux-gnueabihf/lirc/plugins
			permission      = 666
			allow-simulate  = No
			repeat-max      = 600
			#effective-user =
			#listen         = [address:]port
			#connect        = host[:port]
			#loglevel       = 6
			#release        = true
			#release_suffix = _EVUP
			#logfile        = ...
			#driver-options = ...

			[lircmd]
			uinput          = False
			nodaemon        = False

			# [modinit]
			# code = /usr/sbin/modprobe lirc_serial
			# code1 = /usr/bin/setfacl -m g:lirc:rw /dev/uinput
			# code2 = ...


			# [lircd-uinput]
			# add-release-events = False
			# release-timeout    = 200
			# release-suffix     = _EVUP
		EOF

		config_count=$(( $config_count + 1 ))
	else
		echo "/etc/lirc/lirc_options.conf already configured"
	fi
}

#-------------------------------------------------------------------------------

# Get the date info
day=`date +%A`
dom=`date +%d`
dow=`date +%w`
mon=`date +%B`
ymd=`date +%Y-%m-%d`
start_time=`date +'%Y-%m-%d %H:%M:%S'`

MNTDIR=./mnt
LOGDIR=./logs
LOGFILE=$LOGDIR/$ymd.log
SCRIPTDIR=$(dirname $0)
HOSTNAME=$(hostname)
UNAME=$(uname -a)

config_count=0

echo
echo --------------------------------------------------------------------------------
echo Config System
echo --------------------------------------------------------------------------------

echo "Hostname      : $HOSTNAME"
echo "System        : $UNAME"
echo

do_packages
do_boot_config
do_lirc_hardware
do_lirc_options

echo
echo "create /etc/lirc/lircd.conf ..."

if [ ! -e /etc/lirc/lircd.conf ]; then
	cat <<-EOF | sudo tee /etc/lirc/lircd.conf
		# IR Remote Settings

		#include "TV.conf"
		#include "CABLE.conf"
		#include "RECEIVER.conf"
	EOF

	config_count=$(( $config_count + 1 ))
else
	echo "/etc/lirc/lircd.conf already configured"
fi

echo
echo "enable Lirc service ..."

# See if we should reboot
if [ $config_count -gt 0 ]; then
	echo rebooting in 10 seconds ...
	sleep 10
	sudo reboot
fi

# After first reboot
sudo systemctl enable lircd
sudo systemctl start lircd
sudo systemctl status lircd

echo
echo "made $config_count config file changes"
echo
echo "done"
