#! /bin/sh

ownPath=$(dirname $0)

# convert the path of this script to an absolute path
if [ "$ownPath" = "." ]; then
	ownPath=$PWD
else
	if echo $ownPath | grep -q '^\/'; then
		# absolute path, we do nothing
		:
	else
		# relative path
		ownPath=$PWD/$ownPath
	fi
fi

bb=$ownPath/build/busybox/busybox

if [ "$1" != "" ]; then
	if [ ! -e $bb ]; then
		echo "Busybox not available, Please compile jailTools first."
		exit 1
	fi

	if [ ! -d $1 ]; then
		echo "Please ensure the path is a directory and is writable"
		exit 1
	else

		cp $ownPath/build/busybox/busybox $1/jt
		chmod u+x $1/jt
		echo "Done. Installed \`jt' in $1"
	fi
else
	echo "Please input a directory where you want to install \`jt'"
	exit 1
fi
