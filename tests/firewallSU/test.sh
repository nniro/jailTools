#! /bin/sh

sh=$1
testPath=$2
jtPath=$3

jail=$testPath/fwTest

bb=$testPath/../bin/busybox

thisPath=$PWD/firewallSU

. $testPath/../../utils/utils.sh

$jtPath new $jail >/dev/null 2>/dev/null || exit 1

$jtPath config $jail -s realRootInJail true >/dev/null 2>/dev/null

cat - > $jail/root/home/firewallFront.sh << EOF
#! /bin/sh

eval "\$(jt --show jt_firewall)"

firewallCLI \$@

exit \$?

EOF

$jtPath cp $jail /usr/sbin /usr/sbin/iptables /usr/sbin/iptables-save

if [ ! -e $jail/root/usr/sbin/iptables ] || [ ! -e $jail/root/usr/sbin/iptables-save ]; then
	echo "Mandatory applications iptables and/or iptables-save are missing."
	exit 1
fi

$jtPath config $jail -s runEnvironment "PATH=\"/sbin:/usr/sbin:/bin:/usr/bin\" $($jtPath config $jail -g runEnvironment)" >/dev/null 2>/dev/null

$jtPath config $jail -s networking true >/dev/null 2>/dev/null
$jtPath config $jail -s setNetAccess false >/dev/null 2>/dev/null

cat - > $jail/root/home/testUtils.sh << EOF
checkLines() {
	local _err=0
        for l in \$1; do
                #echo "entry : '\$l'"
                count=\$(printf "%s" "\$2" | grep -- "^\$l$" | wc -l)

                if [ "\$count" = "0" ]; then
                        echo "\$l - Not present"
			[ "\$_err" = "0" ] && _err=1
                elif [ \$((\$count > 1)) = 1 ]; then
                        echo "\$l - More than one entry detected"
			[ "\$_err" = "0" ] && _err=2
                fi
        done
	return \$_err
}
EOF

cat - > $jail/root/home/singleTest.sh << EOF
. /home/testUtils.sh

deleteMode="false"
if [ "\$1" = "-d" ]; then
	deleteMode="true"
	shift
fi

cmdFile=\$1
expectedInstrRuleFile=\$2
expectedIptablesRulesFile=\$3
shift 3

if [ ! -e \$cmdFile ]; then
	echo cmdFile missing
	exit 1
fi

if [ ! -e \$expectedInstrRuleFile ]; then
	echo expectedInstrRuleFile missing
	exit 1
fi

if [ ! -e \$expectedIptablesRuleFile ]; then
	echo expectedIptablesRulesFile missing
	exit 1
fi

cd /home

fwInstrPath=/tmp/firewallInstructions.txt

if [ "\$deleteMode" = "false" ]; then
	[ -e \$fwInstrPath ] && rm \$fwInstrPath
fi

. \$cmdFile

if [ ! -e \$fwInstrPath ]; then
	echo "file '\$fwInstrPath' should exist but it doesn't"
	exit 1
fi

if ! test -s \$expectedInstrRuleFile; then
	# we expect the instruction file to contain nothing
	if test -s \$fwInstrPath; then
		echo "The file firewallInstructions.txt should be empty but it has an unexpected content '\$(cat \$fwInstrPath)'"
		exit 1
	fi
else
	if ! cat \$fwInstrPath | grep -q "^\$(cat \$expectedInstrRuleFile)$"; then
		echo "The file firewallInstructions.txt should be '\$(cat \$expectedInstrRuleFile)' has an unexpected content '\$(cat \$fwInstrPath)'"
		exit 1
	fi
fi

result=\$(iptables-save)
IFS="
"
output=\$(checkLines "\$(cat \$expectedIptablesRulesFile)" "\$result")
_err=\$?

if [ "\$deleteMode" = "false" ]; then
	if [ \$((\$_err >= 1)) = 1 ]; then
		echo \$output
		echo "result from iptables-save : '\$result'"
		exit 1
	fi
elif [ "\$deleteMode" = "true" ]; then # check if all the rules are *not* in the iptables rules
	if [ \$((\$_err == 1)) = 1 ]; then
		exit 0
	else
		echo "Iptables rules are still present but they shouldn't be"
		echo "the full iptables rules dump : '\$result'"
		exit 1
	fi
fi
EOF

# test blockAll
subTestStart "blockAll" $sh $thisPath/blockAllTest.sh $sh $testPath $jtPath $jail $bb $thisPath || exit 1

# test openPort tcp and udp
subTest "openPort tcp" $sh $thisPath/openPortTest.sh tcp $sh $testPath $jtPath $jail $bb $thisPath || exit 1
subTest "openPort udp" $sh $thisPath/openPortTest.sh udp $sh $testPath $jtPath $jail $bb $thisPath || exit 1

# test allowConnection tcp and udp
subTest "allowConnection tcp" $sh $thisPath/allowConnectionTest.sh tcp $sh $testPath $jtPath $jail $bb $thisPath || exit 1
subTest "allowConnection udp" $sh $thisPath/allowConnectionTest.sh udp $sh $testPath $jtPath $jail $bb $thisPath || exit 1

# test dnat tcp and udp
subTest "dnat tcp" $sh $thisPath/dnatTest.sh tcp $sh $testPath $jtPath $jail $bb $thisPath || exit 1
subTest "dnat udp" $sh $thisPath/dnatTest.sh udp $sh $testPath $jtPath $jail $bb $thisPath || exit 1

# test snat
subTestEnd "snat" $sh $thisPath/snatTest.sh $sh $testPath $jtPath $jail $bb $thisPath || exit 1

exit 0
