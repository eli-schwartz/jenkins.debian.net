#!/bin/bash

# Copyright 2012-2017 Holger Levsen <holger@layer-acht.org>
# Copyright      2013 Antonio Terceiro <terceiro@debian.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

EXPORTS_RESULTS=false
# Inside chroot (for the job process)
JENKINS_EXPORTS_DIR=/tmp/job-exports

# cp artifacts back into workspace if this is set
if [ "$ARTIFACTS" != "true" ] ; then
	ARTIFACTS=false
fi

# $1 = base distro (if the '-backports' is used, then it automatically bpo)
# $2 $3 ... = command to run inside a clean chroot running the distro in $1

if [ $# -lt 2 ]; then
	echo "usage: $0 DISTRO [backports|minimal] [--exports-results] CMD [ARG1 ARG2 ...]"
	exit 1
fi

if [ -z "${1%%*-backports}" ]; then
	DISTRO="${1%-backports}"
	BACKPORTS=yes
else
	DISTRO="$1"
fi
shift

if [ "$1" = "backports" ] ; then
	BACKPORTS=yes
	shift
fi

if [ "$BACKPORTS" = "yes" ]; then
	BACKPORTS="deb $MIRROR ${DISTRO}-backports main"
	BACKPORTSSRC="deb-src $MIRROR ${DISTRO}-backports main"
fi

if [ "$1" = "minimal" ] ; then
	MINIMAL=yes
	BOOTSTRAP_OPTIONS=--variant=minbase
	shift
fi

if [ "$1" = "--exports-results" ]; then
	   EXPORTS_RESULTS=true
	   export JENKINS_EXPORTS_DIR
	   shift
fi

if [ ! -d "$CHROOT_BASE" ]; then
	echo "Directory $CHROOT_BASE does not exist, aborting."
	exit 1
fi

export CHROOT_TARGET=$(mktemp -d -p $CHROOT_BASE/ chroot-run-$DISTRO.XXXXXXXXX)
if [ -z "$CHROOT_TARGET" ]; then
	echo "Could not create a directory to create the chroot in, aborting."
	exit 1
fi
chmod 755 "$CHROOT_TARGET"

export CURDIR=$(pwd)

bootstrap() {
	mkdir -p "$CHROOT_TARGET/etc/dpkg/dpkg.cfg.d"
	echo force-unsafe-io > "$CHROOT_TARGET/etc/dpkg/dpkg.cfg.d/02dpkg-unsafe-io"

	local TMPLOG=$(mktemp -p $CHROOT_BASE/ chroot-run-$DISTRO.XXXXXXXXX)
	echo "$(date -u ) - bootstraping $DISTRO into $CHROOT_TARGET now."
	set +e
	sudo debootstrap $BOOTSTRAP_OPTIONS $DISTRO $CHROOT_TARGET $MIRROR | tee $TMPLOG
	local RESULT=$(egrep "E: (Couldn't download (packages|dists)|Invalid Release signature)" $TMPLOG || true )
	rm $TMPLOG
	set -e
	if [ ! -z "$RESULT" ] ; then
	        echo "$(date -u) - initial debootstrap failed, sleeping 5min before retrying..."
	        sudo rm -rf --one-file-system $CHROOT_TARGET
	        sleep 5m
	        if ! sudo debootstrap $BOOTSTRAP_OPTIONS $DISTRO $CHROOT_TARGET $MIRROR ; then
			SLEEPTIME="30m"
			echo "$(date -u ) - debootstrap failed, slowing down, sleeping $SLEEPTIME now..."
			sleep $SLEEPTIME
			exit 1
		fi
	fi

	if [ "$EXPORTS_RESULTS" = "true" ]; then
		mkdir -p "$CHROOT_TARGET/$JENKINS_EXPORTS_DIR"
	fi


	cat > $CHROOT_TARGET/tmp/chroot-prepare <<-EOF
$SCRIPT_HEADER
mount /proc -t proc /proc
echo -e '#!/bin/sh\nexit 101' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d
echo 'Acquire::http::Proxy "$http_proxy";' > /etc/apt/apt.conf.d/80proxy
echo "deb-src $MIRROR $DISTRO main" >> /etc/apt/sources.list
echo "${BACKPORTS}" >> /etc/apt/sources.list
echo "${BACKPORTSSRC}" >> /etc/apt/sources.list
apt-get update
EOF

	chmod +x $CHROOT_TARGET/tmp/chroot-prepare
	sudo chroot $CHROOT_TARGET /tmp/chroot-prepare
}

cleanup() {
	# hack to get data out of the chroot, used by haskell-package-plan
	if [ -e $CHROOT_TARGET/tmp/testrun/stats.csv ]
	then
		cp -v $CHROOT_TARGET/tmp/testrun/stats.csv $CURDIR
	fi

	if [ "${EXPORTS_RESULTS}" = "true" ]; then
		mkdir -p "$WORKSPACE/job-exports"
		if [ ! -z "$(ls -1A "$CHROOT_TARGET/$JENKINS_EXPORTS_DIR")" ]; then
			cp -drv "$CHROOT_TARGET/$JENKINS_EXPORTS_DIR"/* "$WORKSPACE/job-exports/"
		else
			echo "W: No exported results found in $JENKINS_EXPORTS_DIR"
		fi
	fi

	#
	# special case: publish debian-edu-doc on the webserver
	#
	CHANGES=$(ls -1 $CHROOT_TARGET/tmp/debian-edu-doc_*.changes 2>/dev/null|| true)
	if [ ! -z "$CHANGES" ] ; then
		publish_changes_to_userContent $CHANGES debian-edu "git ${GIT_COMMIT:0:7}"
	fi

	#
	# publish artifacts
	#
	if [ "$ARTIFACTS" = "true" ] ; then
		CHANGES=$(ls -1 $CHROOT_TARGET/tmp/*_*.changes 2>/dev/null|| true)
		dcmd cp $CHANGES $WORKSPACE/
	fi

	#
	# actually cleanup
	#
	if [ -d $CHROOT_TARGET/proc ]; then
		sudo umount -l $CHROOT_TARGET/proc || fuser -mv $CHROOT_TARGET/proc
	fi
	if [ -d $CHROOT_TARGET/testrun ]; then
		sudo umount -l $CHROOT_TARGET/testrun || fuser -mv $CHROOT_TARGET/testrun
	fi
	if [ -d $CHROOT_TARGET ]; then
		sudo rm -rf --one-file-system $CHROOT_TARGET || fuser -mv $CHROOT_TARGET
	fi

}
trap cleanup INT TERM EXIT

run() {
	cp -r $CURDIR $CHROOT_TARGET/tmp/
	mv $CHROOT_TARGET/tmp/$(basename $CURDIR) $CHROOT_TARGET/tmp/testrun
	cat > $CHROOT_TARGET/tmp/chroot-testrun <<-EOF
$SCRIPT_HEADER
cd /tmp/testrun
EOF
	if [ "$MINIMAL" != "yes" ]; then
		cat >> $CHROOT_TARGET/tmp/chroot-testrun <<-EOF
echo 'APT::Get::Assume-Yes "true";' > /etc/apt/apt.conf.d/23jenkins
apt-get install build-essential devscripts git
if [ "$1" = "gbp" ] ; then
	apt-get install git-buildpackage
	# either there is a debian branch or not
	git checkout debian || echo "No debian branch exists, assuming packaging is in master branch."
fi
if [ -f debian/control ] ; then
	cat debian/control
	# install build-depends
	if [ -z "$BACKPORTS" ] ; then
		mk-build-deps -ir
	else
		# use default mk-build-deps tool but configure it to use backports
		mk-build-deps -ir -t "apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends -t $DISTRO-backports"
	fi
fi
EOF
	fi
	if [ "$EXPORTS_RESULTS" = "true" ]; then
		echo "export JENKINS_EXPORTS_DIR=\"$JENKINS_EXPORTS_DIR\"" >> $CHROOT_TARGET/tmp/chroot-testrun
	fi
	echo "$*" >> $CHROOT_TARGET/tmp/chroot-testrun
	chmod +x $CHROOT_TARGET/tmp/chroot-testrun
	sudo chroot $CHROOT_TARGET /tmp/chroot-testrun

}

bootstrap
run "$@"
trap - INT TERM EXIT
cleanup

