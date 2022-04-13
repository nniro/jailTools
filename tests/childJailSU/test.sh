#! /bin/sh

# we do various tests in a child jail.
# Maybe we could install these tests inside a jail and rerun them
# to see if they all work correctly. (that would be fantastic!)

sh=$1
testPath=$2
jtPath=$3

. $testPath/../../utils/utils.sh

jail=$testPath/childJailSU

$jtPath new $jail >/dev/null 2>/dev/null || exit 1

# some tests to deliberately fail various parts
#rm root/usr/bin/jt
#echo "exit 1" > root/usr/bin/jt
#chmod +x root/usr/bin/jt

cat > $jail/root/home/internalListTest.sh << EOF
#! /bin/sh

cd /home

if ! which jt >/dev/null 2>/dev/null ; then
	echo "Missing the command 'jt'"
	exit 1
fi

if ! jt new child >/dev/null 2>/dev/null ; then
	echo "Could not create child jail"
	exit 1
fi

cd child

if ! jt start sh -c exit 2>/dev/null ; then
	echo "Could not start child jail"
	exit 1
fi

exit 0
EOF

lift $jtPath start $jail sh /home/internalListTest.sh 2>/dev/null || exit 1

exit 0
