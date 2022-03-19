#! /bin/sh

cmd=$testPath/../fifo
retval=$testPath/../pbRetval
stdout=$testPath/../pbStdout
stderr=$testPath/../pbStderr

# send commands to the powerbox.
# only jt commands are accepted. (for now)
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

# use this to implement tests within tests.
subTest() {
	testDescription=$1
	shift

	printf "\t$testDescription : " >&2

	if $@; then
		printGreen "passed" >&2
		return 0
	else
		printRed "failed" >&2
		return 1
	fi
}

# for subtests, this is for the starting test
subTestStart() {
	printf "\n" >&2
	subTest $@
}

# for subtests, this is for the ending test
subTestEnd() {
	subTest $@
	printf "\tAll subtests : " >&2
}
