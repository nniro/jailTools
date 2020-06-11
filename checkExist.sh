#! /bin/sh


for cmd in autoconf autoreconf automake m4; do
	if which $cmd >/dev/null 2>/dev/null; then
		:
	else
		echo "Missing the command $cmd, please install it first"
		exit 1
	fi
done

touch .ready
