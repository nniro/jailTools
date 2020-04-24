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

doCheck() {
	echo giving 5 seconds maximum timeout for the jail to start the daemon
	timeout 5 sh -c 'while :; do if [ -e run/jail.pid ]; then break; fi ; done'
	echo 5 seconds timeout is done
	if [ ! -e run/jail.pid ]; then
		echo "The daemonized jail is not running, run/jail.pid contains : '$(cat run/jail.pid)'" 2>&1
		exit 1
	fi
	echo "the jail is running"

	echo "Testing to see if the httpd service is running"
	sleep 1
	pstree $(cat run/jail.pid) | grep -q httpd
	err=$?

	if [ "$err" != "0" ]; then
		echo "Failed, the httpd service is not running"
		echo "here is the info on the running process : \"$(pstree $(cat run/jail.pid))\""
		echo "here is the line in rootCustomConfig.sh :"
		grep '^daemonCommand=' rootCustomConfig.sh
		echo "jail pid : $(cat run/jail.pid) - ns pid : $(cat run/ns.pid)"
		echo "stopping the jail"
		$jtPath stop 2>&1
		exit 1
	fi
	echo "success"
}

$jtPath new $testPath/basic 2>&1 || exit 1
cd $testPath/basic

echo "Testing standard daemon with a direct command put in the background"
cp ._rootCustomConfig.sh.initial rootCustomConfig.sh
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh
sed -e 's/^\(daemonCommand=\)""$/\1"\x2Fusr\x2Fsbin\x2Fhttpd -p 8000"/' -i rootCustomConfig.sh
$jtPath daemon 2>&1 || exit 1
doCheck
$jtPath stop 2>&1
sleep 1

echo "Testing standard daemon with a direct command put in the foreground"
cp ._rootCustomConfig.sh.initial rootCustomConfig.sh
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh
sed -e 's/^\(daemonCommand=\)""$/\1"\x2Fusr\x2Fsbin\x2Fhttpd -p 8000 -f"/' -i rootCustomConfig.sh
$jtPath daemon 2>&1 || exit 1
doCheck
$jtPath stop 2>&1
sleep 1

echo "Testing daemon with a shell that calls the command single quoted and is put in the background"
cp ._rootCustomConfig.sh.initial rootCustomConfig.sh
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh
sed -e 's/^\(daemonCommand=\)""$/\1"sh -c \x27\x2Fusr\x2Fsbin\x2Fhttpd -p 8000\x27"/' -i rootCustomConfig.sh
$jtPath daemon 2>&1 || exit 1
doCheck
$jtPath stop 2>&1
sleep 1

echo "Testing daemon with a shell that calls the command single quoted and is put in the foreground"
cp ._rootCustomConfig.sh.initial rootCustomConfig.sh
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh
sed -e 's/^\(daemonCommand=\)""$/\1"sh -c \x27\x2Fusr\x2Fsbin\x2Fhttpd -p 8000 -f\x27"/' -i rootCustomConfig.sh
$jtPath daemon 2>&1 || exit 1
doCheck
$jtPath stop 2>&1
sleep 1

echo "Testing daemon with a shell that calls the command double quoted and is put in the background"
cp ._rootCustomConfig.sh.initial rootCustomConfig.sh
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh
sed -e 's/^\(daemonCommand=\)""$/\1"sh -c \\\x22\x2Fusr\x2Fsbin\x2Fhttpd -p 8000\\\x22"/' -i rootCustomConfig.sh
$jtPath daemon 2>&1 || exit 1
doCheck
$jtPath stop 2>&1
sleep 1

echo "Testing daemon with a shell that calls the command double quoted and is put in the foreground"
cp ._rootCustomConfig.sh.initial rootCustomConfig.sh
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh
sed -e 's/^\(daemonCommand=\)""$/\1"sh -c \\\x22\x2Fusr\x2Fsbin\x2Fhttpd -p 8000 -f\\\x22"/' -i rootCustomConfig.sh
$jtPath daemon 2>&1 || exit 1
doCheck
$jtPath stop 2>&1
sleep 1

exit 0
