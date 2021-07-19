#! /bin/sh

# we just test creating a vanilla jail

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/general

$jtPath new $jail 2>&1 || exit 1

uid=$(id -u)

jUid=$($jtPath start $jail id -u 2>/dev/null)

echo "jail UID must be the user's UID -- user id : $uid ---- jail user id : $jUid"
[ "$uid" != "$jUid" ] && exit 1

echo "jail UID must not be the root UID"
[ "$jUid" = "0" ] && exit 1

exit 0
