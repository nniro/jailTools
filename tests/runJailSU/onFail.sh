#! /bin/sh

sh=$1
testPath=$2
jtPath=$3

lift() {
	echo "$@" > $testPath/../fifo
}

cd $testPath/basic
if [ -e run/jail.pid ]; then
	lift $jtPath stop $testPath/basic
	sleep 1

	if [ ! -e run/jail.pid ] ; then
		exit 0
	fi
else
	echo "run/jail.pid doesn't exist"
	exit 0
fi

exit 1
