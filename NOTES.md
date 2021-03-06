# remsetup

Scripts for building and configuring Raspbian for Lirc remote control

Starting remsetup project to attempt to write a set of scripts to build and config a Raspbian image for use as a remote box.  This will probably include these things

- Raspbian Lite image
- Configure wifi and headless build via ssh
- configure raspi-config settings
- Update OS
- configure lirc

- Add packages
   1. Python
   2. lirc

> http://paulmouzas.github.io/python/http/sockets/2015/03/29/roku-remote.html

## Setup

### Set credentials using

	. vars

### Use prep.sh to flash and config

Boot

### Run sudo raspi-config:

1. Change password
2. Change hostname
4. Change locale timezone keyboard wifi-country
7. Change Memory split

## potential for automation:

### hostname (AUTOMATED)

	echo hostname > /etc/hostname file

### memory split (AUTOMATED)

	echo "gpu_mem=16" >> /boot/config.txt


	add "en_US.UTF-8 UTF-8" to /etc/locale.gen

### timezone (AUTOMATED)

	echo US/Eastern > etc/timezone
	ln -s usr/share/zoneinfo/US/Eastern /etc/localtime

### locale (AUTOMATED)

	echo "LANG=C.UTF-8" > /etc/default/locale

### /etc/default/keyboard

	# KEYBOARD CONFIGURATION FILE

### Consult the keyboard(5) manual page.  Todo: compare raw file with file after raspi-config

	XKBMODEL="pc101"
	XKBLAYOUT="us"
	XKBVARIANT=""
	XKBOPTIONS="lv3:ralt_alt"
	
	BACKSPACE="guess"

## Installing Packages

	sudo apt-get -y update
	sudo apt-get -y upgrade
	
	sudo apt-get -y install lirc
	sudo apt-get -y install git


## Lirc Setup

### add to /boot/config.txt:

	dtoverlay=lirc-rpi,gpio_in_pin=23,gpio_out_pin=22,gpio_in_pull=up

### add to /etc/modules:

	lirc_dev
	lirc_rpi gpio_in_pin=23 gpio_out_pin=22

### update /etc/lirc/hardware.conf 

We are only sending IR commands.  we don't need to enable or config any of the IR receive services.  We also want the Lirc daemon  to listen for commands to send on its local port.

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

### Reboot

Much frustration can be avoided be rebooting before testing

## Troubleshooting

### Check for syslog errors

Fix bug in /etc/rsyslog.conf to no longer refer to xconsole to prevent annoying syslog errors for headless systems not running an X desktop.  This may no longer be necessary in Stretch onward.

The parameters in /etc/modules for lirc_rpi seem to cause an error message in /var/log/syslog:

	Mar 19 10:36:54 raspberrypi systemd-modules-load[89]: Inserted module 'lirc_dev'
	Mar 19 10:36:54 raspberrypi systemd-modules-load[89]: Failed to find module 'lirc_rpi gpio_in_pin=23 gpio_out_pin=22'

It's possible that since these options are now specified in the /boot/config.txt file that they aren't even necessary.  I excluded them on the zero and it seems to still work and the message goes away.

So for the Pi Zero W the config options are as follows.  Since we aren't using the receiver don't list it. 

/boot/config.txt:

	# Uncomment this to enable the lirc-rpi module
	dtoverlay=lirc-rpi
	dtparam=gpio_out_pin=22

 Edit to /etc/modules:

	lirc_dev
	lirc_rpi

### random send failures

Seemingly at random irsend will stop working yet not complain.  The pin will work but irsend will stop sending.  A couple of people in various forums recommend adding the explicit socket command to the irsend command.  i.e.:

	irsend -d /var/run/lirc/lircd send_once AA59 KEY_VOLUMEUP

Todo: is this still an issue?


## test IR receive

	sudo /etc/init.d/lirc stop
	mode2 -d /dev/lirc0


## Create Lirc .conf file

See projects/lirc for info on coding lircd.conf files.  It's also possible to create a file by recording IR commands.

### Stop lirc to free up /dev/lirc0

	sudo /etc/init.d/lirc stop

### Create a new remote control configuration file (using irrecord) to ~/lircd.conf

	irrecord -d /dev/lirc0 ~/lircd.conf

### Make a backup of the original lircd.conf file

	sudo mv /etc/lirc/lircd.conf /etc/lirc/lircd_original.conf

### Copy over your new configuration file

	sudo cp ~/lircd.conf /etc/lirc/lircd.conf

### Start up lirc again

	sudo /etc/init.d/lirc start
	sudo service lirc start
	sudo /etc/init.d/lirc status

### list all devices and commands

Note the empty quoted string as placeholder for (required) key argument.

	irsend list "" ""

## Test IR Send

	irsend send_once <device> <key>

	$ irsend SEND_ONCE <device-name> KEY_POWER
	$ irsend SEND_ONCE <device-name> KEY_VOLUMEUP

## Config application

	svn checkout svn://server/home/Shared/repository/projects


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

Add two files.  An empty file named `ssh` and a file named `wpa_supplicant.conf` with the SSID and password of the wireless access point to connect to.  Be careful to not included spaces around the equals signs:

	cd /mnt/disk
	cat > wpa_supplicant.conf
	network={
	  ssid=
	  psk=
	}

Unmount or eject the SD card.

	cd /mnt
	sudo umount /mnt/disk


## First Boot

### Scan for hosts

	nmap -sP 192.168.1.* | grep scan

ssh pi@raspberrypi

Run:
	/boot/tools/config.sh

after reboot run it again to finish config

	/boot/tools/config.sh

get projects

	cd ~
	mkdir projects
	cd projects
	svn checkout svn+ssh://rnee@centos7/home/Shared/repository/projects/bottle
	svn checkout svn+ssh://rnee@centos7/home/Shared/repository/projects/rnee
	svn checkout svn+ssh://rnee@centos7/home/Shared/repository/projects/lirc

Setup IR Remote applications

	cd bottle
	virtualenv venv
	. venv/bin/activate
	pip3 install -r requirements.txt


#### Configure for low power:

- Turn off HDMI

	/usr/bin/tvservice -o (-p to re-enable). Add the line to /etc/rc.local to disable HDMI on boot.

- Turn off LEDs

If you want to turn off the LED on the Pi Zero completely, run the following two commands:

	# Set the Pi Zero ACT LED trigger to 'none'.
	echo none | sudo tee /sys/class/leds/led0/trigger

	# Turn off the Pi Zero ACT LED.
	echo 1 | sudo tee /sys/class/leds/led0/brightness

To make these settings permanent, add the following lines to your Pi's /boot/config.txt file and reboot:

	# Disable the ACT LED on the Pi Zero.
	dtparam=act_led_trigger=none
	dtparam=act_led_activelow=on

06/24/2019

NOTE: (02/2020) this is no loger relevent for Stretch onward and Lirc 0.10+

GitHub gist: https://gist.githubusercontent.com/prasanthj/c15a5298eb682bde34961c322c95378b/raw/1c20ca90ab1ed8ef83b7839983dd740c38a00ffc/lirc-pi3.txt

Notes to make IR shield (made by LinkSprite) work in Raspberry Pi 3 (bought from Amazon [1]). 
The vendor has some documentation [2] but that is not complete and sufficient for Raspbian Stretch. 
Following are the changes that I made to make it work.

	$ sudo apt-get update
	$ sudo apt-get install lirc

### Update the following line in /boot/config.txt (DEFUNCT)

	dtoverlay=lirc-rpi,gpio_in_pin=18,gpio_out_pin=17

### Add the following lines to /etc/modules file (DEFUNCT)

	lirc_dev
	_rpi gpio_in_pin=18 gpio_out_pin=17


### Add the following lines to /etc/lirc/hardware.conf file (DEFUNCT)

	LIRCD_ARGS="--uinput --listen"
	LOAD_MODULES=true
	DRIVER="default"
	DEVICE="/dev/lirc0"
	MODULES="lirc_rpi"

### Update the following lines in /etc/lirc/lirc_options.conf

	# todo: what does this do?
	driver    = default
	device    = /dev/lirc0

	$ sudo /etc/init.d/lircd stop
	$ sudo /etc/init.d/lircd start


## Notes on Lirc 0.10.1

Previous Raspbian distros included an earilier version of Lirc

Here is how I got it to work. First of all: I use the latest Raspbian Stretch Lite 2018-03-13. With this version there is no /etc/lirc/hardware.conf anymore if you install lirc. You should also use up to date versions.

In /boot/config.txt enable overlay lirc-rpi. GPIO 17 out and GPIO 18 in are default and you can omit their settings. I have added them if you use other pins. You can find the settings in /boot/overlays/README.

	# Uncomment this to enable the lirc-rpi module
	dtoverlay=lirc-rpi,gpio_out_pin=17,gpio_in_pin=18,gpio_in_pull=up

Install lirc:

	rpi3 ~$ sudo apt update
	rpi3 ~$ sudo apt install lirc

Edit /etc/lirc/lirc_options.conf and change this settings to:

	driver = default
	device = /dev/lirc0

Now

	rpi3 ~$ sudo systemctl reboot

After login you should have a lirc0 device and see something like:

	rpi3 ~$ ls -l /dev/lirc0
	crw-rw---- 1 root video 244, 0 2018-01-28 16:58 /dev/lirc0
	rpi3 ~$ lsmod | grep lirc
	lirc_rpi                9032  3
	lirc_dev               10583  1 lirc_rpi
	rc_core                24377  1 lirc_dev

Check services with:

	rpi3 ~$ systemctl status lircd.service
	rpi3 ~$ systemctl status lircd.socket

Now you can test if you get signals. Start mode2 and push some buttons on your remote control. mode2 should show you very low level info in space and pulse:

	rpi3 ~$ sudo systemctl stop lircd.service
	rpi3 ~$ sudo systemctl stop lircd socket
	rpi3 ~$ sudo mode2 --driver default --device /dev/lirc0

If everything is OK to this, we can start lirc again:

	rpi3 ~$ sudo systemctl start lircd socket
	rpi3 ~$ sudo systemctl start lircd.service

Now we need a configuration file that maps the lirc pulses to the buttons of your remote control. On the internet there is a database with many config files for remote controls. the config file for my remote control I have found there. If you cannot find yours you have to training your remote control by yourself with:

	rpi3 ~$ sudo irrecord -n -d /dev/lirc0 ~/lircd.conf

That's your exercise ;-) Haven't tested it. If you have your config file move it to /etc/lirc/lircd.conf.d/ and restart lirc to load this file:

	rpi3 ~$ sudo systemctl restart lircd

Now we can look if we get the pushed buttons. Start irw and push buttons on your remote control. You should get something like:

	rpi3 ~$ irw
	0000000000002422 00 KEY_VOLUMEUP Sony_RMT-CS33AD
	0000000000002422 01 KEY_VOLUMEUP Sony_RMT-CS33AD
	0000000000002422 02 KEY_VOLUMEUP Sony_RMT-CS33AD
	0000000000006422 00 KEY_VOLUMEDOWN Sony_RMT-CS33AD
	0000000000006422 01 KEY_VOLUMEDOWN Sony_RMT-CS33AD
	0000000000006422 02 KEY_VOLUMEDOWN Sony_RMT-CS33AD

Last step is to give these events actions, e.g. start a program. For this we use the program irexec. This needs its config file ~/.config/lircrc with entries like this (simple example):

	begin
	prog = irexec
	button = KEY_VOLUMEUP
	config = echo "Volume-Up"
	end
	begin
	prog = irexec
	button = KEY_VOLUMEDOWN
	config = echo "Volume-Down"
	end

For any button add a new block begin ... end. The button name is exact the name you get with irw. As action (line config =) I do a simple echo so you can see on the console what button was pressed. Here you can call any other program, e.g. system programs, bash scripts, python programs, what you want. Look at man irexec.

## Loopback devices
q
## DeviceTree info

Name:   gpio-ir
Info:   Use GPIO pin as rc-core style infrared receiver input. The rc-core-
        based gpio_ir_recv driver maps received keys directly to a
        /dev/input/event* device, all decoding is done by the kernel - LIRC is
        not required! The key mapping and other decoding parameters can be
        configured by "ir-keytable" tool.
Load:   dtoverlay=gpio-ir,<param>=<val>
Params: gpio_pin                Input pin number. Default is 18.

        gpio_pull               Desired pull-up/down state (off, down, up)
                                Default is "up".

        rc-map-name             Default rc keymap (can also be changed by
                                ir-keytable), defaults to "rc-rc6-mce"


Name:   gpio-ir-tx
Info:   Use GPIO pin as bit-banged infrared transmitter output.
        This is an alternative to "pwm-ir-tx". gpio-ir-tx doesn't require
        a PWM so it can be used together with onboard analog audio.
Load:   dtoverlay=gpio-ir-tx,<param>=<val>
Params: gpio_pin                Output GPIO (default 18)

        invert                  "1" = invert the output (make it active-low).
                                Default is "0" (active-high).



[1] https://www.amazon.com/Infrared-Shield-for-Raspberry-Pi/dp/B00K2IICKK/ref=pd_sbs_328_1?_encoding=UTF8&psc=1&refRID=1QPY33VFCGETBJ17K8QE
[2] http://learn.linksprite.com/raspberry-pi/shield/infrared-transceiver-on-raspberry-pi-lirc-software-installation-and-configuration/
[3] https://www.hackster.io/nathansouthgate/control-rpi-from-alexa-b558ad


### 02/29/2020 prep.sh and config.sh

prep.sh now does most of the standard config itself before first boot.  config.sh is used to patch the system and config lirc

Confirm settings:

	iw reg get

Additional tasks:

- change password
- change gid of pi user to 100
- rename lircd.conf.dist to lircd.conf <- this file runs everything in lircd.conf.d
- rename devinput.conf devinput.conf.dist


Forget known_hosts both by name and ip:

ssh-keygen -f "/home/pi/.ssh/known_hosts" -R raspberrypi
ssh-keygen -f "/home/pi/.ssh/known_hosts" -R 192.168.1.10

--------------------------------------------------------------------------------

# Pi Zero as a Serial Gadget

21 May 2017 in [Linux](https://systemoverlord.com/category/linux) (2 minutes)

I just got a new Raspberry Pi Zero W (the wireless version) and didn't feel like hooking it up to a monitor and keyboard to get started. I really just wanted a serial console for starters. Rather than solder in a header, I wanted to be really lazy, so decided to use the USB OTG support of the Pi Zero to provide a console over USB. It's pretty straightforward, actually.

  * Install Raspbian on MicroSD
  * Mount the /boot partition
  * Edit /boot/config.txt
  * Edit /boot/cmdline.txt
  * Mount the root (/) partition
  * Enable a Console on /dev/ttyGS0
  * Unmount and boot your Pi Zero
  * Connect via a terminal emulator
  * Conclusion

## Install Raspbian on MicroSD

First off is a straightforward "install" of Raspbian on your MicroSD card. In my case, I used dd to image the img file from Raspbian to a MicroSD card in a card reader.

	dd if=/home/david/Downloads/2017-04-10-raspbian-jessie-lite.img of=/dev/sde bs=1M conv=fdatasync

## Mount the /boot partition

You'll want to mount the boot partition to make a couple of changes. Before doing so, run partprobe to re-read the partition tables (or unplug and replug the SD card). Then mount the partition somewhere convenient.

	partprobe
	mount /dev/sde1 /mnt/boot

## Edit /boot/config.txt

To use the USB port as an OTG port, you'll need to enable the dwc2 device tree overlay. This is accomplished by adding a line to /boot/config.txt with dtoverlay=dwc2.

	vim /mnt/boot/config.txt
	(append dtoverlay=dwc2)

## Edit /boot/cmdline.txt

Now we'll need to tell the kernel to load the right module for the serial OTG support. Open /boot/cmdline.txt, and after rootwait, add modules-load=dwc2,g_serial.

	vim /mnt/boot/cmdline.txt
	(insert modules-load=dwc2,g_serial after rootwait)

When you save the file, make sure it is all one line, if you have any line wrapping options they may have inserted newlines into the file.

## Mount the root (/) partition

Let's switch the partition we're dealing with.

	umount /mnt/boot
	mount /dev/sde2 /mnt/root

## Enable a Console on /dev/ttyGS0

/dev/ttyGS0 is the serial port on the USB gadget interface. While we'll get a serial port, we won't have a console on it unless we tell systemd to start a getty (the process that handles login and starts shells) on the USB serial port. This is as simple as creating a symlink:

	ln -s /lib/systemd/system/getty@.service /mnt/root/etc/systemd/system/getty.target.wants/getty@ttyGS0.service

This asks systemd to start a getty on ttyGS0 on boot.

## Unmount and boot your Pi Zero

Unmount your SD card, insert the micro SD card into a Pi Zero, and boot with a Micro USB cable between your computer and the OTG port.

## Connect via a terminal emulator

You can connect via the terminal emulator of your choice at 115200bps. The Pi Zero shows up as a "Netchip Technology, Inc. Linux-USB Serial Gadget (CDC ACM mode)", which means that (on Linux) your device will typically be /dev/ttyACM0.

	screen /dev/ttyACM0 115200

## Conclusion

This is a quick way to get a console on a Raspberry Pi Zero, but it has downsides:

  * Provides only console, no networking.
  * File transfers are “difficult”.


### Related Posts

  * [Belden Garrettcom 6K/10K Switches: Auth Bypasses, Memory Corruption](https://systemoverlord.com/2017/05/19/belden-garrettcom-6k-10k-switches-auth-bypasses-memory-corruption.html)
  * [Backing up to Google Cloud Storage with Duplicity and Service Accounts](https://systemoverlord.com/2019/09/23/backing-up-to-google-cloud-storage-with-duplicity-and-service-accounts.html)
  * [Bash Extended Test & Pattern Matching](https://systemoverlord.com/2017/04/17/bash-extended-test-pattern-matching.html)
  * [GOT and PLT for pwning.](https://systemoverlord.com/2017/03/19/got-and-plt-for-pwning.html)
  * [Martian Packet Messages](https://systemoverlord.com/2011/11/06/martian-packet-messages/)

### Device tree notes

Name:   dwc2
Info:   Selects the dwc2 USB controller driver
Load:   dtoverlay=dwc2,<param>=<val>
Params: dr_mode                 Dual role mode: "host", "peripheral" or "otg"
        g-rx-fifo-size          Size of rx fifo size in gadget mode
        g-np-tx-fifo-size       Size of non-periodic tx fifo size in gadget mode

--------------------------------------------------------------------------------

# Defunct Info
