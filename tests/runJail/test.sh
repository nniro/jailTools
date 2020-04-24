#! /bin/sh

# we create a unprivileged jail and start it in the 3 ways

sh=$1
testPath=$2
jtPath=$3

$jtPath new $testPath/basic 2>&1 || exit 1
cd $testPath/basic
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh
echo starting the jail
echo exit | $jtPath start 2>&1 || exit 1

echo Starting a daemon
$jtPath daemon 2>&1 || exit 1
timeout 5 sh -c 'while :; do if [ -e run/jail.pid ]; then break; fi ; done'

if [ ! -e run/jail.pid ]; then
	echo "The daemonized jail is not running, run/jail.pid is missing"
	exit 1
fi

echo "Attempting to re-enter the daemonized jail"
echo exit | $jtPath shell 2>&1 || exit 1
echo "Stopping the daemonized jail"
$jtPath stop 2>&1 || exit 1
sleep 1

echo "Starting a jail with the shell command"
echo exit | $jtPath shell 2>&1 || exit 1

echo "Now we start a new jail and expect it to actually fail"
sed -e 's/^\(startCommand=\)""$/\1"fusionReactorStarter ignite ahahahah"/' -i rootCustomConfig.sh
echo exit | $jtPath start 2>&1 && exit 1


exit 0
