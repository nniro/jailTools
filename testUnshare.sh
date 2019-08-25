#! /bin/sh

unsharePath=$1

# test which unshare namespaces are available
# This has to be done as a normal user as we don't want
# to actually run these namespaces, we rely on their
# messages. But we also support this being run as root.

case "$(readlink -f /proc/$$/exe)" in
	*)
		sh="$(readlink -f /proc/$$/exe)"
		#echo "using shell : $sh"
	;;
esac

if [ "$unsharePath" = "" ]; then
	unsharePath=unshare
fi

# -m -u -i -n -p -U -C
# -m mount ns
# -u UTS ns
# -i IPC ns
# -n net ns
# -p pid ns
# -U user ns
# -C cgroups ns
for ns in m u i n p U C; do
	result=$($unsharePath -$ns echo 'it works' 2>&1)
	successMessage="Operation not permitted"

	if [ "$result" = "it works" ] || $(echo $result | sed -ne "/$successMessage/ q 0; q 1"); then
		printf $ns
	fi
done
echo
