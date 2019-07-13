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

	sudo apt --yes update --allow-releaseinfo-change
	sudo apt --yes update
	sudo apt --yes upgrade

	sudo apt --yes install git subversion lirc lirc-doc
}

#-------------------------------------------------------------------------------

do_timezone()
{
	local file=/etc/timezone

	grep --quiet "$1" $file
	if [ "$?" -ne "0" ]; then
		echo "Set $file to $1 ..."

		sudo timedatectl set-timezone $1

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already set to $1"
	fi
}

#-------------------------------------------------------------------------------

do_hostname()
{
	local file=/etc/hostname

	grep --quiet "$1" $file
	if [ "$?" -ne "0" ]; then
		echo "Set $file to $1 ..."

		echo $1 | sudo dd status=none of=$file

		sed s/raspberrypi/$1/ /etc/hosts | sudo dd status=none of=/etc/hosts

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already set to $1"
	fi
}

#-------------------------------------------------------------------------------

do_locale()
{
	local file=/etc/default/locale

	grep --quiet "$1" $file
	if [ "$?" -ne "0" ]; then
		echo "Set $file to $1 ..."

		echo LANG=$1 | sudo dd status=none of=$file

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already set to $1"
	fi
}

#-------------------------------------------------------------------------------

do_keyboard()
{
	local file=/etc/default/keyboard

	grep --quiet "$1" $file
	if [ "$?" -ne "0" ]; then
		echo "set $file to $1 $2 ..."

		sudo cp -f $file $file.orig
		cat <<-EOF | sudo dd status=none of=$file
		    # IR Remote Settings
		    XKBMODEL="$1"
		    XKBLAYOUT="$2"
		    XKBVARIANT=""
		    XKBOPTIONS=""

		    BACKSPACE="guess"
		EOF

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already set to $1 $2"
	fi
}

#-------------------------------------------------------------------------------

do_boot_config()
{
	local file=/boot/config.txt

	grep --quiet "gpu_mem=16" $file
	if [ "$?" -ne "0" ]; then
		echo "update $file gpio_pin $1 ..."

		sudo cp -f $file $file.orig
		cat <<-EOF | sudo tee --append $file

			# IR Remote Settings
			gpu_mem=16
			dtoverlay=gpio-ir-tx,gpio_pin=$1
		EOF

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured"
	fi
}

#-------------------------------------------------------------------------------

do_lirc_options()
{
	local file=/etc/lirc/lirc_options.conf

	grep --quiet "lirc0" $file
	if [ "$?" -ne "0" ]; then
		echo "create $file port $1 ..."

		if [ -e $file ]; then
			sudo cp -vf $file $file.orig
		fi

		cat <<-EOF | sudo tee $file
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
			listen          = $1
			#connect        = host[:port]
			logfile         = /var/log/lirc.log
			loglevel        = 6
			#release        = true
			#release_suffix = _EVUP
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
		echo "$file already configured"
	fi
}

#-------------------------------------------------------------------------------

do_lircd_conf()
{
	local file=/etc/lirc/lircd.conf

	if [ ! -e $file ]; then
		echo "create $file ..."

		cat <<-EOF | sudo tee $file
			# IR Remote Settings

			#include "TV.conf"
			#include "CABLE.conf"
			#include "RECEIVER.conf"
		EOF

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured"
	fi
}

#-------------------------------------------------------------------------------
# This is a legacy file for Raspbian pre Stretch

do_etc_modules()
{
	echo
	echo "update /etc/modules ..."

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
# this is for versions of Lirc prior to 0.9.4

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

# Get the date info
day=`date +%A`
dom=`date +%d`
dow=`date +%w`
mon=`date +%B`
ymd=`date +%Y-%m-%d`
start_time=`date +'%Y-%m-%d %H:%M:%S'`

SCRIPTDIR=$(dirname $0)
HOSTNAME=remstage
LIRCPORT=8765
LIRCPIN=23
UNAME=$(uname -a)

. /etc/os-release

echo
echo --------------------------------------------------------------------------------
echo Config System
echo --------------------------------------------------------------------------------

echo "Hostname      : $HOSTNAME"
echo "System        : $UNAME"
echo "Release       : $NAME $VERSION"

config_count=0

do_hostname $HOSTNAME
do_timezone "America/New_York"
do_locale "C.UTF-8"
do_keyboard "pc101" "us"

do_packages
do_boot_config $LIRCPIN
do_lirc_options $LIRCPORT
do_lircd_conf

echo
echo "made $config_count config file changes"

# See if we should reboot
if [ $config_count -gt 0 ]; then
	echo rebooting in 10 seconds ...
	sleep 10
	sudo reboot
fi

# After first reboot
`
echo
echo "enable Lirc service ..."

sudo systemctl enable lircd
sudo systemctl start lircd
sudo systemctl status lircd

echo
echo "made $config_count config file changes"
echo
echo "done"
