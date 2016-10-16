#! /bin/sh

rootDir=$PWD

cd musl
./configure --prefix=$rootDir/usr
