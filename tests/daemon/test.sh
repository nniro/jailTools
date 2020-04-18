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
	if [ ! -e run/jail.pid ]; then
		echo "The daemonized jail is not running, run/jail.pid contains : '$(cat run/jail.pid)'" 2>&1
		exit 1
	fi

	echo "Testing to see if the httpd service is running"
	pstree $(cat run/jail.pid) | grep -q httpd

	if [ "$?" != "0" ]; then
		echo "Failed, the httpd service is not running"
		echo "here is the info on the running process : \"$(pstree $(cat run/jail.pid))\""
		echo "here is the line in rootCustomConfig.sh :"
		grep 'runJail -d \$ownPath' rootCustomConfig.sh
		exit 1
	fi
	echo "success"
}

$jtPath new $testPath/basic >/dev/null || exit 1
cd $testPath/basic

echo "Testing standard daemon with a direct command put in the background"
cp ._rootCustomConfig.sh.initial rootCustomConfig.sh
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh
sed -e 's/^\([[:space:]]*runJail -d \$ownPath\).*$/\1 \x2Fusr\x2Fsbin\x2Fhttpd -p 8000/' -i rootCustomConfig.sh
$jtPath daemon 2>&1 || exit 1
sleep 1
doCheck
$jtPath stop
sleep 1

echo "Testing standard daemon with a direct command put in the foreground"
cp ._rootCustomConfig.sh.initial rootCustomConfig.sh
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh
sed -e 's/^\([[:space:]]*runJail -d \$ownPath\).*$/\1 \x2Fusr\x2Fsbin\x2Fhttpd -p 8000 -f/' -i rootCustomConfig.sh
$jtPath daemon 2>&1 || exit 1
sleep 1
doCheck
$jtPath stop
sleep 1

echo "Testing daemon with a shell that calls the command single quoted and is put in the background"
cp ._rootCustomConfig.sh.initial rootCustomConfig.sh
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh
sed -e 's/^\([[:space:]]*runJail -d \$ownPath\).*$/\1 sh -c \x27\x2Fusr\x2Fsbin\x2Fhttpd -p 8000\x27/' -i rootCustomConfig.sh
$jtPath daemon 2>&1 || exit 1
sleep 1
doCheck
$jtPath stop
sleep 1

echo "Testing daemon with a shell that calls the command single quoted and is put in the foreground"
cp ._rootCustomConfig.sh.initial rootCustomConfig.sh
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh
sed -e 's/^\([[:space:]]*runJail -d \$ownPath\).*$/\1 sh -c \x27\x2Fusr\x2Fsbin\x2Fhttpd -p 8000 -f\x27/' -i rootCustomConfig.sh
$jtPath daemon 2>&1 || exit 1
sleep 1
doCheck
$jtPath stop
sleep 1

echo "Testing daemon with a shell that calls the command double quoted and is put in the background"
cp ._rootCustomConfig.sh.initial rootCustomConfig.sh
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh
sed -e 's/^\([[:space:]]*runJail -d \$ownPath\).*$/\1 sh -c \x22\x2Fusr\x2Fsbin\x2Fhttpd -p 8000\x22/' -i rootCustomConfig.sh
$jtPath daemon 2>&1 || exit 1
sleep 1
doCheck
$jtPath stop
sleep 1

echo "Testing daemon with a shell that calls the command double quoted and is put in the foreground"
cp ._rootCustomConfig.sh.initial rootCustomConfig.sh
sed -e 's/jailNet=true/jailNet=false/' -i rootCustomConfig.sh
sed -e 's/^\([[:space:]]*runJail -d \$ownPath\).*$/\1 sh -c \x22\x2Fusr\x2Fsbin\x2Fhttpd -p 8000 -f\x22/' -i rootCustomConfig.sh
$jtPath daemon 2>&1 || exit 1
sleep 1
doCheck
$jtPath stop
sleep 1

exit 0
