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
