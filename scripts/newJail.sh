#! /bin/sh

case "$(readlink -f /proc/$$/exe)" in
	*zsh)
		setopt shwordsplit
		sh="$(readlink -f /proc/$$/exe)"
		echo "using shell : $sh"
	;;

	*busybox)
		sh="$(readlink -f /proc/$$/exe) sh"
		echo "using shell : $sh"
	;;

	*)
		sh="$(readlink -f /proc/$$/exe)"
		echo "using shell : $sh"
	;;
esac

if [ "$1" = "" ]; then
	echo "Synopsis : $0 <path and name> [main jail user name] [main jail user group name]"
	echo "please input the name of the new directory to instantiate and optionally a name for the main jail's user name and optionally a name for the main jail's group name"
	exit 1
fi

jailPath=$(dirname $1)
jailName=$(basename $1)

[ "$2" = "" ] && mainJailUsername=$jailName || mainJailUsername=$2
[ "$3" = "" ] && mainJailUsergroup=$jailName || mainJailUsergroup=$3

if [ -e $1 ]; then
	echo "Invalid path given, file or directory already exists."
	exit 1
fi

if [ ! -d $jailPath ]; then
	echo "Invalid path given, the directory $jailPath does not exist."
	exit 1
fi

uid=$(id -u)
gid=$(id -g)

exe=$(readlink /proc/$$/exe)

if [ "$(dirname $0)" = "." ] && [ "$(basename $exe)" = "busybox" ]; then
	bb=$exe
	echo "Using busybox directly"
	ISINBUSYBOX=1
	eval "$($bb --show jt_utils)"
else
	bb=""
	ISINBUSYBOX=0

	ownPath=$(dirname $0)
	jtPath=$(dirname $ownPath)

	# include common functions
	. $ownPath/utils.sh

	# convert the path of this script to an absolute path
	if [ "$ownPath" = "." ]; then
		ownPath=$PWD
	else
		if [ "$(substring 0 1 $ownPath)" = "/" ]; then
			# absolute path, we do nothing
			:
		else
			# relative path
			ownPath=$PWD/$ownPath
		fi
	fi

	. $ownPath/paths.sh # this sets the variable 'bb'
fi

if [ ! -e $bb ]; then
	echo "Please run 'make' in \`$ownPath' to compile the necessary dependencies first"
	exit 1
fi

# check the kernel's namespace support
unshareSupport=$(for ns in m u i n p U C; do $bb unshare -$ns 'echo "Operation not permitted"; exit' 2>&1 | grep -q "Operation not permitted" && printf $ns; done)

if ! echo $unshareSupport | grep -q 'm'; then # check for mount namespace support
	echo "Linux kernel Mount namespace support was not detected. It is mandatory to use this tool. Bailing out."
	exit 1
fi

# optional commands

jailName=$(basename $1)
newChrootHolder=$1
newChrootDir=$newChrootHolder/root
echo "Instantiating directory : " $newChrootDir

mkdir $newChrootHolder
mkdir $newChrootHolder/run
mkdir $newChrootDir

touch $newChrootHolder/startRoot.sh # this is to make cpDep detect the new style jail
touch $newChrootHolder/rootCustomConfig.sh

if [ "$ISINBUSYBOX" = "1" ]; then
	fsData="$bb --show jt_filesystem_template"
else
	fsData="cat $ownPath/filesystem.template.sh"
fi

for fPath in $($fsData); do
	mkdir $newChrootDir/$fPath
	chmod 705 $newChrootDir/$fPath
done

if [ -h /lib64 ]; then
	echo "Linking /lib to /lib64"
	ln -s lib $newChrootDir/lib64
else
	mkdir $newChrootDir/lib64
fi

genPass() {
	len=$1
	cat /dev/urandom | head -c $(($len * 2)) | base64 | tr '/' '@' | head -c $len
}

echo "Populating the /etc configuration files"
# localtime
if [ "$ISINBUSYBOX" = "1" ]; then
	$bb jt_cpDep $newChrootHolder /etc /etc/localtime
else
	$sh $ownPath/cpDep.sh $newChrootHolder /etc/ /etc/localtime
fi
echo "Done populating /etc"
# group
cat >> $newChrootDir/etc/group << EOF
root:x:0:
$mainJailUsergroup:x:$gid:
EOF
chmod 644 $newChrootDir/etc/group
# passwd
cat >> $newChrootDir/etc/passwd << EOF
root:x:0:0::/root:/bin/false
nobody:x:99:99::/dev/null:/bin/false
$mainJailUsername:x:$uid:$gid::/home:/bin/false
EOF
chmod 644 $newChrootDir/etc/passwd
# shadow
cat >> $newChrootDir/etc/shadow << EOF
root:$(echo "$(genPass 200)" | $bb cryptpw -m sha512 -P 0 -S "$(genPass 16)"):0:0:99999:7:::
nobody:!:0:0:99999:7:::
$mainJailUsername:!:0:0:99999:7:::
EOF
chmod 600 $newChrootDir/etc/shadow
# shells
cat >> $newChrootDir/etc/shells << EOF
/bin/sh
/bin/false
EOF

# get the default internet facing network interface
defNetInterface=$($bb ip route | grep '^default' | sed -e 's/^.* dev \([^ ]*\) .*$/\1/')

echo Internet facing network interface : $defNetInterface

if [ "$ISINBUSYBOX" = "1" ]; then
	ownPath=$newChrootHolder

	$bb --show jt_jailLib_template > $ownPath/jailLib.template.sh
	$bb --show jt_startRoot_template > $ownPath/startRoot.template.sh
	$bb --show jt_rootDefaultConfig_template > $ownPath/rootDefaultConfig.template.sh
	$bb --show jt_rootCustomConfig_template > $ownPath/rootCustomConfig.template.sh
fi

populateFile $ownPath/jailLib.template.sh @SHELL@ "$bb sh" @JTPATH@ "$jtPath" @MAINJAILUSERNAME@ "$mainJailUsername" > $newChrootHolder/jailLib.sh

populateFile $ownPath/startRoot.template.sh @SHELL@ "$bb sh" @JTPATH@ "$jtPath" > $newChrootHolder/startRoot.sh

populateFile $ownPath/rootDefaultConfig.template.sh @SHELL@ "$bb sh" @JAILNAME@ "$jailName" @DEFAULTNETINTERFACE@ "$defNetInterface" > $newChrootHolder/rootDefaultConfig.sh
populateFile $ownPath/rootCustomConfig.template.sh @SHELL@ "$bb sh" @JAILNAME@ "$jailName" @DEFAULTNETINTERFACE@ "$defNetInterface" > $newChrootHolder/rootCustomConfig.sh

if [ "$ISINBUSYBOX" = "1" ]; then
	rm $ownPath/jailLib.template.sh
	rm $ownPath/startRoot.template.sh
	rm $ownPath/rootDefaultConfig.template.sh
	rm $ownPath/rootCustomConfig.template.sh
fi

# we save the default initial rootCustomConfig for update purposes
cp $newChrootHolder/rootCustomConfig.sh $newChrootHolder/._rootCustomConfig.sh.initial

echo "Copying /etc data"
etcFiles=""
for ef in termcap services protocols nsswitch.conf ld.so.cache inputrc hostname resolv.conf host.conf hosts; do etcFiles="$etcFiles /etc/$ef"; done
if [ "$ISINBUSYBOX" = "1" ]; then
	$bb jt_cpDep $newChrootHolder /etc/ $etcFiles
else
	$sh $ownPath/cpDep.sh $newChrootHolder /etc/ $etcFiles
fi

if [ "$ISINBUSYBOX" = "1" ]; then
	[ -e /etc/terminfo ] && $bb jt_cpDep $newChrootHolder /etc/ /etc/terminfo
	$bb jt_cpDep $newChrootHolder /bin $bb
else
	[ -e /etc/terminfo ] && $sh $ownPath/cpDep.sh $newChrootHolder /etc/ /etc/terminfo
	$sh $ownPath/cpDep.sh $newChrootHolder /bin $bb
fi

for app in $($bb --list-full); do ln -s /bin/busybox ${newChrootDir}/$app; done

# we append these to update.sh
echo "# end basic dependencies" >> $newChrootHolder/update.sh
echo "" >> $newChrootHolder/update.sh

echo "All done"
exit 0
