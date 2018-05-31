# remsetup
Scripts for building and configuring Raspbian for Lirc remote control

Starting remsetup project to attempt to write a set of scripts to build
and config a Raspbian Jessie image for use as a remote box.  This will
probably include these things

- Raspbian Jessie
- Configure wifi and headless build via ssh
- configure raspi-config settings
- Update OS

- configure lirc

- Add packages
   * Python
   * lirc


http://paulmouzas.github.io/python/http/sockets/2015/03/29/roku-remote.html


Setup
-----

Set credentials using
```bash
	. vars
```

Use prep.sh to flash and config

Boot

Run sudo raspi-config
1. Change password
2. Change hostname
4. Change locale timezone keyboard wifi-country
7. Change Memory split

#### potential automation:
add to /etc/hostname file
append "gpu_mem=16" to /boot/config.txt
add "en_US.UTF-8 UTF-8" to /etc/locale.gen
create /etc/timezone with US/Eastern

pi@raspberrypi:/etc/default $ cat locale
```bash
	#  File generated by update-locale
	LANG=C.UTF-8
```
pi@raspberrypi:/etc/default $ cat keyboard
		# KEYBOARD CONFIGURATION FILE

		# Consult the keyboard(5) manual page.

		XKBMODEL="pc101"
		XKBLAYOUT="us"
		XKBVARIANT=""
		XKBOPTIONS="lv3:ralt_alt"

		BACKSPACE="guess"

sudo apt-get -y update
sudo apt-get -y upgrade

Fix bug in /etc/rsyslog.conf to no longer refer to xconsole to prevent annoying syslog errors

install:
		sudo apt-get -y install lirc
		sudo apt-get -y install subversion
		sudo apt-get -y install git

Maybe:
- vim
- wiringpi

svn checkout svn://server/home/Shared/repository/projects

Lirc:

### add to /boot/config.txt:

	dtoverlay=lirc-rpi,gpio_in_pin=23,gpio_out_pin=22,gpio_in_pull=up


### add to /etc/modules:

	lirc_dev
	lirc_rpi gpio_in_pin=23 gpio_out_pin=22


update /etc/lirc/hardware.conf to match this:

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
	DRIVER="default"
	# usually /dev/lirc0 is the correct setting for systems using udev
	DEVICE="/dev/lirc0"
	MODULES="lirc_rpi"

	# Default configuration files for your hardware if any
	LIRCD_CONF=""
	LIRCMD_CONF=""


reboot

test receive:

sudo /etc/init.d/lirc stop
mode2 -d /dev/lirc0


test send:

# Stop lirc to free up /dev/lirc0
sudo /etc/init.d/lirc stop

# Create a new remote control configuration file (using /dev/lirc0) and save the output to ~/lircd.conf
irrecord -d /dev/lirc0 ~/lircd.conf

# Make a backup of the original lircd.conf file
sudo mv /etc/lirc/lircd.conf /etc/lirc/lircd_original.conf

# Copy over your new configuration file
sudo cp ~/lircd.conf /etc/lirc/lircd.conf

# Start up lirc again
#sudo /etc/init.d/lirc start
sudo service lirc start
sudo /etc/init.d/lirc status

# list all commands
irsend list /home/pi/lircd.conf ""

------------------------------------------------------------

see projects/lirc for info on coding lircd.conf files

------------------------------------------------------------

# NOTES FROM 3/19/2017

The parameters in /etc/modules for lirc_rpi seem to cause an error message in /var/log/syslog:

	Mar 19 10:36:54 raspberrypi systemd-modules-load[89]: Inserted module 'lirc_dev'
	Mar 19 10:36:54 raspberrypi systemd-modules-load[89]: Failed to find module 'lirc_rpi gpio_in_pin=23 gpio_out_pin=22'

It's possible that since these options are now specified in the /boot/config.txt file that they
aren't even necessary.  I excluded them on the zero and it seems to still work and the message goes away.

So for the Pi Zero W the config options are as follows.  Since we aren't using the receiver don't list it.  
/boot/config.txt:

	# Uncomment this to enable the lirc-rpi module
	dtoverlay=lirc-rpi
	dtparam=gpio_out_pin=22

add to /etc/modules:

	lirc_dev
	lirc_rpi

Seemingly at random irsend will stop working yet not complain.  The pin will work but irsend will stop sending.  A couple
of people in various forums recommend adding the explicit socket command to the irsend command.  i.e.:

	irsend -d /var/run/lirc/lircd send_once AA59 KEY_VOLUMEUP

Info on remotes in: http://www.lirc.org/remotes



--------------------------------------------------------------------------------

10/22/2017

# Setting up remote with stretch on a Raspberry Pi Zero W

## Setting up the Raspbian SD card

Download the current Lite version of Raspbian from https://www.raspberrypi.org/downloads.  The Lite version is smaller and does not include a desktop which is not needed for a headless box.  Copy the image to a micro SD card of at least 4GB.  You can't just copy it to the card.  You want to reimage the card itself using the Raspbian boot image.  There are instructions for WIndowns if you follow the links from the downloads page.

For Linux use /proc/partitions and/or /dev to locate the device with the SD card,  If the card does not appear then try unplugging and replugging the card reader itself.

	cat /proc/partitions
	ls /dev
	dd if=2017-09-07-raspbian-stretch-lite.img of=/dev/sdx bs=64K

We need to add some files to the boot partition to permit Raspbian to boot headless and connect to the LAN wirelessly.  Windows should mount the first partition (which is formatted FAT) automatically.

For Linux mount the drive for in RW mode:

	sudo mount -t vfat /dev/sdx1 /mnt/disk -o rw,umask=0000

Add two files.  An empty file named `ssh` and a file named `wpa_supplicant.conf` with the SSID and password of the wireless access point to connect to:

	cd /mnt/disk
	cat > wpa_supplicant.conf
	network={
	  ssid="Linksys18889"
	  psk="rminkkf1jk"
	}

Unmount or eject the SD card.

	cd /mnt
	sudo umount /mnt/disk


## First Boot
	











# Package List:

