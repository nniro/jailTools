#! /bin/bash

file=$1

example="`cat << EOF 
	\tlinux-gate.so.1 (0xb77a2000)\n
	\tlibc.so.6 => /lib/libc.so.6 (0xb75c9000)\n
	\t/lib/ld-linux.so.2 (0xb77a3000)
EOF`"

if [ "$file" == "" ]; then
cat << EOF
	Please input an executable file or shared object.
EOF
	exit 1
fi

if [ ! -e $file ]; then
cat << EOF
	Error, no such file or directory: $file
EOF
	exit 1
fi

rawOutput=`ldd $file 2> /dev/null`
#rawOutput=`echo -e $example`

# handle statically linked files
if [ "`echo -e $rawOutput | sed -e "s/.*\(statically\|not a dynamic\).*/static/; {t toDelAll} " -e ":toDelAll {p; b delAll}; :delAll {d; b delAll}"`" == "static" ]; then
	# we exit returning nothing for statically linked files
	exit 0
fi

#filterOne=`echo -e $rawOutput | sed -n -e "s/^\(\|[ \t]*\)\(.*\)/\2/" -e "$ {H; x; s/\n/\?/g; p; q}" -e "H"`

#echo -e $filterOne

echo -e "$rawOutput" | sed -e "s/^\(\|[ \t]*\)\([^ ]*\) (.*)$/\2/" -e "s/[^ ]* \=> \([^ ]*\) (.*)$/\1/" | sed -e "/.*linux-gate.*/ d"
