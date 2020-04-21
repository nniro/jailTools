#! /bin/sh

# we create a privileged jail and start it in the 3 ways

sh=$1
testPath=$2
jtPath=$3

lift() {
	echo "$@" > $testPath/../fifo
}

$jtPath new $testPath/basic 2>&1 || exit 1
cd $testPath/basic
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh

echo Starting a daemon
lift $jtPath daemon $testPath/basic 2>&1 || exit 1
timeout 5 sh -c 'while :; do if [ -e run/jail.pid ]; then break; fi ; done'

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
