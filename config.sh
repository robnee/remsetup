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

	apt --yes update --allow-releaseinfo-change
	apt --yes update
	apt --yes upgrade

	apt --yes install git vim python3-pip
	apt --yes autoremove
	# optional
	# apt --yes install powertop cpufrequtils

	pip3 install virtualenv
}

#-------------------------------------------------------------------------------
# main

SCRIPTDIR=$(dirname $0)
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

# prep.sh and lirc.sh do all the rest
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
echo "made $config_count config changes"
echo
echo "done"
