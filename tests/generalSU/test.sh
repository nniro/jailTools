#! /bin/sh

# privileged general test

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/generalSU

bb=$testPath/../bin/busybox

. $testPath/../../utils/utils.sh

$jtPath new $jail >/dev/null 2>/dev/null || exit 1

uid=$(id -u)

jUid=$(lift $jtPath start $jail id -u 2>/dev/null)

if [ "$uid" != "$jUid" ]; then
	echo "jail UID must be the user's UID -- user id : '$uid' ---- jail user id : '$jUid'"
	exit 1
fi

if [ "$jUid" = "0" ]; then
	echo "jail UID must not be the root UID"
	exit 1
fi

# check the realRootInJail config which is supposed to provide in jail root.
# Of course, for an unprivileged instance we only expect the fake root.

# Setting the configuration : realRootInJail

$jtPath config $jail -s realRootInJail true >/dev/null 2>/dev/null

jUid=$(lift $jtPath start $jail id -u 2>/dev/null)
#jUid=$(lift $jtPath start $jail id -u)

if [ "$jUid" != "0" ]; then
	echo "With realRootInJail, jail UID must be the root UID we got : $jUid instead of 0"
	cat $jail/run/innerCoreLog
	exit 1
fi

# Doing a test by making a directory, changing it's ownership to root and checking it
if ! lift $jtPath start $jail mkdir /home/testDir 2>$jail/run/errorInfo; then
	echo "Unable to create the directory /home/testDir"
	cat $jail/run/errorInfo
	exit 1
fi

if ! lift $jtPath start $jail chown root /home/testDir 2>$jail/run/errorInfo; then
	echo "Attempt to change ownership of /home/testDir to root failed"
	cat $jail/run/errorInfo
	ls $jail/root
	exit 1
fi

if ! $bb stat -c %U $jail/root/home/testDir | grep -q root; then
	echo "user owning the directory : '$($bb stat -c %U $jail/root/home/testDir)' (expecting 'root')"
	exit 1
fi

# we test realRootInJail with a shell reentry in a daemon

$jtPath config $jail -s realRootInJail true >/dev/null 2>/dev/null

if ! lift $jtPath daemon $jail 2>/dev/null; then
	echo "Could not start a daemon instance"
	exit 1
fi

jUid=$(lift $jtPath shell $jail id -u 2>/dev/null)

if [ ! "$jUid" = "0" ]; then
	echo "daemon - jail UID must be the root UID - got $jUid and should be 0"
	lift $jtPath stop $jail 2>/dev/null || exit 1
	sleep 1
	exit 1
fi

if $jtPath shell $jail mkdir /home/testDirBogus 2>/dev/null; then
	echo "daemon - We are not supposed to be able to reenter this jail unprivileged"
	lift $jtPath stop $jail 2>/dev/null || exit 1
	exit 1
fi

if ! lift $jtPath shell $jail mkdir /home/testDir2 2>/dev/null; then
	echo "daemon - Could not create a directory"
	lift $jtPath stop $jail 2>/dev/null || exit 1
	exit 1
fi
if ! lift $jtPath shell $jail chown root /home/testDir2 2>/dev/null; then
	echo "daemon - Could not chown as root a directory"
	lift $jtPath stop $jail 2>/dev/null || exit 1
	exit 1
fi

if ! $bb stat -c %U $jail/root/home/testDir2 | grep -q root; then
	echo "daemon - user owning the directory : '$($bb stat -c %U $jail/root/home/testDir2)' (expecting 'root')"
	lift $jtPath stop $jail 2>/dev/null || exit 1
	sleep 1
	exit 1
fi

if ! lift $jtPath stop $jail 2>/dev/null; then
	echo  "Stopping daemonized jail failed"
	exit 1
fi
sleep 1

# test jt itself, embedded in busybox

# we of course expect this one to work
s1=$($jtPath v)
# now this is what we test (we reset PATH just in case it is installed)
s2=$(PATH= $jtPath busybox jt v)

if [ "$s1" != "$s2" ]; then
	echo "the embedded jt is not working correctly"
	PATH= $jtPath busybox jt v
	exit 1
fi

exit 0
