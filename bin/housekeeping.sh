#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# default settings
#
export LC_ALL=C
set -e

check_for_mounted_chroots() {
	CHROOT_PATTERN="/chroots/${1}-*"
	OUTPUT=$(mktemp)
	ls $CHROOT_PATTERN 2>/dev/null > $OUTPUT || true
	if [ -s $OUTPUT ] ; then
		figlet "Warning:"
		echo
		echo "Probably manual cleanup needed:"
		echo
		echo "$ ls -la $CHROOT_PATTERN"
		# List the processes using the partition
		echo
		fuser -mv $CHROOT_TARGET
		cat $OUTPUT
		rm $OUTPUT
		exit 1
	fi
	rm $OUTPUT
}

report_disk_usage() {
	du -schx /var/lib/jenkins/jobs/${1}_* |grep total |sed -s "s#total#${1} jobs#"
	# FIXME: if $2 is given check, that disk usage is below $2 GB - same for report_filetype_usage()
}

report_filetype_usage() {
	OUTPUT=$(mktemp)
	find /var/lib/jenkins/jobs/${1}_* -type f -name "*.${2}" 2>/dev/null|xargs -r du -sch |grep total |sed -s "s#total#$1 .$2 files#" > $OUTPUT
	if [ "$3" = "warn" ] &&  [ -s $OUTPUT ] ; then
		echo "Warning: there are $2 files and there should not be any."
		cat $OUTPUT
		echo "Checking for running QEMU processes:"
		ps fax | grep [q]emu-system || true
	else
		cat $OUTPUT
	fi
	rm $OUTPUT
}


report_squid_usage() {
	REPORT=/var/www/calamaris/calamaris.txt
	if [ -z $1 ] ; then
		cat $REPORT
	else
		head -31 $REPORT
	fi
}

general_housekeeping() {
	echo
	uptime

	echo
	# ignore unreadable /media fuse mountpoints from guestmount
	df -h 2>/dev/null || true

	echo
	for DIR in /var/cache/apt/archives/ /var/spool/squid/ /var/cache/pbuilder/build/ /var/lib/jenkins/jobs/ ; do
		sudo du -shx $DIR 2>/dev/null
	done
	JOB_PREFIXES=$(ls -1 /var/lib/jenkins/jobs/|cut -d "_" -f1|sort -f -u)
	for PREFIX in $JOB_PREFIXES ; do
		report_disk_usage $PREFIX
	done

	echo
	vnstat

	(df 2>/dev/null || true ) | grep tmpfs > /dev/null || ( echo ; echo "Warning: no tmpfs mounts in use. Please investigate the host system." ; exit 1 )
}

#
# if $1 is empty, we do general housekeeping, else for some subgroup of all jobs
#
if [ -z $1 ] ; then
	general_housekeeping
	report_squid_usage brief
else
	case $1 in
		chroot-installation)		report_disk_usage $1
						check_for_mounted_chroots $1
						;;
		g-i-installation)		report_disk_usage $1
						report_filetype_usage $1 raw warn
						report_filetype_usage $1 iso
						report_filetype_usage $1 png
						report_filetype_usage $1 ppm warn
						report_filetype_usage $1 bak warn
						;;
		squid)				report_squid_usage
						;;
		*)				;;
	esac
fi

echo
echo "No problems found, all seems good."
figlet "Ok."
