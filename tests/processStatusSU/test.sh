#! /bin/sh

# this is for testing the jt superscript command : status
# first we test that it's actually working correctly by testing
# if jt status -p  shows the same thing as jt shell ps
# there has been a bug that anything started in the daemon command part
# will not show in the jail's status ps at all. We will need to test this
# by starting a http server and checking if the status contains it.

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/processStatus

. $testPath/../../utils/utils.sh

$jtPath new $jail >/dev/null 2>/dev/null || exit 1

lift $jtPath daemon $jail >/dev/null 2>/dev/null || exit 1

if ! lift $jtPath status $jail >/dev/null 2>/dev/null; then
	echo "It should be possible to get the status of a running jail with a privileged shell."
	lift $jtPath stop $jail 2>/dev/null || exit 1
	sleep 1
	exit 1
fi

if ! $jtPath status $jail >/dev/null; then # 2>/dev/null; then
	echo "It should be possible to get the status of a running jail with an unprivileged shell."
	lift $jtPath stop $jail 2>/dev/null || exit 1
	sleep 1
	exit 1
fi

s1=$($jtPath status $jail -p 2>/dev/null | sed -e '$ d')
s2=$($jtPath shell $jail ps 2>/dev/null | sed -e '$ d')

s3=$(lift $jtPath status $jail -p 2>/dev/null | sed -e '$ d')
s4=$(lift $jtPath shell $jail ps 2>/dev/null | sed -e '$ d')

lift $jtPath stop $jail 2>/dev/null || exit 1
sleep 1

if [ "$s1" != "$s2" ]; then
	echo "unprivileged - Incorrect status in 'jt status -p'"
	echo "got : $s1"
	echo "should be : $s2"
	exit 1
fi

if [ "$s3" != "$s4" ]; then
	echo "privileged - Incorrect status in 'jt status -p'"
	echo "got : $s1"
	echo "should be : $s2"
	exit 1
fi

exit 0
