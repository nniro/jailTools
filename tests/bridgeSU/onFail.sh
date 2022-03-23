#! /bin/sh

sh=$1
testPath=$2
jtPath=$3

. $testPath/../../utils/utils.sh

jail1=$testPath/bridgePrimus
jail2=$testPath/bridgeSecondus

if [ -e $jail1/run/jail.pid ]; then
	lift $jtPath stop $jail1
	sleep 1

	if [ ! -e $jail1/run/jail.pid ] ; then
		:
	fi
else
	echo "$jail1/run/jail.pid doesn't exist"
fi

if [ -e $jail2/run/jail.pid ]; then
	lift $jtPath stop $jail2
	sleep 1

	if [ ! -e $jail2/run/jail.pid ] ; then
		exit 0
	fi
else
	echo "$jail2/run/jail.pid doesn't exist"
	exit 0
fi

exit 1
