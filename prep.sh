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

WORKDIR=./remsetup
TARGETDEV=/dev/sdb
LOGDIR=./logs
LOGFILE=$LOGDIR/$ymd.log

SCRIPTDIR=$(dirname $0)
BACKDIR=/home/Backup
PIDFILE=$BACKDIR/backup.pid
BACKFILE=$BACKDIR/archive/home.tgz
ROOTFILE=$BACKDIR/archive/root.tgz
MEDIAFILE=$BACKDIR/archive/media.tar

ARCHDEV=/dev/disk/by-label/ARCHIVE
ARCHDIR=/home/Archive
ARCH2DEV=/dev/disk/by-label/ARCHIVE2
ARCH2DIR=/home/Archive2

HOSTWAY=64.71.34.38
LINODE=97.107.139.235
AYUCR=45.33.95.120

#-------------------------------------------------------------------------------

# . $SCRIPTDIR/lib.sh

#-------------------------------------------------------------------------------

if [ "$#" -ne 1 ]; then
    echo "usage: prep.sh <raspbian zip file>"
	exit
fi

if [ ! -f "$1" ]; then
	echo "$1 does not exist"
	exit
fi

# Check if this is an image file
filetype=`file "$1" | grep -o "DOS/MBR"`
if [ "$filetype" != "DOS/MBR" ]; then
	echo "$1 does not appear to be image file"
	exit
fi

imgsize=`du --block-size=1MB $1 | cut -f1`
echo $1 size $imgsize

echo --------------------------------------------------------------------------------
echo Setup workspace
echo --------------------------------------------------------------------------------

echo "Img file      : $1"
echo "Img size      ; $imgsize MB"
echo "Target        : $TARGETDEV"
echo

if [ -e $WORKDIR ]
then
	while true; do
		read -p "$WORKDIR already exists.  Remove? [y|N]" yn
		case $yn in
			([Yy]* ) break;;
			([Nn]* ) exit;;
			("" ) exit;;
		esac
	done
	
	echo removing $WORKDIR
	rm -rf $WORKDIR
fi

echo "flashing image..."
dd if=$1 status=progress of=$TARGETDEV bs=1M

echo HALT
exit

#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------
#-------------------------------------------------------------------------------

# ensure backup is not already running
#
if [ -e $PIDFILE ]
then
	echo backup already running...

	echo backup already running... >> $LOGFILE 2>&1
	ls -l $PIDFILE >> $LOGFILE 2>&1
	cat $PIDFILE >> $LOGFILE 2>&1
	exit
fi

echo $$ > $PIDFILE

# Back up the root Linux partition making sure to capture all SELinux attributes
#
echo Taking root partition snapshot >> $LOGFILE 2>&1
tar --totals --acls --selinux --xattrs -czf $ROOTFILE /bin /boot /etc /lib /opt /root /sbin /usr /var >> $LOGFILE 2>&1

# Back up all data except Media
#
echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
echo Backing up /home ... >> $LOGFILE 2>&1
tar --totals -czvf $BACKFILE --exclude=/home/Shared/Media/* /home/rnee /home/Shared >> $LOGFILE 2>&1

# Sundays and the 1st of the month create a separate Media Backup.  Don't compress it
#
if [ "$day" == "Sunday" -o $dom -eq 1 ]; then
	echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
	echo Backing up /home/Shared/Media ... >> $LOGFILE 2>&1
	tar --totals -cvf $MEDIAFILE --exclude=Media/VOB/* -C /home/Shared Media >> $LOGFILE 2>&1
fi

# Trigger a backup of the HOSTWAY mysql database and local files
#
#echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
#echo Requesting HOSTWAY backups >> $LOGFILE 2>&1
#wget -qO- $HOSTWAY/cgi-bin/backtrack.pl >> $LOGFILE 2>&1

#echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
#echo fetching HOSTWAY backups >> $LOGFILE 2>&1
#sftp robnee@$HOSTWAY:backup/sql/$ymd.sql.gz $BACKDIR/robnee/sql >> $LOGFILE 2>&1

echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
echo fetching Linode robnee.com hosted backups >> $LOGFILE 2>&1
sftp rnee@$LINODE:/home/rnee/backup/srv.tgz.gpg $BACKDIR/linode >> $LOGFILE 2>&1
sftp rnee@$LINODE:/home/rnee/backup/db.sql.gz $BACKDIR/linode/sql/db.$ymd.sql.gz >> $LOGFILE 2>&1

echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
echo fetching Linode ayucr.com hosted backups >> $LOGFILE 2>&1
sftp rnee@$AYUCR:/home/rnee/backup/srv.tgz.gpg $BACKDIR/ayucr >> $LOGFILE 2>&1
sftp rnee@$AYUCR:/home/rnee/backup/db.sql.gz $BACKDIR/ayucr/sql/db.$ymd.sql.gz >> $LOGFILE 2>&1

# Only get the local files on the 1st
#
if [ $dom -eq 1 ]; then
#	sftp robnee@$HOSTWAY:backup/robnee.tgz $BACKDIR/robnee/images/robnee.$ymd.tgz >> $LOGFILE 2>&1

	sftp rnee@$LINODE:/home/rnee/backup/srv.tgz.gpg $BACKDIR/linode/images/linode.$ymd.tgz.gpg >> $LOGFILE 2>&1
	sftp rnee@$AYUCR:/home/rnee/backup/srv.tgz.gpg $BACKDIR/ayucr/images/ayucr.$ymd.tgz.gpg >> $LOGFILE 2>&1
fi

#echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
#echo Mounting $ARCHDEV on $ARCHDIR ... >> $LOGFILE 2>&1
#
#mount_drive $ARCHDEV $ARCHDIR
#if [ $? == 0 ]; then
#	echo Mounted >> $LOGFILE 2>&1

	df -h >> $LOGFILE 2>&1

	# Rotate the files to keep additionals
	#
	if [ $day == Sunday ]; then
		echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
		echo Rotating Sunday Files >> $LOGFILE 2>&1
		mv -fv $ARCHDIR/Backup/Server/Weekly.2.tgz  $ARCHDIR/Backup/Server/Weekly.3.tgz >> $LOGFILE 2>&1
		mv -fv $ARCHDIR/Backup/Server/Weekly.1.tgz  $ARCHDIR/Backup/Server/Weekly.2.tgz >> $LOGFILE 2>&1
		mv -fv $ARCHDIR/Backup/Server/Daily.0.tgz  $ARCHDIR/Backup/Server/Weekly.1.tgz >> $LOGFILE 2>&1

		mv -fv $ARCHDIR/Backup/Server/root.2.tgz  $ARCHDIR/Backup/Server/root.3.tgz >> $LOGFILE 2>&1
		mv -fv $ARCHDIR/Backup/Server/root.1.tgz  $ARCHDIR/Backup/Server/root.2.tgz >> $LOGFILE 2>&1
		mv -fv $ARCHDIR/Backup/Server/root.tgz  $ARCHDIR/Backup/Server/root.1.tgz >> $LOGFILE 2>&1
	fi

	# Monthly save a copy of the backup and rotate the media backups to keep three additionals
	#
	if [ $dom -eq 1 ]; then
		echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
		echo Rotating Monthly Files >> $LOGFILE 2>&1
		mv -fv $ARCHDIR/Backup/Server/Monthly.5.tgz  $ARCHDIR/Backup/Server/Monthly.6.tgz >> $LOGFILE 2>&1
		mv -fv $ARCHDIR/Backup/Server/Monthly.4.tgz  $ARCHDIR/Backup/Server/Monthly.5.tgz >> $LOGFILE 2>&1
		mv -fv $ARCHDIR/Backup/Server/Monthly.3.tgz  $ARCHDIR/Backup/Server/Monthly.4.tgz >> $LOGFILE 2>&1
		mv -fv $ARCHDIR/Backup/Server/Monthly.2.tgz  $ARCHDIR/Backup/Server/Monthly.3.tgz >> $LOGFILE 2>&1
		mv -fv $ARCHDIR/Backup/Server/Monthly.1.tgz  $ARCHDIR/Backup/Server/Monthly.2.tgz >> $LOGFILE 2>&1
		mv -fv $ARCHDIR/Backup/Server/Monthly.0.tgz  $ARCHDIR/Backup/Server/Monthly.1.tgz >> $LOGFILE 2>&1

		echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
		echo Rotating Media Files >> $LOGFILE 2>&1
	#	mv -fv $ARCHDIR/Backup/Server/media.2.tar  $ARCHDIR/Backup/Server/media.3.tar >> $LOGFILE 2>&1
		mv -fv $ARCHDIR/Backup/Server/media.1.tar  $ARCHDIR/Backup/Server/media.2.tar >> $LOGFILE 2>&1
		mv -fv $ARCHDIR/Backup/Server/media.0.tar  $ARCHDIR/Backup/Server/media.1.tar >> $LOGFILE 2>&1

		echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
		echo Archiving Monthly File $mon.tgz >> $LOGFILE 2>&1
		dd if=$BACKFILE of=$ARCHDIR/Backup/Server/Monthly.0.tgz >> $LOGFILE 2>&1
	fi

	# Copy current backup files over to the archive
	#
	echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
	echo Archiving backup files root.tgz Daily.$dow.tgz >> $LOGFILE 2>&1
	dd if=$ROOTFILE of=$ARCHDIR/Backup/Server/root.tgz >> $LOGFILE 2>&1
	dd if=$BACKFILE of=$ARCHDIR/Backup/Server/Daily.$dow.tgz >> $LOGFILE 2>&1

	if [ $day == Sunday -o $dom -eq 1 ]; then
		echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
		echo Archiving $MEDIAFILE >> $LOGFILE 2>&1
		dd if=$MEDIAFILE of=$ARCHDIR/Backup/Server/media.0.tar >> $LOGFILE 2>&1
	fi

	# Sync copy of snapshot directory every Saturday to snapshot.2
	#
	#if [ $day == Saturday ]; then
	#	echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
	#	echo Syncing extra copy of snapshot files >> $LOGFILE 2>&1
	#
	#	# -W skips delta algorithm for speed with these large files
	#	rsync -avuiW --delete --stats --human-readable /home/Backup/snapshot/ $ARCHDIR/Backup/snapshot.2/ >> $LOGFILE 2>&1
	#fi

	# Sync copy of backup directory to archive
	#
	echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
	echo Syncing copy of Backup directory to Archive >> $LOGFILE 2>&1

	rsync -avui --stats --human-readable /home/Backup/logs/ $ARCHDIR/Backup/logs/ >> $LOGFILE 2>&1
	rsync -avui --stats --human-readable /home/Backup/msmoney/ $ARCHDIR/Backup/msmoney/ >> $LOGFILE 2>&1
	rsync -avui --delete --stats --human-readable /home/Backup/hostway/ $ARCHDIR/Backup/hostway/ >> $LOGFILE 2>&1
	rsync -avui --delete --stats --human-readable /home/Backup/linode/ $ARCHDIR/Backup/linode/ >> $LOGFILE 2>&1
	rsync -avui --delete --stats --human-readable /home/Backup/ayucr/ $ARCHDIR/Backup/ayucr/ >> $LOGFILE 2>&1
	rsync -avuiW --delete --stats --human-readable /home/Backup/snapshot/ $ARCHDIR/Backup/snapshot/ >> $LOGFILE 2>&1
	rsync -avuiW --delete --stats --human-readable /home/Backup/kvm/ $ARCHDIR/Backup/kvm/ >> $LOGFILE 2>&1

#	echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
#	echo Syncing extra Archive >> $LOGFILE 2>&1
#
#	mount_drive $ARCH2DEV $ARCH2DIR
#
#	rsync -avui --stats --human-readable $ARCHDIR/ $ARCH2DIR/ >> $LOGFILE 2>&1
#
#	echo Unmouinting... >> $LOGFILE 2>&1
#	umount $ARCHDIR
#	umount $ARCH2DIR
#fi

echo -------------------------------------------------------------------------------- >> $LOGFILE 2>&1
echo Done! >> $LOGFILE 2>&1

end_time=`date +'%Y-%m-%d %H:%M:%S'`

echo >> $LOGFILE 2>&1
echo START : $start_time >> $LOGFILE 2>&1
echo END   : $end_time >> $LOGFILE 2>&1

rm -f $PIDFILE
