#! /bin/sh

filesystem="
/bin
/boot
/dev
/dev/pts
/etc
/lib
/lib/tls
/home
/mnt
/opt
/sbin
/sys
/root
/tmp
/usr
/usr/bin
/usr/sbin
/usr/lib
/usr/lib/tls
/usr/libexec
/usr/local
/usr/local/bin
/usr/local/lib
/usr/local/lib/tls
/usr/local/sbin
/var
/var/account
/var/cache
/var/empty
/var/games
/var/lock
/var/log
/var/mail
/var/opt
/var/run
/var/spool
/var/state
/var/tmp
/var/yp
"
if [ "$1" = "" ]; then
	echo "please input the name of the new directory to instantiate"
	exit 1
fi

if [ "$2" = "" ]; then
	echo "please also input a service name (for the creation of a username and group)"
	exit 1
fi

if [ -e $1 ]; then
	echo "invalid path given, file or directory already exists"
	exit 1
fi

echo "Instantiating directory : " $1

mkdir $1

for path in $filesystem ; do
	mkdir ${1}/$path
	chmod 704 ${1}/$path
	#chown 0 ${1}/$path
	#chgrp 0 ${1}/$path
done

echo "Adding /bin/false to the jail"
sh cpDep.sh $1 /bin/ /bin/false

echo "Populating the /etc configuration files"
# localtime
sh cpDep.sh $1 /etc/ /etc/localtime
# group
cat >> $1/etc/group << EOF
root:x:0:
$2:x:100:
EOF
# passwd
cat >> $1/etc/passwd << EOF
root:x:0:0::/root:/bin/false
$2:x:$UID:100::/home:/bin/false
EOF
# shadow
cat >> $1/etc/shadow << EOF
root:$(./cryptPass `sh gene.sh -f 512` `sh gene.sh -f 50`):0:0:99999:7:::
$2:!:0:0:99999:7:::
EOF
# shells
cat >> $1/etc/shells << EOF
/bin/sh
/bin/false
EOF

echo "Copying minimal locale and gconv data"
sh cpDep.sh $1 /usr/lib/locale/en_US /usr/lib/locale/en_US
sh cpDep.sh $1 /usr/lib/gconv /usr/lib/gconv

echo "Copying terminfo data"
sh cpDep.sh $1 /usr/share/ /usr/share/{terminfo,misc}
sh cpDep.sh $1 /etc/ /etc/{termcap,services,protocols,nsswitch.conf,ld.so.cache,inputrc,hostname,resolv.conf,host.conf,hosts}

echo "Copying the nss libraries"
sh cpDep.sh $1 /lib/ /lib/libnss*

# if you want the standard binaries for using sh scripts
#sh cpDep.sh $1 /bin/ /bin/{sh,ls,mkdir,cat,chgrp,chmod,chown,cp,grep,ln,kill,rm,rmdir,sed,sh,sleep,touch}

echo "Now creating $1/dev/null, $1/dev/random and $1/dev/urandom"
echo "This requires root, so we use sudo"
# create quasi essential special nodes in /dev
sudo mknod ${1}/dev/null c 1 3
sudo chmod 666 ${1}/dev/null
sudo mknod ${1}/dev/random c 1 8
sudo mknod ${1}/dev/urandom c 1 9

echo "All done"
exit 0

