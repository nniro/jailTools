# we create an unprivileged jail and test the daemon feature with the httpd service

# runJail -d $ownPath \x2Fusr\x2Fsbin\x2Fhttpd -p 8000
# runJail -d $ownPath \x2Fusr\x2Fsbin\x2Fhttpd -p 8000 -f
# runJail -d $ownPath sh -c '\x2Fusr\x2Fsbin\x2Fhttpd -p 8000'
# runJail -d $ownPath sh -c '\x2Fusr\x2Fsbin\x2Fhttpd -p 8000 -f'
# runJail -d $ownPath sh -c "\x2Fusr\x2Fsbin\x2Fhttpd -p 8000"
# runJail -d $ownPath sh -c "\x2Fusr\x2Fsbin\x2Fhttpd -p 8000 -f"

# " is \x22
# ' is \x27
# / is \x2F

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/basic

resetConfig() {
	jail=$1

	cp $jail/._rootCustomConfig.sh.initial $jail/rootCustomConfig.sh
}

bb=$testPath/../bin/busybox

doCheck() {
	description=$1
	jail=$2
	# giving 8 seconds maximum timeout for the jail to start the daemon
	timeout 8 sh -c 'while :; do if [ -e run/jail.pid ]; then break; fi ; sleep 0.5 ; done'
	# 8 seconds timeout is done
	if [ ! -e $jail/run/jail.pid ]; then
		echo "The daemonized jail is not running, missing $jail/run/jail.pid"
		return 1
	fi
	#echo "the jail is running"

	#echo "Testing to see if the httpd service is running"
	$bb pstree $(cat $jail/run/jail.pid) | grep -q httpd
	err=$?

	if [ "$err" != "0" ]; then
		echo "Test '$description' Failed, the httpd service is not running"
		echo "here is the info on the running process : \"$($bb pstree $(cat $jail/run/jail.pid))\""
		echo "Jail processes : $($jtPath status $jail -p)"
		echo "here is the line in rootCustomConfig.sh :"
		grep '^daemonCommand=' $jail/rootCustomConfig.sh
		echo "jail pid : $(cat $jail/run/jail.pid) - ns pid : $(cat $jail/run/ns.pid)"
		echo "stopping the jail"
		$jtPath stop $jail 2>&1
		return 1
	fi
	#echo "success"
	return 0
}

$jtPath new $jail >/dev/null 2>/dev/null || exit 1

# directly
$jtPath config $jail -s jailNet true >/dev/null
$jtPath config $jail -s setNetAccess false >/dev/null
if ! $jtPath daemon $jail /usr/sbin/httpd -p 8000 2>&1; then
	echo "Failed to start a daemonized httpd server from the command line"
	exit 1
fi
doCheck "directly" $jail || exit 1
$jtPath stop $jail 2>/dev/null
resetConfig $jail

# with a shell
$jtPath config $jail -s jailNet true >/dev/null
$jtPath config $jail -s setNetAccess false >/dev/null
if ! $jtPath daemon $jail sh -c '/usr/sbin/httpd -p 8000' 2>&1; then
	echo "Failed to start an httpd server under a shell from the command line"
	exit 1
fi
doCheck "with a shell" $jail || exit 1
$jtPath stop $jail 2>/dev/null
resetConfig $jail

# with the daemonCommand config in the background
$jtPath config $jail -s jailNet true >/dev/null
$jtPath config $jail -s setNetAccess false >/dev/null
$jtPath config $jail -s daemonCommand "/usr/sbin/httpd -p 8000" >/dev/null
if ! $jtPath daemon $jail 2>&1; then
	echo "Failed to start a daemon in the daemonCommand config put in the background"
	exit 1
fi
doCheck "with the daemonCommand config in the background" $jail || exit 1
$jtPath stop $jail 2>/dev/null
resetConfig $jail

# with the daemonCommand config in the foreground
$jtPath config $jail -s jailNet true >/dev/null
$jtPath config $jail -s setNetAccess false >/dev/null
$jtPath config $jail -s daemonCommand "/usr/sbin/httpd -p 8000 -f" >/dev/null
if ! $jtPath daemon $jail 2>&1; then
	echo "Failed to start a daemon in the daemonCommand config put in the foreground"
	exit 1
fi
doCheck "with the daemonCommand config in the foreground" $jail || exit 1
$jtPath stop $jail 2>/dev/null
resetConfig $jail

# with the daemonCommand config single quoted as a shell in the background
$jtPath config $jail -s jailNet true >/dev/null
$jtPath config $jail -s setNetAccess false >/dev/null
$jtPath config $jail -s daemonCommand "sh -c '/usr/sbin/httpd -p 8000'" >/dev/null
if ! $jtPath daemon $jail 2>&1; then
	echo "Failed to start a daemon with a shell that calls the command single quoted and is put in the background"
	exit 1
fi
doCheck "with the daemonCommand config single quoted as a shell in the background" $jail || exit 1
$jtPath stop $jail 2>/dev/null
resetConfig $jail

# with the daemonCommand config single quoted as a shell in the foreground
$jtPath config $jail -s jailNet true >/dev/null
$jtPath config $jail -s setNetAccess false >/dev/null
$jtPath config $jail -s daemonCommand "sh -c '/usr/sbin/httpd -p 8000 -f'" >/dev/null
if ! $jtPath daemon $jail 2>&1; then
	echo "Failed to start a daemon with a shell that calls the command single quoted and is put in the foreground"
	exit 1
fi
doCheck "with the daemonCommand config single quoted as a shell in the foreground" $jail || exit 1
$jtPath stop $jail 2>/dev/null
resetConfig $jail

# with the daemonCommand config double quoted as a shell in the foreground
$jtPath config $jail -s jailNet true >/dev/null
$jtPath config $jail -s setNetAccess false >/dev/null
$jtPath config $jail -s daemonCommand 'sh -c "/usr/sbin/httpd -p 8000"' >/dev/null
if ! $jtPath daemon $jail 2>&1; then
	echo "Failed to start a daemon with a shell that calls the command double quoted and is put in the background"
	exit 1
fi
doCheck "with the daemonCommand config double quoted as a shell in the foreground" $jail || exit 1
$jtPath stop $jail 2>/dev/null
resetConfig $jail

# with the daemonCommand config double quoted as a shell in the foreground
$jtPath config $jail -s jailNet true >/dev/null
$jtPath config $jail -s setNetAccess false >/dev/null
$jtPath config $jail -s daemonCommand 'sh -c "/usr/sbin/httpd -p 8000 -f"' >/dev/null
if ! $jtPath daemon $jail 2>&1; then
	echo "Failed to start a daemon with a shell that calls the command double quoted and is put in the foreground"
	exit 1
fi
doCheck "with the daemonCommand config double quoted as a shell in the foreground" $jail || exit 1
$jtPath stop $jail 2>/dev/null
resetConfig $jail

# with the daemonCommand config with multiple instructions
$jtPath config $jail -s jailNet true >/dev/null
$jtPath config $jail -s setNetAccess false >/dev/null
$jtPath config $jail -s daemonCommand 'sh -c "cd /usr/sbin/; ./httpd -p 8000 -f"' >/dev/null
if ! $jtPath daemon $jail 2>&1; then
	echo "Failed to start a daemon with a shell that calls multiple instructions"
	exit 1
fi
doCheck "with the daemonCommand config with multiple instructions" $jail || exit 1
$jtPath stop $jail 2>/dev/null
resetConfig $jail

exit 0
