#! /bin/sh

sh=$1
testPath=$2
jtPath=$3

jail1=$testPath/bridgePrimus
jail2=$testPath/bridgeSecondus
bogus=$testPath/bogus

bb=$testPath/../bin/busybox

. $testPath/../../utils/utils.sh

$jtPath new $jail1 >/dev/null 2>/dev/null || exit 1

$jtPath new $jail2 >/dev/null 2>/dev/null || exit 1

$jtPath new $bogus >/dev/null 2>/dev/null || exit 1

$jtPath config $jail1 -s setNetAccess false >/dev/null
$jtPath config $jail2 -s setNetAccess false >/dev/null
$jtPath config $bogus -s setNetAccess false >/dev/null

$jtPath config $jail1 -s networking false >/dev/null
$jtPath config $jail2 -s networking false >/dev/null
$jtPath config $bogus -s networking false >/dev/null

# we setup the jail1
$jtPath config $jail1 -s createBridge true >/dev/null
$jtPath config $jail1 -s bridgeIp "192.168.99.1" >/dev/null

cat - > $jail1/root/home/index.html << EOF
This test has passed
EOF

# inside jail1 this sets up the service
cat - > $jail1/root/home/startHttpd.sh << EOF
#! /bin/sh

cd /home
/usr/sbin/httpd -f -p 192.168.99.1:8000
EOF

# starting a jail with a bridge unprivileged should work
$jtPath daemon $jail1 sh /home/startHttpd.sh 2>/dev/null
err=$?

[ "$err" = "0" ] && $jtPath shell $jail1 /sbin/ip addr 2>/dev/null | grep -q 'bridgePrimus:' 2>/dev/null || err=1

if [ "$err" != "0" ]; then
	echo "Unprivileged jail is supposed to be able to start a bridge - $err"
	$jtPath stop $jail1 2>/dev/null
	exit 1
fi
$jtPath stop $jail1 2>/dev/null

lift $jtPath daemon $jail1 sh /home/startHttpd.sh 2>/dev/null || exit 1

# we first try without setting the joinBridgeByJail and expect a failure
lift $jtPath daemon $jail2 2>/dev/null || exit 1

if $jtPath shell $jail2 timeout 2 wget 192.168.99.1:8000 -q -O - 2>/dev/null | grep -q '^This test has passed$'>&2; then
	echo "jail2 is _not_ supposed to be able to be able to connect to jail1's service, but it did."
	exit 1
fi

lift $jtPath stop $jail2 2>/dev/null || exit 1

# we use bogus to attempt to join a non existing jail
sed -e "s@# joinBridgeByJail .*@joinBridgeByJail ${bogus}NonExisting \"false\" \"3\" || exit 1@" -i $bogus/rootCustomConfig.sh

if $jtPath daemon $bogus 2>/dev/null; then
	echo "Attempting to join a non existing jail should fail"
	$jtPath stop $bogus 2>/dev/null
	exit 1
fi

$jtPath stop $bogus 2>/dev/null

# we setup the jail2

sed -e "s@# joinBridgeByJail .*@joinBridgeByJail $jail1 \"false\" \"3\" || exit 1@" -i $jail2/rootCustomConfig.sh

# starting an unprivileged jail to join a bridge should not work
if $jtPath daemon $jail2 2>/dev/null; then
	echo "Attempting to join a bridge with an unprivileged jail is not supposed to work"
	$jtPath stop $jail2 2>/dev/null
	exit 1
fi

err=0
lift $jtPath daemon $jail2 || err=1

[ "$err" = "0" ] && $jtPath shell $jail2 timeout 2 wget 192.168.99.1:8000 -q -O - 2>/dev/null | grep -q '^This test has passed$' || err=1

if [ "$err" != "0" ]; then
	echo "jail2 is supposed to be able to be able to connect to jail1's service"
	lift $jtPath stop $jail1 2>/dev/null
	lift $jtPath stop $jail2 2>/dev/null
	exit 1
fi

lift $jtPath stop $jail2 2>/dev/null || exit 1

lift $jtPath stop $jail1 2>/dev/null || exit 1

exit 0
