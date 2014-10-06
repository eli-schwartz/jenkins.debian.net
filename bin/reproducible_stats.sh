#!/bin/bash

# Copyright 2014 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

. /srv/jenkins/bin/common-functions.sh
common_init "$@"

set +x
# define db
PACKAGES_DB=/var/lib/jenkins/reproducible.db
INIT=/var/lib/jenkins/reproducible.init
if [ ! -f $PACKAGES_DB ] ; then
	echo "$PACKAGES_DB doesn't exist, no stats possible."
	exit 1
fi 

SUITE=sid
AMOUNT=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT amount FROM source_stats WHERE suite = \"$SUITE\"" | xargs echo)
GOOD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"reproducible\" ORDER BY name" | xargs echo)
COUNT_GOOD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"reproducible\"")
BAD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"unreproducible\" ORDER BY build_date DESC" | xargs echo)
COUNT_BAD=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"unreproducible\"")
UGLY=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"FTBFS\" ORDER BY build_date DESC" | xargs echo)
COUNT_UGLY=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"FTBFS\"")
SOURCELESS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"404\" ORDER BY build_date DESC" | xargs echo)
COUNT_SOURCELESS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"404\"" | xargs echo)
NOTFORUS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"not for us\" ORDER BY build_date DESC" | xargs echo)
COUNT_NOTFORUS=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"not for us\"" | xargs echo)
BLACKLISTED=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT name FROM source_packages WHERE status = \"blacklisted\" ORDER BY build_date DESC" | xargs echo)
COUNT_BLACKLISTED=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages WHERE status = \"blacklisted\"" | xargs echo)
COUNT_TOTAL=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT COUNT(name) FROM source_packages")
PERCENT_TOTAL=$(echo "scale=1 ; ($COUNT_TOTAL*100/$AMOUNT)" | bc)
PERCENT_GOOD=$(echo "scale=1 ; ($COUNT_GOOD*100/$COUNT_TOTAL)" | bc)
PERCENT_BAD=$(echo "scale=1 ; ($COUNT_BAD*100/$COUNT_TOTAL)" | bc)
PERCENT_UGLY=$(echo "scale=1 ; ($COUNT_UGLY*100/$COUNT_TOTAL)" | bc)
PERCENT_NOTFORUS=$(echo "scale=1 ; ($COUNT_NOTFORUS*100/$COUNT_TOTAL)" | bc)
PERCENT_SOURCELESS=$(echo "scale=1 ; ($COUNT_SOURCELESS*100/$COUNT_TOTAL)" | bc)
GUESS_GOOD=$(echo "$PERCENT_GOOD*$AMOUNT/100" | bc)

write_index() {
	echo "$1" >> index.html
	echo "$1" | html2text
}

mkdir -p /var/lib/jenkins/userContent/rb-pkg/
write_pkg_frameset() {
	FRAMESET="/var/lib/jenkins/userContent/rb-pkg/$1.html"
	cat > $FRAMESET <<-EOF
<!DOCTYPE html>
<html>
	<head>
	</head>
	<frameset framespacing="0" rows="42,*" frameborder="0" noresize>
		<frame name="top" src="$1_navigation.html" target="top">
		<frame name="main" src="$2" target="main">
	</frameset>
</html>
EOF
}

init_navi_frame() {
	NAVI="/var/lib/jenkins/userContent/rb-pkg/$1_navigation.html"
	echo "<!DOCTYPE html><link href="../static/style.css" type="text/css" rel="stylesheet"> </link><html><body><p>" > $NAVI
	echo "<font size=+1>$1</font> " >> $NAVI
	RESULT=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT build_date,version FROM source_packages WHERE name = \"$PKG\"")
	BUILD_DATE=$(echo $RESULT|cut -d "|" -f1)
	VERSION=$(echo $RESULT|cut -d "|" -f2)
	echo "($VERSION) " >> $NAVI
	echo "<font size=-1>at $BUILD_DATE:</font> " >> $NAVI
}

append2navi_frame() {
	echo "$1" >> $NAVI
}

finish_navi_frame() {
	echo "</p></body></html>" >> $NAVI
}

link_packages() {
	for PKG in $@ ; do
		VERSION=$(sqlite3 -init $INIT $PACKAGES_DB "SELECT version FROM source_packages WHERE name = \"$PKG\"")
		# remove epoch
		EVERSION=$(echo $VERSION | cut -d ":" -f2)
		# FIXME: remove unused code once all diffp.log files are gone
		if [ -f "/var/lib/jenkins/userContent/dbd/${PKG}_${EVERSION}.debbindiff.html" ] || [ -f "/var/lib/jenkins/userContent/dbd/${PKG}_${EVERSION}.diffp.log" ] || [ -f "/var/lib/jenkins/userContent/buildinfo/${PKG}_${EVERSION}_amd64.buildinfo" ] || [ -f "/var/lib/jenkins/userContent/rbuild/${PKG}_${EVERSION}.rbuild.log" ]; then
			STAR=""
			MAINLINK=""
			init_navi_frame "$PKG"
			if [ -f "/var/lib/jenkins/userContent/buildinfo/${PKG}_${EVERSION}_amd64.buildinfo" ] ; then
				append2navi_frame " <a href=\"$JENKINS_URL/userContent/buildinfo/${PKG}_${EVERSION}_amd64.buildinfo\" target=\"main\">buildinfo</a> "
				MAINLINK="$JENKINS_URL/userContent/buildinfo/${PKG}_${EVERSION}_amd64.buildinfo"
			elif $EXTRA_STAR ; then
				STAR="<font color=\"#333333\" size=\"-1\">&beta;</font>" # used to be a star...
			fi
			if [ -f "/var/lib/jenkins/userContent/dbd/${PKG}_${EVERSION}.debbindiff.html" ] ; then
				append2navi_frame " <a href=\"$JENKINS_URL/userContent/dbd/${PKG}_${EVERSION}.debbindiff.html\" target=\"main\">debbindiff</a> "
				MAINLINK="$JENKINS_URL/userContent/dbd/${PKG}_${EVERSION}.debbindiff.html"
			elif [ -f "/var/lib/jenkins/userContent/dbd/${PKG}_${EVERSION}.diffp.log" ] ; then
				append2navi_frame " <a href=\"$JENKINS_URL/userContent/dbd/${PKG}_${EVERSION}.diffp.log\" target=\"main\">diffp</a> "
				MAINLINK="$JENKINS_URL/userContent/dbd/${PKG}_${EVERSION}.diffp.log"
			fi
			if [ -f "/var/lib/jenkins/userContent/rbuild/${PKG}_${EVERSION}.rbuild.log" ] ; then
				append2navi_frame " <a href=\"$JENKINS_URL/userContent/rbuild/${PKG}_${EVERSION}.rbuild.log\" target=\"main\">rbuild</a> "
				if [ "$MAINLINK" = "" ] ; then
					MAINLINK="$JENKINS_URL/userContent/rbuild/${PKG}_${EVERSION}.rbuild.log"
				fi
			fi
			append2navi_frame " <a href=\"https://packages.qa.debian.org/${PKG}\" target=\"main\">PTS</a> "
			append2navi_frame " <a href=\"https://bugs.debian.org/src:${PKG}\" target=\"main\">BTS</a> "
			append2navi_frame " <a href=\"https://sources.debian.net/src/${PKG}/\" target=\"main\">sources</a> "

			finish_navi_frame
			write_pkg_frameset "$PKG" "$MAINLINK"
			write_index " <a href=\"$JENKINS_URL/userContent/rb-pkg/$PKG.html\">$PKG</a>$STAR "
		else
			write_index " $PKG "
		fi
	done
}

echo "Starting to write statistics index page."
echo
write_index "<!DOCTYPE html><html><link href="static/style.css" type="text/css" rel="stylesheet"> </link><body>" > index.html
write_index "<header><h2>Statistics for reproducible builds</h2>"
write_index "<p>This page is updated every three hours. Results are obtained from <a href=\"$JENKINS_URL/view/reproducible\">several build jobs running on jenkins.debian.net</a>. Thanks to <a href=\"https://www.profitbricks.com\">Profitbricks</a> for donating the virtual machine it's running on!</p>"
write_index "<p>$COUNT_TOTAL packages attempted to build so far, that's $PERCENT_TOTAL% of $AMOUNT source packages in Debian $SUITE currently. Out of these, $PERCENT_GOOD% were successful, so quite wildly guessing this roughy means about $GUESS_GOOD packages should be reproducibly buildable! Join <code>#debian-reproducible</code> on OFTC to get support for making sure your packages build reproducibly too!</p></header>"
write_index "<p>$COUNT_BAD packages ($PERCENT_BAD% of $COUNT_TOTAL) failed to built reproducibly: <code>"
EXTRA_STAR=true
link_packages $BAD
EXTRA_STAR=false
write_index "</code></p>"
write_index "<p><font size=\"-1\">A &beta; sign after a package name indicates that no .buildinfo files were generated.</font></p>"
write_index
write_index "<p>$COUNT_UGLY packages ($PERCENT_UGLY%) failed to build from source: <code>"
link_packages $UGLY
write_index "</code></p>"
if [ $COUNT_SOURCELESS -gt 0 ] ; then
	write_index "<p>$COUNT_SOURCELESS ($PERCENT_SOURCELESS%) packages where the source could not be downloaded. <code>$SOURCELESS</code></p>"
fi
if [ $COUNT_NOTFORUS -gt 0 ] ; then
	write_index "<p>$COUNT_NOTFORUS ($PERCENT_NOTFORUS%) packages which are neither Architecture: 'any' nor 'all' nor 'amd64' nor 'linux-amd64': <code>$NOTFORUS</code></p>"
fi
if [ $COUNT_BLACKLISTED -gt 0 ] ; then
	write_index "<p>$COUNT_BLACKLISTED packages are blacklisted and will never be tested here: <code>$BLACKLISTED</code></p>"
fi
write_index "<p>$COUNT_GOOD packages ($PERCENT_GOOD%) successfully built reproducibly: <code>"
link_packages $GOOD
write_index "</code></p>"
write_index "<hr/><h1>Packages which failed to build reproducibly, sorted by Maintainers: and Uploaders: fields</h1>"
write_index "<p><pre>$(echo $BAD | dd-list -i) </pre></p>"
write_index "<hr/><p><font size='-1'><a href=\"$JENKINS_URL/userContent/reproducible.html\">Static URL for this page.</a> Last modified: $(date). Copyright 2014 <a href=\"mailto:holger@layer-acht.org\">Holger Levsen</a>, GPL-2 licensed.</font>"
write_index "</p></body></html>"
echo

# job output
cp index.html /var/lib/jenkins/userContent/reproducible.html
