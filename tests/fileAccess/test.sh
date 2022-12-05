#! /bin/sh

# Tests if it is possible to create file and directories in directories and expect
# to be able to do so only in two directories : /home and /var

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/fileAccess

$jtPath new $jail >/dev/null 2>/dev/null || exit 1

createAndTestTouchFile() {
	path=$1
	file=$2
	expectedResult=$3

	if $jtPath start $jail sh -c "touch $path/$file; [ -e $path/$file ]" >/dev/null 2>/dev/null; then
		if [ "$expectedResult" = "0" ]; then
			echo "We should not be able to create a file in $path"
			return 1
		fi
	else
		if [ "$expectedResult" = "1" ]; then
			echo "We should be able to create a file in $path"
			return 1
		fi
	fi
	return 0
}

createAndTestCreateDir() {
	path=$1
	dir=$2
	expectedResult=$3

	if $jtPath start $jail sh -c "mkdir $path/$dir; [ -d $path/$dir ]" >/dev/null 2>/dev/null; then
		if [ "$expectedResult" = "0" ]; then
			echo "We should not be able to create a directory in $path"
			return 1
		fi
	else
		if [ "$expectedResult" = "1" ]; then
			echo "We should be able to create a directory in $path"
			return 1
		fi
	fi
	return 0
}

# we expect these to be writable
createAndTestCreateDir '/home' 'blehDir' 1 || exit 1
createAndTestTouchFile '/home' 'bleh' 1 || exit 1

createAndTestCreateDir '/var' 'blehDir' 1 || exit 1
createAndTestTouchFile '/var' 'bleh' 1 || exit 1

createAndTestCreateDir '/tmp' 'blehDir' 1 || exit 1
createAndTestTouchFile '/tmp' 'bleh' 1 || exit 1

# we expect these not to be writable
createAndTestCreateDir '/dev' 'blehDir' 0 || exit 1
createAndTestTouchFile '/dev' 'bleh' 0 || exit 1

createAndTestCreateDir '/etc' 'blehDir' 0 || exit 1
createAndTestTouchFile '/etc' 'bleh' 0 || exit 1

createAndTestCreateDir '/mnt' 'blehDir' 0 || exit 1
createAndTestTouchFile '/mnt' 'bleh' 0 || exit 1

createAndTestCreateDir '/usr' 'blehDir' 0 || exit 1
createAndTestTouchFile '/usr' 'bleh' 0 || exit 1

createAndTestCreateDir '/usr/lib' 'blehDir' 0 || exit 1
createAndTestTouchFile '/usr/lib' 'bleh' 0 || exit 1

createAndTestCreateDir '/usr/bin' 'blehDir' 0 || exit 1
createAndTestTouchFile '/usr/bin' 'bleh' 0 || exit 1

createAndTestCreateDir '/usr/sbin' 'blehDir' 0 || exit 1
createAndTestTouchFile '/usr/sbin' 'bleh' 0 || exit 1

createAndTestCreateDir '/usr/share' 'blehDir' 0 || exit 1
createAndTestTouchFile '/usr/share' 'bleh' 0 || exit 1

createAndTestCreateDir '/usr/local' 'blehDir' 0 || exit 1
createAndTestTouchFile '/usr/local' 'bleh' 0 || exit 1

createAndTestCreateDir '/root' 'blehDir' 0 || exit 1
createAndTestTouchFile '/root' 'bleh' 0 || exit 1

createAndTestCreateDir '/bin' 'blehDir' 0 || exit 1
createAndTestTouchFile '/bin' 'bleh' 0 || exit 1

createAndTestCreateDir '/lib' 'blehDir' 0 || exit 1
createAndTestTouchFile '/lib' 'bleh' 0 || exit 1

createAndTestCreateDir '/sbin' 'blehDir' 0 || exit 1
createAndTestTouchFile '/sbin' 'bleh' 0 || exit 1

createAndTestCreateDir '/opt' 'blehDir' 0 || exit 1
createAndTestTouchFile '/opt' 'bleh' 0 || exit 1

exit 0
