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

	apt --yes update
	apt --yes install lirc lirc-doc
}

#-------------------------------------------------------------------------------

do_boot_config()
{
	local file=/boot/config.txt

	grep --no-messages "dtoverlay=gpio-ir-tx" $file
	if [ "$?" -ne "0" ]; then
		echo "update $file dtoverlay=gpio-ir-tx ..."

		cp -f $file $file.orig
		cat >> $file <<-EOF

			# IR Remote Settings
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

	grep --no-messages "lirc0" $file
	if [ "$?" -ne "0" ]; then
		echo "create $file port $1 ..."

		dir=`dirname $file`
		if [ ! -d $dir ]; then
			mkdir --verbose $dir
		fi

		if [ -e $file ]; then
			cp -vf $file $file.orig
		fi

		cat > $file <<-EOF
			# IR Remote Settings

			[lircd]
			nodaemon        = False
			driver          = default
			device          = /dev/lirc0
			output          = /var/run/lirc/lircd
			pidfile         = /var/run/lirc/lircd.pid
			plugindir       = /usr/lib/arm-linux-gnueabihf/lirc/plugins
			logfile         = /var/log/lirc.log
			loglevel        = 6
			permission      = 666
			allow-simulate  = No
			repeat-max      = 600
			listen          = $1
			#effective-user =
			#connect        = host[:port]
			#release        = true
			#release_suffix = _EVUP
			#driver-options = ...

			# todo: turn this off?
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
	local dir=/etc/lirc/lircd.conf.d
	local file=/etc/lirc/lircd.conf

	if [ ! -e $file ]; then
		echo "create $file ..."

		if [ ! -d $dir ]; then
			mkdir --parents --verbose $dir
		fi

		cat > $file <<-EOF
			include "lircd.conf.d/*.conf"
		EOF

		config_count=$(( $config_count + 1 ))
	else
		echo "$file already configured"
	fi
}

#-------------------------------------------------------------------------------
# The following functions are no longer used or have been superceded by above.

#-------------------------------------------------------------------------------
# This is a legacy file for Raspbian pre Stretch

do_etc_modules()
{
	echo
	echo "update /etc/modules ..."

	grep --quiet "lirc_dev" /etc/modules
	if [ "$?" -ne "0" ]; then
		cp -vf /etc/modules /etc/modules.orig
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
			cp -vf /etc/lirc/hardware.conf /etc/lirc/hardware.conf.orig
		fi

		cat <<-EOF | sudo tee --append /etc/lirc/hardware.conf
			# /etc/lirc/hardware.conf
			#
			# Arguments which will be used when launching lircd
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

		config_count=$(( $config_count + 1 ))
	else
		echo "/etc/lirc/hardware.conf already configured"
	fi
}

#-------------------------------------------------------------------------------
# main

SCRIPTDIR=$(dirname $0)
LIRCPORT=8765
LIRCPIN=22  # Pin #17 is the standard IR send pin
UNAME=$(uname -a)

if [ `id -u` -ne "0" ]; then
	echo "must run as root"
	exit 1
fi

. /etc/os-release

echo
echo --------------------------------------------------------------------------------
echo Config System
echo --------------------------------------------------------------------------------
echo "System        : $UNAME"
echo "Release       : $NAME $VERSION"
echo

config_count=0

do_boot_config $LIRCPIN
do_lirc_options $LIRCPORT
do_lircd_conf
do_packages

echo
echo "made $config_count config changes"

# See if we did anything and should reboot
if [ $config_count -gt 0 ]; then
	echo rebooting in 10 seconds ...
	sleep 10
	reboot
fi

# After first reboot.  If you rerun the script after boot it should detect zero
# changes are in the pre-boot stuff and skip the reboot landing us here.

echo
echo "enable Lirc service ..."

systemctl enable lircd
systemctl start lircd
systemctl status lircd

echo
echo "made $config_count config changes"
echo
echo "done"
