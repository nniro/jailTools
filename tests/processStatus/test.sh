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

$jtPath new $jail >/dev/null 2>/dev/null || exit 1

cd $jail

$jtPath daemon >/dev/null 2>/dev/null || exit 1

s1=$($jtPath status -p 2>/dev/null | sed -e '$ d')
s2=$($jtPath shell ps 2>/dev/null | sed -e '$ d')

$jtPath stop 2>/dev/null || exit 1

if [ "$s1" != "$s2" ]; then
	echo "Incorrect status in 'jt status -p'"
	echo "got : $s1"
	echo "should be : $s2"
	exit 1
fi

exit 0
