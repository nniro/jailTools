#! /bin/sh

rootDir=$PWD

git submodule init
git submodule update

cd musl
./configure --prefix=$rootDir/usr
