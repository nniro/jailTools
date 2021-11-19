#! /bin/sh

debugging=false

tf=tests

# this is the variable that is set when this script is being run as root.
# the privileged part re-run the script unprivileged but sets this variable to
# flag the availability of the powerbox.
# POWERBOX
user=

. ../scripts/paths.sh # this sets the variable 'bb'

privileged=0

lift() {
	[ -e $tf/fifo ] && echo $@ > $tf/fifo
}

if [ "$(id -u)" != "0" ]; then
	if [ "$POWERBOX" = "" ]; then
		echo "This script has limited testing abilities when it's not run as root" >&2
	else
		privileged=1
	fi
	user=$(id -u)
else # the user is root

	uid=$($bb stat -c %u $0)
	gid=$($bb stat -c %g $0)

	[ ! -d $tf ] && $bb chpst -u $uid:$gid mkdir $tf

	# we set a powerbox to do the commands
	[ ! -e $tf/fifo ] && $bb chpst -u $uid:$gid mkfifo $tf/fifo

	(
		while :; do
			[ "$debugging" = "true" ] && echo "[powerbox] waiting for input" >&2
			in=$(cat $tf/fifo);
			if [ "$in" = "quit" ]; then
				[ "$debugging" = "true" ] && echo "[powerbox] got the quit command, quitting" >&2
				exit 0
			fi
			[ "$debugging" = "true" ] && echo "[powerbox] got the input : '$in'" >&2
			if echo "$in" | grep -q "^$PWD/$tf/bin/jt/[^/]*/jt [^ ]*\( $PWD/$tf/.*\|\)$"; then
				$in 2> $tf/debug > $tf/result
				[ "$debugging" = "true" ] && echo [powerbox] sending reply back to sender >&2
				$bb timeout 2 $bb sh -c "cat $tf/result > $tf/fifo"
			else
				[ "$debugging" = "true" ] && echo [powerbox] command denied >&2
			fi
		done
	) &
	powerboxId=$!

	# we re-run this script as the normal user
	$bb env - POWERBOX=fifo $bb chpst -u $uid:$gid $bb sh $0 $@

	rm $tf/fifo

	exit 0
fi

# test folder
[ ! -d $tf ] && mkdir $tf

[ -d $tf/bin ] && rm -R $tf/bin
mkdir $tf/bin

# we provide our own busybox
cp $bb $tf/bin
(cd $tf/bin; ln -s busybox sh)

# list all available shells that we support

# We support :
#	dash
#	busybox ash
#	zsh
#	bash

availShells="$tf/bin/busybox"


shells=""

# link all of them into bin/ and treat busybox differently
echo "Available supported shells : "
for shell in $availShells; do
	shellName=$(basename $shell)
	echo "	$shellName"
	if [ "$shellName" = "busybox" ]; then
		shellName=sh
	else
		[ ! -e $tf/bin/$shellName ] && ln -s $shell $tf/bin/$shellName
	fi
	[ "$shells" = "" ] && shells="$shellName" || shells="$shells $shellName"
done

#echo "$shells"

# create bin/jt

[ ! -d $tf/bin/jt ] && mkdir $tf/bin/jt

# install jt in each shell directory in bin/jt/

for shell in $shells; do
	#echo "$tf/bin/$shell $([ -e $tf/bin/$shell ] && echo yes || echo no)"
	[ ! -d $tf/bin/jt/$shell ] && mkdir $tf/bin/jt/$shell
	[ ! -e $tf/bin/jt/$shell/jt ] && $tf/bin/$shell ../install.sh $PWD/$tf/bin/jt/$shell/ >/dev/null 2>/dev/null
done

availTests=$(cat << EOF
$(cat availableTests)
EOF
)

echo "available tests :"
echo "$availTests"

filter=""
if [ $(( $# > 0 )) = 1 ] ; then
	regex=$(echo "$@" | sed -e 's/ /\\|/g' | sed -e 's/\(.*\)/^\\(\1\\)$/')
	availTests=$(printf "%s" "$availTests" | grep "$regex")
fi


echo "Will run these tests :"
echo "$availTests"

echo
isFailed=0
for shell in $shells; do
	echo
	echo "Doing tests with the shell $shell"
	shellPath=$PWD/$tf/bin/$shell
	jtPath=$PWD/$tf/bin/jt/$shell/jt
	for cTest in $availTests; do
		if $(echo $cTest | grep -q 'SU$') ; then
			if [ "$privileged" = "0" ]; then
				echo "The test $cTest can't be run as an unprivileged user"
				continue
			fi
		fi
		if [ -d $cTest ]; then
			printf "Test $cTest with $shell : "
			if [ -d $tf/$cTest ]; then
				echo "A previously failed test still lingers, please delete it manually"
				isFailed=1
				break
			fi
			mkdir $PWD/$tf/$cTest
			result=$($shell $cTest/test.sh $shellPath $PWD/$tf/$cTest $jtPath)
		       	if [ $? = 0 ]; then
				echo passed

				timeout 5 sh -c 'while :; do if [ -e run/jail.pid ]; then break; fi ; done'
				if find $tf/$ctest | grep -q jail.pid ; then
					echo "We detected a running jail where there should be none. Automatically failing the test."
					isFailed=1
				fi
			else
				echo failed
				isFailed=1
			fi

			if [ "$isFailed" = "1" ]; then
				printf "Test failed with : \n\n%s\n\n" "$result"

				echo "Attempting to automatically cleanse the test"
				$bb timeout 5 sh -c 'while :; do if [ -e run/jail.pid ]; then break; fi ; done'
				$shell $cTest/onFail.sh $shellPath $PWD/$tf/$cTest $jtPath

				if [ "$?" = "1" ]; then
					echo "Automatic cleanse failed"
					echo "This test has failed and we didn't manage to stop it : Please manually stop it and delete it's files manually, they are in $tf/$cTest"
					break
				else
					echo "Automatic cleanse complete"
					rm -Rf $tf/$cTest
					break
				fi
			fi
			rm -Rf $tf/$cTest
		fi
	done

	if [ "$isFailed" = "1" ]; then
		break
	fi
done

# stop the powerbox
if [ "$privileged" = "1" ]; then
	[ "$debugging" = "true" ] && echo "Shutting down the powerbox" >&2
	sleep 2
	lift quit
fi
