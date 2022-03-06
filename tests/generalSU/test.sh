#! /bin/sh

# privileged general test

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/generalSU

bb=$testPath/../bin/busybox

. $testPath/../../utils/utils.sh

$jtPath new $jail 2>/dev/null 2>/dev/null || exit 1

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

$jtPath config $jail -s realRootInJail true 2>/dev/null

jUid=$(lift $jtPath start $jail id -u 2>/dev/null)

if [ ! "$jUid" = "0" ]; then
	echo "jail UID must be the root UID"
	exit 1
fi

# Doing a test by making a directory, changing it's ownership to root and checking it
$jtPath start $jail sh -c 'mkdir /home/testDir' 2>/dev/null
lift $jtPath start $jail chown root /home/testDir 2>/dev/null || exit 1

if ! $bb stat -c %U $jail/root/home/testDir | grep -q root; then
	echo "user owning the directory : '$($bb stat -c %U $jail/root/home/testDir)' (expecting 'root')"
	exit 1
fi

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
