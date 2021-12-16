#! /bin/sh

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/listJail

if [ -e $jail/run/jail.pid ]; then
	$jtPath stop $jail
fi

exit 0
