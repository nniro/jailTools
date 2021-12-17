#! /bin/sh

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/netAccess

$jtPath new $jail >/dev/null 2>/dev/null || exit 1

if ! $jtPath start $jail sh -c 'printf "GET / HTTP/1.1\r\nHost: 1.1.1.1\r\n\r\n" | timeout 2 ssl_client 1.1.1.1 | grep -q ".*"' 2>/dev/null; then
	echo "Could not connect to the remote site 1.1.1.1"
	exit 1
fi

$jtPath config $jail --set setNetAccess "false" >/dev/null || exit 1

if $jtPath start $jail sh -c 'printf "GET / HTTP/1.1\r\nHost: 1.1.1.1\r\n\r\n" | timeout 2 ssl_client 1.1.1.1 | grep -q ".*"' 2>/dev/null; then
	echo "With setNetAccess set to 'false' we should not be able to connect to the remote site 1.1.1.1"
	exit 1
fi

# set 1.1.1.1 as our dns provider
echo "nameserver 1.1.1.1" > $jail/root/etc/resolv.conf

if $jtPath start $jail sh -c 'printf "GET / HTTP/1.1\r\nHost: kernel.org\r\n\r\n" | timeout 2 ssl_client kernel.org | grep -q ".*"' 2>/dev/null; then
	echo "With setNetAccess set to 'false' we should not be able to connect to the remote site linux.org"
	exit 1
fi

$jtPath config $jail --set setNetAccess "true" >/dev/null || exit 1

if ! $jtPath start $jail sh -c 'printf "GET / HTTP/1.1\r\nHost: kernel.org\r\n\r\n" | timeout 2 ssl_client kernel.org | grep -q ".*"' 2>/dev/null; then
	echo "Could not connect to the remote site linux.org"
	exit 1
fi

exit 0
