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

newChrootHolder=$1
newChrootDir=$newChrootHolder/root
echo "Instantiating directory : " $newChrootDir

mkdir $newChrootHolder
mkdir $newChrootHolder/run
mkdir $newChrootDir

for path in $filesystem ; do
	mkdir $newChrootDir/$path
	chmod 704 $newChrootDir/$path
	#chown 0 ${1}/$path
	#chgrp 0 ${1}/$path
done

echo "Adding /bin/false to the jail"
$sh cpDep.sh $newChrootDir /bin/ /bin/false

echo "Populating the /etc configuration files"
# localtime
$sh cpDep.sh $newChrootDir /etc/ /etc/localtime
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
root:$(./cryptPass $($sh gene.sh -f 200) $($sh gene.sh -f 50)):0:0:99999:7:::
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

# place all the directory mountPoints that you want extra for your chroot directory in this emplacement
read -d '' mountPoints << EOF
/usr/share/locale
/usr/lib/locale
/usr/lib/gconv
/usr/share/terminfo
/usr/share/misc
@EOF

function startChroot() {
	for mount in \$mountPoints; do
		# we create the directories for you
		if [ ! -d root/\$mount ]; then
			mkdir -p root/\$mount
		fi

		chmod 755 root/\$mount
		mountpoint root/\$mount > /dev/null || mount -o defaults --bind \$mount root/\$mount
	done

	# put your chroot starting scripts/instructions here
	# here's an example
	env - PATH=/usr/bin:/bin USER=\$2 UID=1000 HOSTNAME=nowhere.here chroot --userspec=1000:100 root /bin/sh
	# if you need to add logs, just pipe them to the directory : root/run/someLog.log


}

function stopChroot() {
	for mount in \$mountPoints; do
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

#echo "Copying minimal locale and gconv data"
mkdir $newChrootDir/usr/lib/locale
#sh cpDep.sh $newChrootDir /usr/lib/locale/en_US /usr/lib/locale/en_US
mkdir $newChrootDir/usr/lib/gconv
#sh cpDep.sh $newChrootDir /usr/lib/gconv /usr/lib/gconv

echo "Copying terminfo data"
mkdir $newChrootDir/usr/share/{terminfo,misc}
#sh cpDep.sh $newChrootDir /usr/share/ /usr/share/{terminfo,misc}
$sh cpDep.sh $newChrootDir /etc/ /etc/{termcap,services,protocols,nsswitch.conf,ld.so.cache,inputrc,hostname,resolv.conf,host.conf,hosts}

echo "Copying the nss libraries"
$sh cpDep.sh $newChrootDir /usr/lib/ /lib/libnss*

# if you want the standard binaries for using sh scripts
$sh cpDep.sh $newChrootDir /bin/ /bin/{sh,ls,mkdir,cat,chgrp,chmod,chown,cp,grep,ln,kill,rm,rmdir,sed,sh,sleep,touch,basename,dirname,uname,mktemp,cmp,md5sum,realpath,mv,id,readlink,env,tr,[,fold,which,date,stat} $sh

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

echo "All done"
exit 0

