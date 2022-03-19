#! /bin/sh

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/netAccessSU

bb=$testPath/../bin/busybox

. $testPath/../../utils/utils.sh

$jtPath new $jail >/dev/null 2>/dev/null || exit 1

# TODO we need a means to set a unique IP address to this test
# or at least check that the IP 172.31.254.x is not being used
$jtPath config $jail --set extIp "172.31.254.1" >/dev/null || exit 1

$jtPath config $jail --set setNetAccess "true" >/dev/null || exit 1

echo 'printf "GET / HTTP/1.1\r\nHost: 1.1.1.1\r\n\r\n" | timeout 2 ssl_client 1.1.1.1 | grep -q ".*"' > $jail/root/home/test1.sh

if ! lift $jtPath start $jail sh /home/test1.sh 2>/dev/null; then
	echo "Could not connect to the remote site 1.1.1.1"
	exit 1
fi

$jtPath config $jail --set setNetAccess "false" >/dev/null || exit 1

echo 'printf "GET / HTTP/1.1\r\nHost: 1.1.1.1\r\n\r\n" | timeout 2 ssl_client 1.1.1.1 | grep -q ".*"' > $jail/root/home/test2.sh

if lift $jtPath start $jail sh /home/test2.sh 2>/dev/null; then
	echo "With setNetAccess set to 'false' we should not be able to connect to the remote site 1.1.1.1"
	exit 1
fi

# set 1.1.1.1 as our dns provider
echo "nameserver 1.1.1.1" > $jail/root/etc/resolv.conf

echo 'printf "GET / HTTP/1.1\r\nHost: kernel.org\r\n\r\n" | timeout 2 ssl_client kernel.org | grep -q ".*"' > $jail/root/home/test3.sh

if lift $jtPath start $jail sh /home/test3.sh 2>/dev/null; then
	echo "With setNetAccess set to 'false' we should not be able to connect to the remote site kernel.org"
	exit 1
fi

$jtPath config $jail --set setNetAccess "true" >/dev/null || exit 1

echo 'printf "GET / HTTP/1.1\r\nHost: kernel.org\r\n\r\n" | timeout 2 ssl_client kernel.org | grep -q ".*"' > $jail/root/home/test4.sh

if ! lift $jtPath start $jail sh /home/test4.sh 2>/dev/null; then
	echo "Could not connect to the remote site linux.org"
	exit 1
fi

# this may be a test not fitting here
# this tests if a reentry shell gets exactly the same network namespace
# as the started jail daemon.

$jtPath config $jail --set setNetAccess "true" >/dev/null || exit 1

lift $jtPath daemon $jail 2>/dev/null || exit 1

hostInterfaces="$($bb ip addr show up | $bb sed -ne '/^[0-9]\+:/ p')"

jailInterfaces="$($jtPath shell $jail sh -c '/sbin/ip addr | sed -ne "/^[0-9]\+:/ p"' 2>/dev/null)"

if [ "$jailInterfaces" = "$hostInterfaces" ] ; then
	echo "the shell reentry should be part of the network namespace but it is not."
	echo "jail interfaces\n '$jailInterfaces' \nand the host interfaces\n '$hostInterfaces'"
	lift $jtPath stop $jail 2>/dev/null
	exit 1
fi

lift $jtPath stop $jail 2>/dev/null

exit 0
