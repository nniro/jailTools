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
$jtPath config $jail -s setNetAccess false >/dev/null

cd $jail

$jtPath daemon >/dev/null 2>/dev/null || exit 1

# we check the status command itself
# which is used to figure if a jail is running or not.

if [ -e $jail/run/ns.pid ] && [ -e $jail/run/jail.pid ]; then
	psOutput="$($bb ps)"
	if	printf "%s" "$psOutput" | grep -q "^ *$(cat $jail/run/ns.pid) "\
		&& printf "%s" "$psOutput" | grep -q "^ *$(cat $jail/run/jail.pid) "; then
		# at this point, we know that the jail is running or we need to make sure that we 100% know.

		if ! $jtPath status ; then
			echo "We know the jail is running but it is not detected as so."
			exit 1
		fi
	else
		echo "The jail has the necessary pid files but we could not detect any process running from them."
		echo "We are looking for pids : $(cat $jail/run/ns.pid) and $(cat $jail/run/jail.pid)"
		echo "here is the full ps output :"
		printf "%s" "$psOutput\n"
		echo "here is the filtered ps output :"
		printf "%s" "$psOutput" | grep "^ *\($(cat $jail/run/ns.pid)\|$(cat $jail/run/jail.pid)\) "

		$jtPath stop $jail 2>/dev/null || exit 1
		exit 1
	fi
else
	echo "We expect the jail to be running at this point but it is not"
	$jtPath stop $jail 2>/dev/null || exit 1
	exit 1
fi

s1=$($jtPath status -p 2>/dev/null | sed -e '$ d')
s2=$($jtPath shell ps 2>/dev/null | sed -e '$ d')

$jtPath stop 2>/dev/null || exit 1

if [ "$s1" != "$s2" ]; then
	echo "Incorrect status in 'jt status -p'"
	echo "got : '$s1'"
	echo "should be : '$s2'"
	exit 1
fi

exit 0
