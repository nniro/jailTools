#! /bin/sh

# we create a unprivileged jail and start it in the 3 ways

sh=$1
testPath=$2
jtPath=$3

bb=$testPath/../bin/busybox

$jtPath new $testPath/basic >/dev/null 2>/dev/null || exit 1
cd $testPath/basic
$jtPath config -s jailNet false >/dev/null
if ! $jtPath start sh -c exit 2>/dev/null; then
	echo "Error starting the jail with 'start'"
	exit 1
fi

if ! $jtPath daemon 2>/dev/null; then
	echo "Error starting the jail with 'daemon'"
	exit 1
fi

if ! $jtPath shell sh -c exit 2>/dev/null; then
	echo "Unable to re-enter the daemonized jail"
	exit 1
fi

if ! $jtPath stop 2>/dev/null; then
	echo "Unable to stop the daemonized jail"
	exit 1
fi
sleep 1

if $jtPath shell sh -c exit 2>/dev/null; then
	echo "Starting a jail just with 'shell' should not work"
	exit 1
fi

$jtPath config -s startCommand "fusionReactorStarter ignite ahahahah" >/dev/null
if $jtPath start 2>/dev/null; then
	echo "The jail was started with a bogus startCommand and was expected to fail but it didn't"
	exit 1
fi

# We check the jail's command line features

if ! $jtPath daemon 2>/dev/null; then
	echo "Error starting the jail with 'daemon' for the command line test"
	exit 1
fi

if ! $jtPath shell sh -c 'cd /usr/sbin; ls httpd' 2>/dev/null | grep -q '^httpd$'; then
	echo "Multiple commands check failed"
	exit 1
fi
$jtPath stop 2>/dev/null || exit 1
sleep 1

exit 0
