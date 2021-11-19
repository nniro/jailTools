#! /bin/sh

# we just test creating a vanilla jail

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/general

$jtPath new $jail 2>/dev/null || exit 1

uid=$(id -u)

jUid=$($jtPath start $jail id -u 2>/dev/null)

if [ "$uid" != "$jUid" ]; then
	echo "jail UID must be the user's UID -- user id : $uid ---- jail user id : $jUid"
fi

if [ "$jUid" = "0" ];
	echo "jail UID must not be the root UID"
	exit 1
fi

# check the realRootInJail config which is supposed to provide in jail root.
# Of course, for an unprivileged instance we only expect the fake root.

# Setting the configuration : realRootInJail
$jtPath config $jail -s realRootInJail true

jUid=$($jtPath start $jail id -u 2>/dev/null)

if [ "$jUid" != "0" ]; then
	echo "jail UID must be the root UID"
	exit 1
fi

exit 0
