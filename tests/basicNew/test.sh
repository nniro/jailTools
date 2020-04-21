#! /bin/sh

# we just test creating a vanilla jail

sh=$1
testPath=$2
jtPath=$3

$jtPath new $testPath/basic 2>&1 || exit 1

exit 0
