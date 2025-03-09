#! /bin/sh

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/general

$jtPath new $jail >/dev/null 2>/dev/null || exit 1

uid=$(id -u)

jUid=$($jtPath start $jail id -u 2>/dev/null)

if [ "$uid" != "$jUid" ]; then
	echo "jail UID must be the user's UID -- user id : $uid ---- jail user id : $jUid"
fi

if [ "$jUid" = "0" ]; then
	echo "jail UID must not be the root UID"
	exit 1
fi

# check the realRootInJail config which is supposed to provide in jail root.
# Of course, for an unprivileged instance we only expect the fake root.

# Setting the configuration : realRootInJail
$jtPath config $jail -s realRootInJail true >/dev/null 2>/dev/null

jUid=$($jtPath start $jail id -u 2>/dev/null)

if [ "$jUid" != "0" ]; then
	echo "With realRootInJail, jail UID must be the root UID we got : $jUid instead of 0"
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

# test starting a daemon and attempting to start it again

$jtPath daemon $jail || exit 1

if ! $jtPath status $jail >/dev/null; then
	echo "the jail should be running but it's not, bailing out"
	exit 1
fi

$jtPath start $jail sh -c 'exit' 2>/dev/null && _err=1 || _err=0

if [ "$_err" = "1" ] || ! $jtPath status $jail; then
	echo "Attempting to start an already started jail should fail graciously."
	echo "It should not stop the jail."

	exit 1
fi

$jtPath stop $jail >/dev/null 2>/dev/null

$jtPath daemon $jail 2>/dev/null || exit 1

$jtPath daemon $jail 2>/dev/null && _err=1 || _err=0

if [ "$_err" = "1" ] || ! $jtPath status $jail; then
	echo "Attempting to start a daemon of an already started jail should fail graciously."
	echo "It should not stop the jail."

	$jtPath stop $jail >/dev/null 2>/dev/null
	exit 1
fi

$jtPath stop $jail >/dev/null 2>/dev/null

# test if environment variables work correctly when shared with the jail

export BLAH=nothing

$jtPath config $jail -s runEnvironment "BLAH=\$BLAH" >/dev/null 2>/dev/null

if [ "$($jtPath start $jail sh -c 'echo $BLAH' 2>/dev/null)" != "nothing" ]; then
	echo "Simple environment variable substitution test failed."

	exit 1
fi

# we try to put an absolute path in the variable now
export BLAH="/var/log/mailling"

$jtPath config $jail -s runEnvironment "BLAH=\$BLAH" >/dev/null 2>/dev/null

if [ "$($jtPath start $jail sh -c 'echo $BLAH' 2>/dev/null)" != "/var/log/mailling" ]; then
	echo "Environment variable substitution with an absolute path test failed."

	exit 1
fi

exit 0
