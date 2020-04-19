#! /bin/sh

tf=tests

privileged=0
if [ "$(id -u)" != "0" ]; then
	echo "This script has limited testing abilities when it's not run as root"
else # the user is root
	privileged=1
fi

# test folder
[ ! -d $tf ] && mkdir $tf

[ -d $tf/bin ] && rm -R $tf/bin
mkdir $tf/bin

# we provide our own busybox
cp ../busybox/busybox $tf/bin
(cd $tf/bin; ln -s busybox sh)

# list all available shells that we support

# We support :
#	dash
#	busybox ash
#	zsh
#	bash

availShells="$tf/bin/busybox"

for cmd in dash zsh bash; do
	cmdPath="${cmd}Path"
	eval "$cmdPath"="$(PATH="$PATH:/sbin:/usr/sbin:/usr/local/sbin" command which $cmd 2>/dev/null)"
	eval "cmdPath=\${$cmdPath}"

	availShells="$availShells $cmdPath"
done

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

# install jailtools in each shell directory in bin/jt/

for shell in $shells; do
	#echo "$tf/bin/$shell $([ -e $tf/bin/$shell ] && echo yes || echo no)"
	[ ! -d $tf/bin/jt/$shell ] && mkdir $tf/bin/jt/$shell
	[ ! -e $tf/bin/jt/$shell/jailtools ] && $tf/bin/$shell ../install.sh $PWD/$tf/bin/jt/$shell/ >/dev/null 2>/dev/null
done

availTests=$(cat << EOF
$(cat availableTests)
EOF
)

echo "available tests :"
echo "$availTests"

filter=""
if (($# > 0)); then
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
	shellPath=$tf/bin/$shell
	jtPath=$PWD/$tf/bin/jt/$shell/jailtools
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
			mkdir $tf/$cTest
			result=$($shell $cTest/test.sh $shellPath $tf/$cTest $jtPath 2>/dev/null)
		       	if [ $? = 0 ]; then
				echo passed
			else
				echo failed
				isFailed=1
			fi

			if find $tf/$ctest | grep -q jail.pid ; then
				echo "We detected a running jail where there should be none. Automatically failing the test."
				isFailed=1
			fi

			if [ "$isFailed" = "1" ]; then
				printf "Test failed with : \n\n%s\n\n" "$result"

				echo "Attempting to automatically cleanse the test"
				$shell $cTest/onFail.sh $shellPath $tf/$cTest $jtPath

				if [ "$?" = "1" ]; then
					echo "Automatic cleanse failed"
					echo "This test has failed and we didn't manage to stop it : Please manually stop it and delete it's files manually, they are in $tf/$cTest"
					break
				else
					echo "Automatic cleanse complete"
				fi
			fi
			rm -R $tf/$cTest
		fi
	done

	if [ "$isFailed" = "1" ]; then
		break
	fi
done
