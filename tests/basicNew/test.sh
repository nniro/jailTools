#! /bin/sh

# we just test creating a vanilla jail

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/basic

$jtPath new $jail 2>&1 || exit 1

exit 0
