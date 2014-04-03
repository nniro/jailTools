#! /bin/bash

rootDir=$PWD

cd musl
./configure --prefix=$rootDir/usr
