#! /bin/sh

version=$1

cat << EOF
#ifndef __VERSION_H
#define __VERSION_H

#define VERSION "$version"

#endif /* NOT __VERSION_H */
EOF
