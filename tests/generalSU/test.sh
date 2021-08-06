#! /bin/sh

# we just test creating a vanilla jail

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/general

lift() {
	echo "$@" > $testPath/../fifo
	cat $testPath/../fifo
}

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

lift $jtPath start $jail ping -w 1 example.com 2>/dev/null | grep -q "permission denied" && exit 1

exit 0
