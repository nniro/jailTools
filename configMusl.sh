#! /bin/sh

rootDir=$1

cd musl
./configure --prefix=$rootDir/usr
