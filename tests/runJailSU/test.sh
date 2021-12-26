#! /bin/sh

# we create a privileged jail and start it in the 3 ways

sh=$1
testPath=$2
jtPath=$3

bb=$testPath/../bin/busybox

. $testPath/../../utils/utils.sh

$jtPath new $testPath/basic 2>&1 || exit 1
cd $testPath/basic

echo Starting a daemon
lift $jtPath daemon $testPath/basic 2>/dev/null || exit 1
echo "Started the jail, now we check if it's actually running"
$bb timeout 5 sh -c 'while :; do if [ -e run/jail.pid ]; then break; fi ; done'

echo "checking to see if the jail is running"
if [ ! -e run/jail.pid ]; then
	echo "The daemonized jail is not running, run/jail.pid is missing"
	exit 1
fi

echo "Attempting to re-enter the daemonized jail"
echo exit | $jtPath shell 2>&1 || exit 1
echo "Stopping the daemonized jail"
lift $jtPath stop $testPath/basic 2>&1 || exit 1
sleep 1

exit 0
