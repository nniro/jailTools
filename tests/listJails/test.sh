#! /bin/sh

sh=$1
testPath=$2
jtPath=$3

bb=$testPath/../bin/busybox

jail=$testPath/listJail

$jtPath new $jail 2>/dev/null >/dev/null || exit 1

if $jtPath start $jail sh -c 'jt ls' 2>/dev/null; then
	echo "list is not supposed to work in an empty jail."
       	exit 1
fi

# quick zombie check

if $jtPath start $jail sh -c 'jt ls -z' >/dev/null 2>/dev/null; then
	echo "A newly created jail should not have zombie jail processes"
	exit 1
fi

if unshare -rp id >/dev/null; then
	if ! $jtPath start $jail unshare -rp id >/dev/null 2>/dev/null; then
		echo "PID namespace nesting inside a standalone jail is not working correctly."
		exit 1
	fi
fi

$jtPath daemon $jail 2>/dev/null

if $jtPath shell $jail sh -c 'jt ls -z' >/dev/null 2>/dev/null; then
	echo "A newly created jail and started as a daemon should not have zombie jail processes"
	$jtPath stop $jail 2>/dev/null
	exit 1
fi
$jtPath stop $jail 2>/dev/null

# create a child jail
if ! $jtPath start $jail sh -c 'jt new /home/childjail' >/dev/null 2>$jail/run/errorLog; then
	echo "Unable to create the childJail"
	cat $jail/run/errorLog
	exit 1
fi

$jtPath daemon $jail 2>/dev/null

# giving 6 seconds maximum timeout for the jail to start the daemon
timeout 6 sh -c "while :; do if [ -e $jail/run/jail.pid ]; then break; fi ; sleep 0.5 ; done"
if [ ! -e $jail/run/jail.pid ]; then
	echo "The daemonized jail is not running, missing $jail/run/jail.pid"
	exit 1
fi

$jtPath shell $jail sh -c 'jt daemon /home/childjail' 2>/dev/null

if ! $jtPath shell $jail sh -c 'cd /home/childjail; jt status' >/dev/null 2>/dev/null; then
	if [ -e $jail/root/home/childjail/run/ns.pid ] \
		&& [ -e $jail/root/home/childjail/run/jail.pid ] \
		&& $jtPath shell $jail ps 2>/dev/null | grep -q " \+$(cat $jail/root/home/childjail/run/ns.pid) \+" \
		&& $jtPath shell $jail ps 2>/dev/null | grep -q " \+$(cat $jail/root/home/childjail/run/jail.pid) \+" ; then
		echo "The daemonized child jail is not detected as running but there is evidence of the contrary."
		echo "This means jt status has a bug or there's a fundamental issue."
		exit 1
	fi
	echo "The child jail doesn't seem to be running at all when it should"
	exit 1
fi

# we should get the childJail's run/ns.pid value and grep that from the result of 'jt ls' and
# check if we find it.
if ! $jtPath shell $jail sh -c 'jt ls' >$jail/run/lsLog 2>/$jail/run/errorLog; then
	echo "We are supposed to see the child jail."
	echo "output log : "
	cat $jail/run/lsLog
	echo "error log : "
	cat $jail/run/errorLog
	echo "childJail/run/ content :"
	ls $jail/root/home/childjail/run/
       	exit 1
fi

if ! $jtPath shell $jail sh -c 'jt ls childjail' >/dev/null 2>/dev/null; then
	echo "We are supposed to see the child jail (direct version)"
       	exit 1
fi

$jtPath shell $jail sh -c 'jt stop /home/childjail' 2>/dev/null
$jtPath stop $jail 2>/dev/null

exit 0
