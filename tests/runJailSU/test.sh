#! /bin/sh

# we create a privileged jail and start it in the 3 ways

sh=$1
testPath=$2
jtPath=$3

bb=$testPath/../bin/busybox

. $testPath/../../utils/utils.sh

jail=$testPath/basic

$jtPath new $jail >/dev/null 2>/dev/null || exit 1

lift $jtPath daemon $jail 2>/dev/null || exit 1

if ! echo exit | $jtPath shell $jail 2>/dev/null; then
	echo "Attempt to re-enter the daemonized jail failed"
	exit 1
fi

# attempting to re-enter the daemonized jail as root
if ! echo exit | lift $jtPath shell $jail 2>/dev/null; then
	echo "Reentry into the jail should be possible as root but it is not."
	exit 1
fi

# Stopping the daemonized jail
lift $jtPath stop $jail 2>&1 || exit 1
sleep 1

exit 0
