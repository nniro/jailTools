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

doCheck() {
	jail=$1
	echo giving 2 seconds maximum timeout for the jail to start the daemon
	timeout 2 sh -c 'while :; do if [ -e run/jail.pid ]; then break; fi ; done'
	echo 2 seconds timeout is done
	if [ ! -e $jail/run/jail.pid ]; then
		echo "The daemonized jail is not running, run/jail.pid contains : '$(cat $jail/run/jail.pid)'" 2>&1
		exit 1
	fi
	echo "the jail is running"

	echo "Testing to see if the httpd service is running"
	pstree $(cat $jail/run/jail.pid) | grep -q httpd
	err=$?

	if [ "$err" != "0" ]; then
		echo "Failed, the httpd service is not running"
		echo "here is the info on the running process : \"$(pstree $(cat $jail/run/jail.pid))\""
		echo "Jail processes : $($jtPath status $jail -p)"
		echo "here is the line in rootCustomConfig.sh :"
		grep '^daemonCommand=' $jail/rootCustomConfig.sh
		echo "jail pid : $(cat $jail/run/jail.pid) - ns pid : $(cat $jail/run/ns.pid)"
		echo "stopping the jail"
		$jtPath stop $jail 2>&1
		exit 1
	fi
	echo "success"
}

$jtPath new $jail >/dev/null 2>&1 || exit 1

echo "Starting a daemonized httpd server from the command line"
$jtPath config $jail -s jailNet true
$jtPath config $jail -s disableUnprivilegedNetworkNamespace false
timeout 5 $jtPath daemon $jail /usr/sbin/httpd -p 8000 2>&1 || exit 1
doCheck $jail
$jtPath stop $jail 2>&1
resetConfig $jail

echo "Starting an httpd server under a shell from the command line"
$jtPath config $jail -s jailNet true
$jtPath config $jail -s disableUnprivilegedNetworkNamespace false
timeout 5 $jtPath daemon $jail sh -c '/usr/sbin/httpd -p 8000' 2>&1 || exit 1
doCheck $jail
$jtPath stop $jail 2>&1
resetConfig $jail

echo "Testing standard daemon with a direct command put in the background"
$jtPath config $jail -s jailNet true
$jtPath config $jail -s disableUnprivilegedNetworkNamespace false
$jtPath config $jail -s daemonCommand "/usr/sbin/httpd -p 8000"
timeout 5 $jtPath daemon $jail 2>&1 || exit 1
doCheck $jail
$jtPath stop $jail 2>&1
resetConfig $jail

echo "Testing standard daemon with a direct command put in the foreground"
$jtPath config $jail -s jailNet true
$jtPath config $jail -s disableUnprivilegedNetworkNamespace false
$jtPath config $jail -s daemonCommand "/usr/sbin/httpd -p 8000 -f"
timeout 5 $jtPath daemon $jail 2>&1 || exit 1
doCheck $jail
$jtPath stop $jail 2>&1
resetConfig $jail

echo "Testing daemon with a shell that calls the command single quoted and is put in the background"
$jtPath config $jail -s jailNet true
$jtPath config $jail -s disableUnprivilegedNetworkNamespace false
$jtPath config $jail -s daemonCommand "sh -c '/usr/sbin/httpd -p 8000'"
timeout 5 $jtPath daemon $jail 2>&1 || exit 1
doCheck $jail
$jtPath stop $jail 2>&1
resetConfig $jail

echo "Testing daemon with a shell that calls the command single quoted and is put in the foreground"
$jtPath config $jail -s jailNet true
$jtPath config $jail -s disableUnprivilegedNetworkNamespace false
$jtPath config $jail -s daemonCommand "sh -c '/usr/sbin/httpd -p 8000 -f'"
timeout 5 $jtPath daemon $jail 2>&1 || exit 1
doCheck $jail
$jtPath stop $jail 2>&1
resetConfig $jail

echo "Testing daemon with a shell that calls the command double quoted and is put in the background"
$jtPath config $jail -s jailNet true
$jtPath config $jail -s disableUnprivilegedNetworkNamespace false
$jtPath config $jail -s daemonCommand 'sh -c "/usr/sbin/httpd -p 8000"'
cat $jail/rootCustomConfig.sh | grep daemonCommand
timeout 5 $jtPath daemon $jail 2>&1 || exit 1
doCheck $jail
$jtPath stop $jail 2>&1
resetConfig $jail

echo "Testing daemon with a shell that calls the command double quoted and is put in the foreground"
$jtPath config $jail -s jailNet true
$jtPath config $jail -s disableUnprivilegedNetworkNamespace false
$jtPath config $jail -s daemonCommand 'sh -c "/usr/sbin/httpd -p 8000 -f"'
timeout 5 $jtPath daemon $jail 2>&1 || exit 1
doCheck $jail
$jtPath stop $jail 2>&1
resetConfig $jail

echo "Testing daemon with a shell that calls multiple instructions"
$jtPath config $jail -s jailNet true
$jtPath config $jail -s disableUnprivilegedNetworkNamespace false
$jtPath config $jail -s daemonCommand 'sh -c "cd /usr/sbin/; ./httpd -p 8000 -f"'
timeout 5 $jtPath daemon $jail 2>&1 || exit 1
doCheck $jail
$jtPath stop $jail 2>&1
resetConfig $jail


exit 0
