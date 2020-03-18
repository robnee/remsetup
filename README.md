# remsetup

Scripts for building and configuring Raspbian for Lirc remote control

Starting remsetup project to attempt to write a set of scripts to build and config a Raspbian image for use as a remote box.  This will probably include these things

- Raspbian Lite image
- Configure wifi and headless config via ssh
- configure raspi-config settings
- Update OS
- Add some key packages (git, vim, python3 etc)
- Tweak power settings
- configure lirc

The focus of the project is for a clean Raspbian build with minimal baggage such as a GUI or desktop applications.  The presents a bit of a problem.  raspi-config, the front-end to simplify configuring Raspbian, makes some tasks a bit harder.  For instance, the setting of some options such as locale can't be inspected.  The highlighted value presented in the option picker is not the current setting but a fixed default.  This causes confusion and is very tedious to use.  We need a way to set the key options directly.

Luckily most configuration settings are found in files in /boot and /etc and these files can be edited.

> http://paulmouzas.github.io/python/http/sockets/2015/03/29/roku-remote.html

## Manual steps for standing up a headless, Lirc IR blaster

Starting with a newly imaged install of Raspbian these steps can help set up a streamlined install.  It can be done manually or with the aid of raspi-config.

### raspi-config configuration

	sudo raspi-config

Change these options

N1. Change hostname
N2. Change Wi-fi settings
I1. Change Locale
I2. Change Timezone
I3. Change Keyboard Layout
I4. Change Wi-Fi country
P2. Enable ssh
A3. Change Memory split for graphics memory

### Manual configuration

#### set hostname with /etc/hostname file directly

	sudo echo "name" > /etc/hostname

You should reboot for the name change to take effect

#### A3. Change Memory split for graphics memory

Append gpu_mem seting (16/32/64/128/256) to /boot/config.txt.  We want to restrict memory to the GPU on a headless setup.

	echo "gpu_mem=16" >> /boot/config.txt

A simple preface of sudo will not work with the redirection so first do:
	
	sudo su

### create /etc/timezone

Create /etc/timezone with the region/zone such as "America/New_York".  Also create a link from /etc/localtime to /usr/share/zoneinfo/America/New_York.

	echo "America/New_York" > /etc/timezone
	ln -s /usr/share/zoneinfo/America/New_York /etc/localtime

### /etc/default/locale

	#  File generated by update-locale
	LANG=C.UTF-8

add "en_US.UTF-8 UTF-8" to /etc/locale.gen

### /etc/default/keyboard

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

### Confirm settings

	iw reg get

## Lirc Setup

### add to /boot/config.txt: (DEFUNCT)

	dtoverlay=lirc-rpi,gpio_in_pin=23,gpio_out_pin=22,gpio_in_pull=up

### add to /etc/modules: (DEFUNCT)

	lirc_dev
	lirc_rpi gpio_in_pin=23 gpio_out_pin=22

### update /etc/lirc/hardware.conf  (DEFUNCT)

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

NOTE: Reboot! Much frustration can be avoided be rebooting before testing!

### update lirc_options.conf (Lirc 10.0+)

See section on lirc 10.0

## Troubleshooting

### Check for syslog errors

Fix bug in /etc/rsyslog.conf to no longer refer to xconsole to prevent annoying syslog errors for headless systems not running an X desktop.  This may no longer be necessary in Stretch onward.

So for the Pi Zero W the config options are as follows.  Since we aren't using the receiver don't list it. 


## Configure for low power:

#### Turn off HDMI

	/usr/bin/tvservice -o (-p to re-enable). Add the line to /etc/rc.local to disable HDMI on boot.  prep.sh sets this.

#### Turn off LEDs

If you want to turn off the LED on the Pi Zero completely, run the following two commands:

	# Set the Pi Zero ACT LED trigger to 'none'.
	echo none | sudo tee /sys/class/leds/led0/trigger

	# Turn off the Pi Zero ACT LED.
	echo 1 | sudo tee /sys/class/leds/led0/brightness

To make these settings permanent, add the following lines to your Pi's /boot/config.txt file and reboot:

	# Disable the ACT LED on the Pi Zero.
	dtparam=act_led_trigger=none
	dtparam=act_led_activelow=on

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
	rpi3 ~$ lsmod | grep gpio_ir
	gpio_ir_tx             16384  0

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


### DeviceTree info

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


## 02/29/2020 prep.sh and config.sh

### Set credentials using

	. vars

### Use prep.sh to flash and config

	sudo prep.sh raspbiam.img /dev/sda


