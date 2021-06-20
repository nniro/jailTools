#! /bin/sh

gcc=$1

if [ "$gcc" = "" ]; then
	echo It is necessary to provide a gcc path to this script >&2
	exit 1
fi

if [ -d /usr/include/asm ]; then
	ln -s /usr/include/asm usr/include/asm
else
	host=$($gcc -dumpmachine)
	if [ -d /usr/include/$host/asm ]; then
		ln -s /usr/include/$host/asm usr/include/asm
	else
		echo no >&2
		exit 1
	fi
fi
echo yes
