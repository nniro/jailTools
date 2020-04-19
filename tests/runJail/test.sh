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
sleep 1

echo "Starting a jail with the shell command"
echo exit | $jtPath shell || exit 1

echo "Now we start a new jail and expect it to actually fail"
sed -e 's/^\([[:space:]]*runJail \$rootDir\).*$/\1 fusionReactorStarter ignite ahahahah/' -i rootCustomConfig.sh
#echo exit | $jtPath start 2>&1 && exit 1
echo exit | $jtPath start && exit 1


if (($err = 0)) ; then
	echo "Error should be anything else than 0 (which it is)"
	grep "[[:space:]]*runJail \$rootDir" rootCustomConfig.sh
	exit 1
fi

exit 0
