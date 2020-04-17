#! /bin/sh

unsharePath=$1

# test which linux namespaces are available
# We support this as a normal user and superuser.

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
