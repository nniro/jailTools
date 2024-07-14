#! /bin/sh

# we just test creating a vanilla jail

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/basic

bb=$testPath/../bin/busybox

$jtPath new $jail >/dev/null 2>/dev/null || exit 1

# we check that the bind mount to /lib is read-only and executable
result=$($jtPath start $jail mount 2>/dev/null | grep ' \/lib ' | sed -e 's/.*\(([^)]*)\)$/\1/')
if ! echo $result | grep -q '\((ro\|,ro,\|,ro)\)'; then
	echo "We expect /lib to be bind mounted as read-only"
	exit 1
fi

# test the status command

if $jtPath status $jail >/dev/null; then
	echo "The command 'status' is stating the jail is running when it is not"
	exit 1
fi

$jtPath start $jail sh -c 'while :; do sleep 9999; done' >/dev/null 2>/dev/null &

$bb timeout 20 sh -c "while :; do [ -e $jail/run/ns.pid ] && [ -e $jail/run/jail.pid ] && break ; done"

if [ ! -e $jail/run/ns.pid ] || [ ! -e $jail/run/jail.pid ]; then
	echo "The jail is not running, run/ns.pid or run/jail.pid is missing" >&2
	exit 1
fi

# we check manually that the jail is running

jailPidProcess="$($bb ps | grep "^$(cat $jail/run/jail.pid) *")"
nsPidProcess="$($bb ps | grep "^$(cat $jail/run/ns.pid) *")"

if [ "$jailPidProcess" = "" ] \
	|| ! echo "$jailPidProcess" | grep -q '^[0-9]\+ *[^ ]\+ *[0-9]\+ *[^ ]* *{jt}'; then
	echo "The jail Pid Process is not correct, the jail is not running"
	exit 1
fi

if [ "$nsPidProcess" = "" ] \
	|| ! echo "$nsPidProcess" | grep -q '^[0-9]\+ *[^ ]\+ *[0-9]\+ *[^ ]* *sh -c while :; do /bin/busybox sleep 9999; done'; then
	echo "The ns Pid Process is not correct, the jail is not running"
	exit 1
fi

# now we established manually that the jail is running, we test the command 'status'

if ! $jtPath status $jail >/dev/null; then
	echo "The 'status' command could not detect that the jail is running when it actually is."
	[ -e $jail/run/ns.pid ] && $bb ps | $bb grep "^$(cat $jail/run/ns.pid)"
	cat $jail/run/daemon.log
	exit 1
fi

$jtPath stop $jail

# test simply starting a jail as a daemon
$jtPath daemon $jail || exit 1

if ! $jtPath status $jail >/dev/null; then
	$jtPath status $jail
	echo
	echo "Jail started as a daemon should be running but it's not"
	echo ""
	ls $jail/run
	echo ""
	cat $jail/run/daemon.log
	exit 1
fi

$jtPath stop $jail

exit 0
