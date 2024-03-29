#! /bin/sh

# privileged general test

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/generalSU

bb=$testPath/../bin/busybox

. $testPath/../../utils/utils.sh

$jtPath new $jail >/dev/null 2>/dev/null || exit 1

uid=$($bb id -u)

jUid=$(lift $jtPath start $jail id -u 2>/dev/null)

if [ "$uid" != "$jUid" ]; then
	echo "jail UID must be the user's UID -- user id : '$uid' ---- jail user id : '$jUid'"
	exit 1
fi

if [ "$jUid" = "0" ]; then
	echo "jail UID must not be the root UID"
	exit 1
fi

# check the files run/{daemon.log, firewall.instructions and innerCoreLog} to make sure that they are
# not owned by root. They must be owned by the user instead.

lift $jtPath daemon $jail 2>/dev/null
lift $jtPath stop $jail

if [ "$($bb stat -c %U $jail/run/daemon.log)" != "$($bb id -nu)" ] \
	|| [ "$($bb stat -c %U $jail/run/firewall.instructions)" != "$($bb id -nu)" ] \
	|| [ "$($bb stat -c %U $jail/run/innerCoreLog)" != "$($bb id -nu)" ]; then
	
	echo "files in run/ must be owned by the user and they currently are not."
	echo "run/daemon.log owned by $($bb stat -c %U $jail/run/daemon.log) should be $($bb id -nu)"
	echo "run/firewall.instructions owned by $($bb stat -c %U $jail/run/firewall.instructions) should be $($bb id -nu)"
	echo "run/innerCoreLog owned by $($bb stat -c %U $jail/run/innerCoreLog) should be $($bb id -nu)"
	exit 1
fi

# check that the file $jail/run/.isPrivileged is set when we start the jail privileged
# and if it removed after the jail is stopped.

if [ -e $jail/run/.isPrivileged ]; then
	echo "the file run/.isPrivileged is not supposed to be present before we even started the jail."
	exit 1
fi

lift $jtPath daemon $jail 2>/dev/null

if [ ! -e $jail/run/.isPrivileged ]; then
	echo "the file run/.isPrivileged is supposed to be present for a privileged jail."
	lift $jtPath stop $jail 2>/dev/null
	exit 1
fi

lift $jtPath stop $jail 2>/dev/null

if [ -e $jail/run/.isPrivileged ]; then
	echo "the file run/.isPrivileged is not supposed to be present after we started the jail."
	exit 1
fi

# check the realRootInJail config which is supposed to provide in jail root.
# Of course, for an unprivileged instance we only expect the fake root.

# Setting the configuration : realRootInJail

$jtPath config $jail -s realRootInJail true >/dev/null 2>/dev/null

jUid=$(lift $jtPath start $jail id -u 2>/dev/null)
#jUid=$(lift $jtPath start $jail id -u)

if [ "$jUid" != "0" ]; then
	echo "With realRootInJail, jail UID must be the root UID we got : $jUid instead of 0"
	cat $jail/run/innerCoreLog
	exit 1
fi

# Doing a test by making a directory, changing it's ownership to root and checking it
if ! lift $jtPath start $jail mkdir /home/testDir 2>$jail/run/errorInfo; then
	echo "Unable to create the directory /home/testDir"
	cat $jail/run/errorInfo
	exit 1
fi

if ! lift $jtPath start $jail chown root /home/testDir 2>$jail/run/errorInfo; then
	echo "Attempt to change ownership of /home/testDir to root failed"
	cat $jail/run/errorInfo
	ls $jail/root
	exit 1
fi

if ! $bb stat -c %U $jail/root/home/testDir | grep -q root; then
	echo "user owning the directory : '$($bb stat -c %U $jail/root/home/testDir)' (expecting 'root')"
	exit 1
fi

# we test realRootInJail with a shell reentry in a daemon

$jtPath config $jail -s realRootInJail true >/dev/null 2>/dev/null

if ! lift $jtPath daemon $jail 2>/dev/null; then
	echo "Could not start a daemon instance"
	exit 1
fi

jUid=$(lift $jtPath shell $jail id -u 2>/dev/null)

if [ ! "$jUid" = "0" ]; then
	echo "daemon - jail UID must be the root UID - got $jUid and should be 0"
	lift $jtPath stop $jail 2>/dev/null || exit 1
	sleep 1
	exit 1
fi

if $jtPath shell $jail mkdir /home/testDirBogus 2>/dev/null; then
	echo "daemon - We are not supposed to be able to reenter this jail unprivileged"
	lift $jtPath stop $jail 2>/dev/null || exit 1
	exit 1
fi

if ! lift $jtPath shell $jail mkdir /home/testDir2 2>/dev/null; then
	echo "daemon - Could not create a directory"
	lift $jtPath stop $jail 2>/dev/null || exit 1
	exit 1
fi
if ! lift $jtPath shell $jail chown root /home/testDir2 2>/dev/null; then
	echo "daemon - Could not chown as root a directory"
	lift $jtPath stop $jail 2>/dev/null || exit 1
	exit 1
fi

if ! $bb stat -c %U $jail/root/home/testDir2 | grep -q root; then
	echo "daemon - user owning the directory : '$($bb stat -c %U $jail/root/home/testDir2)' (expecting 'root')"
	lift $jtPath stop $jail 2>/dev/null || exit 1
	sleep 1
	exit 1
fi

if ! lift $jtPath stop $jail 2>/dev/null; then
	echo  "Stopping daemonized jail failed"
	exit 1
fi

# test jt itself, embedded in busybox

# we of course expect this one to work
s1=$($jtPath v)
# now this is what we test (we reset PATH just in case it is installed)
s2=$(PATH= $jtPath busybox jt v)

if [ "$s1" != "$s2" ]; then
	echo "the embedded jt is not working correctly"
	PATH= $jtPath busybox jt v
	exit 1
fi

$jtPath config $jail -s realRootInJail false >/dev/null 2>/dev/null

# test that the pid namespace works correctly in the jail
# only if the pid namespace and user namespace are supported on the host system
if unshare -rp id >/dev/null; then
	lift $jtPath daemon $jail

	if ! $jtPath shell $jail unshare -rp id >/dev/null 2>/dev/null; then
		echo "PID namespace nesting inside a daemonized jail is not working correctly."
		lift $jtPath stop $jail
		exit 1
	fi
	lift $jtPath stop $jail

	if ! lift $jtPath start $jail unshare -rp id >/dev/null 2>/dev/null; then
		echo "PID namespace nesting inside a standalone jail is not working correctly."
		exit 1
	fi
fi

exit 0
