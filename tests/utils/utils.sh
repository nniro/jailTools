#! /bin/sh

cmd=$testPath/../fifo
retval=$testPath/../pbRetval
stdout=$testPath/../pbStdout
stderr=$testPath/../pbStderr

lift() {
	echo "$@" | sed -e 's/ /%20/g' >$cmd
	r=$(timeout 30 cat $cmd)
	sleep 1
	cat $stdout
	cat $stderr >&2
	return $(cat $retval)
}

# print green text
printGreen() {
	printf "\033[38;5;10m$@\033[0m\n"
}

# print red text
printRed() {
	printf "\033[38;5;1m$@\033[0m\n"
}
