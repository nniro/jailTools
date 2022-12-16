#! /bin/sh

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/listJail

$jtPath new $jail 2>/dev/null >/dev/null || exit 1

if $jtPath start $jail sh -c 'jt ls 2>/dev/null' 2>/dev/null; then
	echo "list is not supposed to work in an empty jail."
       	exit 1
fi

# quick zombie check

if $jtPath start $jail sh -c 'jt ls -z' >/dev/null 2>/dev/null; then
	echo "A newly created jail should not have zombie jail processes"
	exit 1
fi

$jtPath daemon $jail 2>/dev/null

if $jtPath shell $jail sh -c 'jt ls -z' >/dev/null 2>/dev/null; then
	echo "A newly created jail and started as a daemon should not have zombie jail processes"
	$jtPath stop $jail 2>/dev/null
	exit 1
fi
$jtPath stop $jail 2>/dev/null

# create a child jail
$jtPath start $jail sh -c 'jt new /home/childjail 2>/dev/null >/dev/null' 2>/dev/null || exit 1

$jtPath daemon $jail 2>/dev/null

# giving 6 seconds maximum timeout for the jail to start the daemon
timeout 6 sh -c "while :; do if [ -e $jail/run/jail.pid ]; then break; fi ; sleep 0.5 ; done"
if [ ! -e $jail/run/jail.pid ]; then
	echo "The daemonized jail is not running, missing $jail/run/jail.pid"
	exit 1
fi

#echo started the jail as a daemon >&2

$jtPath shell $jail sh -c 'jt daemon /home/childjail 2>/dev/null' 2>/dev/null

sleep 6

#echo started the child jail as a daemon >&2

if ! $jtPath shell $jail sh -c 'jt ls >/dev/null 2>/dev/null' 2>/dev/null; then
	echo "We are supposed to see the child jail."
       	exit 1
fi

if ! $jtPath shell $jail sh -c 'jt ls childjail >/dev/null 2>/dev/null' 2>/dev/null; then
	echo "We are supposed to see the child jail (direct version)"
       	exit 1
fi

$jtPath shell $jail sh -c 'jt stop /home/childjail 2>/dev/null' 2>/dev/null
$jtPath stop $jail 2>/dev/null

exit 0
