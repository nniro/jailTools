#! /bin/sh

sh=$1
testPath=$2
jtPath=$3

. $testPath/../../utils/utils.sh

jail=$testPath/firewall

if [ -e $jail/run/jail.pid ]; then
	lift $jtPath stop $jail
	sleep 1

	if [ ! -e run/jail.pid ] ; then
		exit 0
	fi
else
	echo "run/jail.pid doesn't exist"
	exit 0
fi

exit 1
