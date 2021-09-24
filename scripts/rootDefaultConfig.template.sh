# This is the default configuration settings.
# DO NOT CHANGE THE VALUES IN THIS FILE
# use rootCustomConfig.sh instead

# substring offset <optional length> string
# cuts a string at the starting offset and wanted length.
substring() {
	local init=$1; shift
	if [ "$2" != "" ]; then toFetch="\(.\{$1\}\).*"; shift; else local toFetch="\(.*\)"; fi
	echo "$1" | $bb sed -e "s/^.\{$init\}$toFetch$/\1/"
}

# the name of the jail, leaving this at the default is recommended.
jailName="@JAILNAME@"

# If set to true, this will create a new network namespace for the jail
# enabling the jail to have it's own "private" network access.
# When false, the jail gets exactly the same network access as the
# base system.
jailNet="true"

# If set to true, a new bridge will be created with the name
# bridgeName(see below). This permits external sources to join
# it (jails or otherwise) and potentially gaining access to
# services from this jail.
# NOTE : Creating a bridge requires privileged access.
createBridge="false"
# this is the bridge we will create if createBridge=true
bridgeName="$(substring 0 13 $jailName)"
# only used if createBridge=true
bridgeIp="192.168.99.1"
bridgeIpBitmask="24"

# This creates a pair of virtual ethernet devices which can be
# used to access the ressources from this jail from the base system
# and, with the help of firewall rules, access from abroad too.
# It does not grant access to the internet by itself.
# See setNetAccess for that.
# NOTE : This is only available when jailNet=true.
# NOTE : Enabling networking requires privileged access.
networking="false"

# To add devices (in the /dev folder) of the jail use the addDevices function. You
# don't need to add the starting /dev path.
# If for example you wanted to add the 'null' 'urandom' and 'zero' devices you would need :
#
# 	"null urandom zero"
#
# Note that the jail's /dev directory is now a tmpfs so it's content is purged every time
# the jail is stopped. Also note that this puts exactly the same file permissions
# as those on the base system.
#availableDevices=<devices list, separated by a space>
availableDevices="null random urandom zero"

# for programs, you may want to have the /sys special directory mounted.
# unfortunately, it won't work adding it into the roMountPoints section anymore
# so you have to mount it manually using this.
# set to true to get a /sys directory in your jail.
# NOTE : only mount this for applications, not for services as it tells a whole lot about the system itself.
mountSys="true"

# this is the external IP.
# Only valid if networking=true
extIp="172.16.0.1"
extIpBitmask="24"

# This is automatically set but you can change this value
# if you like. You may for example decide to make a jail
# only pass through a tunnel or a vpn. Otherwise, keep
# this value to the default value.
# use the value "auto" so the default (internet facing)
# network interface is used.
#netInterface=<network interface>
netInterface="auto"

# This boolean sets if you want your jail to
# gain full internet access using a technique called
# SNAT or Masquerading. This will make the jail able to
# access the internet and your LAN as if it was on the
# host system.
# Only valid if networking=true
setNetAccess="false"

# Note that this is valid _only_ for unprivileged jails.
# 	If you want this for a privileged jail, put false to jailNet
# This actually disables the network namespace so the jail
# gets exactly the same network interface as the base system.
disableUnprivilegedNetworkNamespace="true"

# activate this in case you actually need the real root user in your jail.
# You should never use this unless you know exactly what you are doing as the
# all powerful root user renders every security measures pretty much void.
# *This is necessary for running sandstorm*.
realRootInJail="false"

corePrivileges="-all,+setpcap,+sys_chroot,+dac_override,+setuid,+setgid,+sys_admin"
chrootPrivileges="-all,+setuid,+setgid,+net_bind_service"
jailPrivileges="-all,+setpcap,+sys_chroot,+dac_override,+setuid,+setgid,+net_bind_service"

# chroot internal IP
# the one liner script is to make sure it is of the same network
# class as the extIp.
# Just change the ending number to set the IP.
# defaults to "2"
# we let jailLib set this one as extIp is usually set by the user
#ipInt=$(echo $extIp | $bb sed -e 's/^\(.*\)\.[0-9]*$/\1\./')2
# chroot internal IP mask
ipIntBitmask="24"
# These are setup only if networking is true
# the external veth interface name (only 15 characters maximum)
vethExt="$(substring 0 13 $jailName)ex"
# the internal veth interface name (only 15 characters maximum)
vethInt="$(substring 0 13 $jailName)in"

