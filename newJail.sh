#! /bin/sh

filesystem="
/bin
/boot
/dev
/dev/pts
/etc
/etc/pam.d
/lib
/lib/tls
/lib/security
/home
/mnt
/opt
/proc
/sbin
/sys
/root
/tmp
/run
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
/var/pid
/var/run
/var/spool
/var/state
/var/tmp
/var/yp
"

case "$(readlink -f /proc/$$/exe)" in
	*dash)
		echo "We don't support dash"
		exit 1
	;;

	*)
		sh="$(readlink -f /proc/$$/exe)"
		echo "using shell : $sh"
	;;
esac

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

ownPath=$(dirname $0)

newChrootHolder=$1
newChrootDir=$newChrootHolder/root
echo "Instantiating directory : " $newChrootDir

mkdir $newChrootHolder
mkdir $newChrootHolder/run
mkdir $newChrootDir

touch $newChrootHolder/startRoot.sh # this is to make cpDep detect the new style jail

for path in $filesystem ; do
	mkdir $newChrootDir/$path
	chmod 704 $newChrootDir/$path
	#chown 0 ${1}/$path
	#chgrp 0 ${1}/$path
done

echo "Linking /lib to /lib64"
ln -s /lib $newChrootDir/lib64

echo "Adding /bin/false to the jail"
$sh $ownPath/cpDep.sh $newChrootHolder /bin/ /bin/false

echo "Populating the /etc configuration files"
# localtime
$sh $ownPath/cpDep.sh $newChrootHolder /etc/ /etc/localtime
# group
cat >> $newChrootDir/etc/group << EOF
root:x:0:
$2:x:100:
EOF
# passwd
cat >> $newChrootDir/etc/passwd << EOF
root:x:0:0::/root:/bin/false
$2:x:$UID:100::/home:/bin/false
EOF
# shadow
cat >> $newChrootDir/etc/shadow << EOF
root:$($ownPath/cryptPass $($sh $ownPath/gene.sh -f 200) $($sh $ownPath/gene.sh -f 50)):0:0:99999:7:::
$2:!:0:0:99999:7:::
EOF

# shells
cat >> $newChrootDir/etc/shells << EOF
$sh
/bin/false
EOF

cat > $newChrootHolder/startRoot.sh << EOF
#! $sh

if [ \$UID != 0 ]; then
	echo "This script has to be run with root permissions as it calls the command chroot"
	exit 1
fi

# dev mount points : read-write, no-exec
read -d '' devMountPoints << EOF
@EOF

# read-only mount points with exec
read -d '' roMountPoints << EOF
/usr/share/locale
/usr/lib/locale
/usr/lib/gconv
@EOF

# read-write mount points with exec
read -d '' rwMountPoints << EOF
@EOF

function mountMany() {
	rootDir=\$1
	mountOps=\$2
	shift 2

	for mount in \$@; do
		if [ ! -d \$rootDir/\$mount ]; then
			echo \$rootDir/\$mount does not exist, creating it
			mkdir -p \$rootDir/\$mount
		fi
		mountpoint \$rootDir/\$mount > /dev/null || mount \$mountOps --bind \$mount \$rootDir/\$mount
	done
}

function startChroot() {
	mount --bind root root
	#for mount in \$mountPoints; do
	#	# we create the directories for you
	#	if [ ! -d root/\$mount ]; then
	#		mkdir -p root/\$mount
	#	fi

	#	chmod 755 root/\$mount
	#	mountpoint root/\$mount > /dev/null || mount -o defaults --bind \$mount root/\$mount
	#done

	# dev
	mountMany root "-o rw,noexec" \$devMountPoints
	mountMany root "-o ro,exec" \$roMountPoints
	mountMany root "-o defaults" \$rwMountPoints

	# put your chroot starting scripts/instructions here
	# here's an example
	env - PATH=/usr/bin:/bin USER=$2 UID=1000 HOSTNAME=nowhere.here unshare -mpf $sh -c 'mount -tproc none root/proc; chroot --userspec=1000:100 root /bin/sh'
	# if you need to add logs, just pipe them to the directory : root/run/someLog.log

	stopChroot
	umount root
}

function stopChroot() {
	for mount in \$devMountPoints \$roMountPoints \$rwMountPoints; do
		mountpoint root/\$mount > /dev/null && umount root/\$mount
	done
}

case \$1 in

	start)
		startChroot
	;;

	stop)
		stopChroot
	;;

	restart)
		stopChroot
		startChroot
	;;

	*)
		echo "\$0 : start|stop|restart"
	;;
esac

EOF

# we fix the EOF inside the script
sed -e "s/^\@EOF$/EOF/g" -i $newChrootHolder/startRoot.sh

echo "Copying pam security libraries"
#sh cpDep.sh $newChrootHolder /lib/security /lib/security/*

#echo "Copying minimal locale and gconv data"
mkdir $newChrootDir/usr/lib/locale
#sh cpDep.sh $newChrootHolder /usr/lib/locale/en_US /usr/lib/locale/en_US
mkdir $newChrootDir/usr/lib/gconv
#sh cpDep.sh $newChrootHolder /usr/lib/gconv /usr/lib/gconv

echo "Copying terminfo data"
mkdir $newChrootDir/usr/share/{terminfo,misc}
sh cpDep.sh $newChrootHolder /usr/share/ /usr/share/{terminfo,misc}
$sh $ownPath/cpDep.sh $newChrootHolder /etc/ /etc/{termcap,services,protocols,nsswitch.conf,ld.so.cache,inputrc,hostname,resolv.conf,host.conf,hosts}

echo "Copying the nss libraries"
$sh $ownPath/cpDep.sh $newChrootHolder /usr/lib/ /lib/libnss*

# if you want the standard binaries for using sh scripts
$sh $ownPath/cpDep.sh $newChrootHolder /bin/ /bin/{sh,ls,mkdir,cat,chgrp,chmod,chown,cp,grep,ln,kill,rm,rmdir,sed,sh,sleep,touch,basename,dirname,uname,mktemp,cmp,md5sum,realpath,mv,id,readlink,env,tr,[,fold,which,date,stat} $sh

echo "Now creating $newChrootDir/dev/null, $newChrootDir/dev/random and $newChrootDir/dev/urandom"
echo "This requires root, so we use sudo"

# this is the section we need root

sudo chown root $newChrootDir/etc/shadow
sudo chmod 600 $newChrootDir/etc/shadow
sudo chown root $newChrootDir/etc/group
sudo chmod 644 $newChrootDir/etc/group

# create quasi essential special nodes in /dev
sudo mknod $newChrootDir/dev/null c 1 3
sudo chmod 666 $newChrootDir/dev/null
sudo mknod $newChrootDir/dev/random c 1 8
sudo chmod 444 $newChrootDir/dev/random
sudo mknod $newChrootDir/dev/urandom c 1 9
sudo chmod 444 $newChrootDir/dev/urandom
sudo mknod $newChrootDir/dev/zero c 1 5
sudo chmod 444 $newChrootDir/dev/zero

# we append these to update.sh
echo "# end basic dependencies" >> $newChrootHolder/update.sh
echo "" >> $newChrootHolder/update.sh

echo "All done"
exit 0

