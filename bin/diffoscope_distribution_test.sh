#!/bin/bash

# Copyright 2014-2016 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code (used for irc_message)
. /srv/jenkins/bin/reproducible_common.sh

send_irc_warning() {
	local WARNING=$1
	irc_message reproducible-builds "$WARNING"
	echo "Warning: $WARNING"
}

check_pypi() {
	TMPPYPI=$(mktemp -t diffoscope-distribution-XXXXXXXX)
	# the following two lines are a bit fragile…
	curl https://pypi.org/project/diffoscope/ -o $TMPPYPI
	DIFFOSCOPE_IN_PYPI=$(sed -ne 's@.*diffoscope \([0-9][0-9]*\).*@\1@gp' $TMPPYPI)
	rm -f $TMPPYPI > /dev/null
	echo
	echo
	if [ "$DIFFOSCOPE_IN_DEBIAN" = "$DIFFOSCOPE_IN_PYPI" ] ; then
		echo "Yay. diffoscope in Debian has the same version as on PyPI: $DIFFOSCOPE_IN_DEBIAN"
	elif dpkg --compare-versions "$DIFFOSCOPE_IN_DEBIAN" gt "$DIFFOSCOPE_IN_PYPI" ; then
		echo "Fail: diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
		echo "Fail: diffoscope in PyPI:   $DIFFOSCOPE_IN_PYPI"
		send_irc_warning "It seems diffoscope $DIFFOSCOPE_IN_DEBIAN is not available on PyPI, which only has $DIFFOSCOPE_IN_PYPI."
		exit 0
	else
		echo "diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
		echo "diffoscope in PyPI:   $DIFFOSCOPE_IN_PYPI"
		echo
		echo "Failure is the default action…"
		exit 1
	fi
}

check_whohas() {
	# the following is "broken" (but good enough for now)
	# as sort doesn't do proper version comparison
	DIFFOSCOPE_IN_WHOHAS=$(whohas -d $DISTRIBUTION diffoscope | awk '{print $3}' | sort -u | tail -1)
	echo
	echo
	if [ "$DIFFOSCOPE_IN_DEBIAN" = "$DIFFOSCOPE_IN_WHOHAS" ] ; then
		echo "Yay. diffoscope in Debian has the same version as $DISTRIBUTION has: $DIFFOSCOPE_IN_DEBIAN"
	elif dpkg --compare-versions "$DIFFOSCOPE_IN_DEBIAN" gt "$DIFFOSCOPE_IN_WHOHAS" ; then
		echo "Fail: diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
		echo "Fail: diffoscope in $DISTRIBUTION: $DIFFOSCOPE_IN_WHOHAS"
		send_irc_warning "It seems diffoscope $DIFFOSCOPE_IN_DEBIAN is not available in $DISTRIBUTION, which only has $DIFFOSCOPE_IN_WHOHAS."
		exit 0
	else
		# FIXME: archlinux package version will be greater than Debian: 52-1 vs 52
		echo "diffoscope in Debian: $DIFFOSCOPE_IN_DEBIAN"
		echo "diffoscope in $DISTRIBUTION: $DIFFOSCOPE_IN_WHOHAS"
		echo
		echo "Failure is the default action…"
		exit 1
	fi
}


#
# main
#
for SUITE in 'experimental' 'unstable|sid'
do
	DIFFOSCOPE_IN_DEBIAN=$(rmadison diffoscope|egrep " ${SUITE} "| awk '{print $3}' || true)

	if [ "$DIFFOSCOPE_IN_DEBIAN" != "" ] ; then
		break
	fi
done

case $1 in
	PyPI)	check_pypi
		;;
	FreeBSD|NetBSD|MacPorts)
		DISTRIBUTION=$1
		check_whohas
		# missing tests: Arch, Fedora, openSUSE, maybe OpenBSD, Guix…
		;;
	*)
		echo "Unsupported distribution."
		exit 1
		;;
esac

