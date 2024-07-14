# This module takes care of creating a new jail.
#
# direct call :
# jt --run jt_new

bb="$BB"
shower="$JT_SHOWER"
runner="$JT_RUNNER"

IS_RUNNING=0

sh="$bb sh"

if [ "$1" = "" ]; then
	echo "Synopsis : $0 <path and name> [main jail user name] [main jail user group name]"
	echo "please input the name of the new directory to instantiate and optionally a name for the main jail's user name and optionally a name for the main jail's group name"
	exit 1
fi

jailPath=$($bb dirname $1)
jailName=$($bb basename $1)

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

uid=$($bb id -u)
gid=$($bb id -g)

bb="$BB"
shower="$JT_SHOWER"
runner="$JT_RUNNER"

eval "$($shower jt_utils)"

# check the kernel's namespace support
unshareSupport=$(for ns in m u i n p U C; do $bb unshare -$ns 'echo "Operation not permitted"; exit' 2>&1 | $bb grep -q "Operation not permitted" && printf $ns; done)

if ! echo $unshareSupport | $bb grep -q 'm'; then # check for mount namespace support
	echo "Linux kernel Mount namespace support was not detected. It is mandatory to use this tool. Bailing out."
	exit 1
fi

# optional commands

newChrootHolder=$jailPath/$jailName
newChrootDir=$newChrootHolder/root
echo "Instantiating directory : " $newChrootDir

$bb mkdir $newChrootHolder
$bb mkdir $newChrootHolder/run
$bb mkdir $newChrootDir

$bb mkdir $newChrootDir/bin
echo "copying jt over to the jail - '$JT_CALLER'"
exe=$(echo $JT_CALLER | $bb sed -e 's/^\([^ ]*\) .*/\1/')
$bb cp $exe $newChrootHolder/root/bin/busybox
bb=$newChrootHolder/root/bin/busybox

$bb touch $newChrootHolder/rootCustomConfig.sh

fsData="$shower jt_filesystem_template"

for fPath in $($fsData); do
	$bb mkdir -p $newChrootDir/$fPath
	$bb chmod 705 $newChrootDir/$fPath
done

if [ -h /lib64 ]; then
	echo "Linking /lib to /lib64"
	$bb ln -s lib $newChrootDir/lib64
else
	$bb mkdir $newChrootDir/lib64
fi

genPass() {
	len=$1
	$bb cat /dev/urandom | $bb head -c $(($len * 2)) | $bb base64 | $bb tr '/' '@' | $bb head -c $len
}

ownPath=$newChrootHolder

$shower jt_rootDefaultConfig_template > $ownPath/rootDefaultConfig.template.sh
$shower jt_rootCustomConfig_template > $ownPath/rootCustomConfig.template.sh


populateFile $ownPath/rootDefaultConfig.template.sh @SHELL@ "$bb sh" @JAILNAME@ "$jailName" @MAINJAILUSERNAME@ "$mainJailUsername" @JAIL_VERSION@ "$JT_VERSION" > $newChrootHolder/rootDefaultConfig.sh
populateFile $ownPath/rootCustomConfig.template.sh @SHELL@ "$bb sh" > $newChrootHolder/rootCustomConfig.sh

$bb rm $ownPath/rootDefaultConfig.template.sh
$bb rm $ownPath/rootCustomConfig.template.sh

# we save the default initial rootCustomConfig for update purposes
$bb cp $newChrootHolder/rootCustomConfig.sh $newChrootHolder/._rootCustomConfig.sh.initial

echo "Populating the /etc configuration files"
# localtime
$runner jt_cpDep $newChrootHolder /etc /etc/localtime
echo "Done populating /etc"
# group
$bb cat >> $newChrootDir/etc/group << EOF
root:x:0:
$mainJailUsergroup:x:$gid:
EOF
$bb chmod 644 $newChrootDir/etc/group
# passwd
$bb cat >> $newChrootDir/etc/passwd << EOF
root:x:0:0::/root:/bin/false
nobody:x:99:99::/dev/null:/bin/false
$mainJailUsername:x:$uid:$gid::/home:/bin/sh
EOF
$bb chmod 644 $newChrootDir/etc/passwd
# shadow
$bb cat >> $newChrootDir/etc/shadow << EOF
root:$(echo "$(genPass 200)" | $bb cryptpw -m sha512 -P 0 -S "$(genPass 16)"):0:0:99999:7:::
nobody:!:0:0:99999:7:::
$mainJailUsername:!:0:0:99999:7:::
EOF
$bb chmod 600 $newChrootDir/etc/shadow
# shells
$bb cat >> $newChrootDir/etc/shells << EOF
/bin/sh
/bin/false
EOF

echo "Copying /etc data"
etcFiles=""
for ef in termcap services protocols nsswitch.conf ld.so.cache inputrc hostname resolv.conf host.conf hosts; do etcFiles="$etcFiles /etc/$ef"; done
$runner jt_cpDep $newChrootHolder /etc/ $etcFiles


for app in $($bb --list-full); do $bb ln -s /bin/busybox ${newChrootDir}/$app; done

# we append these to update.sh
echo "# end basic dependencies" >> $newChrootHolder/update.sh
echo "" >> $newChrootHolder/update.sh

echo "All done"
exit 0
