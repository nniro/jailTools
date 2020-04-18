#! /bin/sh

# we create a unprivileged jail and start it in the 3 ways

sh=$1
testPath=$2
jtPath=$3

$jtPath new $testPath/basic >/dev/null || exit 1
cd $testPath/basic
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh
echo starting the jail
echo exit | $jtPath start 2>&1 || exit 1

echo Starting a daemon
$jtPath daemon 2>&1 || exit 1
sleep 1

if [ ! -e run/jail.pid ]; then
	echo "The daemonized jail is not running, run/jail.pid contains : '$(cat run/jail.pid)'" 2>&1
	exit 1
fi

echo "Attempting to re-enter the daemonized jail"
echo exit | $jtPath shell || exit 1
echo "Stopping the daemonized jail"
$jtPath stop || exit 1

echo "Starting a jail with the shell command"
echo exit | $jtPath shell || exit 1

exit 0
