#! /bin/sh

# we just test creating a vanilla jail

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/generalSU

lift() {
	echo "$@" > $testPath/../fifo
	cat $testPath/../fifo
}

bb=$testPath/../bin/busybox

$jtPath new $jail 2>&1 || exit 1

uid=$(id -u)

jUid=$(lift $jtPath start $jail id -u 2>/dev/null)

echo "jail UID must be the user's UID -- user id : $uid ---- jail user id : $jUid"
[ "$uid" != "$jUid" ] && exit 1

echo "jail UID must not be the root UID"
[ "$jUid" = "0" ] && exit 1

# check the realRootInJail config which is supposed to provide in jail root.
# Of course, for an unprivileged instance we only expect the fake root.

echo "Setting the configuration : realRootInJail"

$jtPath config $jail -s realRootInJail true

jUid=$(lift $jtPath start $jail id -u 2>/dev/null)

echo "jail UID must be the root UID"
[ "$jUid" = "0" ] || exit 1

echo "Doing a test by making a directory, changing it's ownership to root and checking it"
$jtPath start $jail sh -c 'mkdir /home/testDir'
lift $jtPath start $jail chown root /home/testDir 2>/dev/null || exit 1
echo "user owning the directory : '$($bb stat -c %U $jail/root/home/testDir)' (expecting 'root')"
$bb stat -c %U $jail/root/home/testDir | grep -q root || exit 1

exit 0
