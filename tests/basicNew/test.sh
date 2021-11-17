#! /bin/sh

# we just test creating a vanilla jail

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/basic

$jtPath new $jail 2>/dev/null || exit 1

# we check that the bind mount to /lib is read-only and executable
result=$($jtPath start $jail mount 2>/dev/null | grep ' \/lib ' | sed -e 's/.*\(([^)]*)\)$/\1/')
if ! echo $result | grep -q '\((ro\|,ro,\|,ro)\)'; then
	echo "We expect /lib to be bind mounted as read-only"
	exit 1
fi

exit 0
