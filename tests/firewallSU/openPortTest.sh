#! /bin/sh

rawProto=$1
sh=$2
testPath=$3
jtPath=$4
jail=$5
bb=$6
thisPath=$7

. $testPath/../../utils/utils.sh

if [ "$rawProto" = "udp" ]; then
	proto="udp"
	protoName="Udp"
else
	proto="tcp"
	protoName="Tcp"
fi

# simple test
cat - > $jail/root/home/firewallCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall open${protoName}Port fwTestIn fwTestOut 8000
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external open${protoName}Port fwTestIn fwTestOut 8000;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -o fwTestIn -p $proto -m $proto --dport 8000 -j ACCEPT
-A OUTPUT -o fwTestOut -p $proto -m $proto --sport 8000 -j ACCEPT
-A INPUT -i fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
-A INPUT -i fwTestIn -p $proto -m $proto --sport 8000 -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "Simple open${protoName}Port test failed"
	exit 1
fi
# simple test end

# checks test
cat - > $jail/root/home/firewallCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall -c open${protoName}Port fwTestIn fwTestOut 8000 >&2 && exit 1
sh /home/firewallFront.sh \$fwInstrPath firewall open${protoName}Port fwTestIn fwTestOut 8000
sh /home/firewallFront.sh \$fwInstrPath firewall -c open${protoName}Port fwTestIn fwTestOut 8000 >&2 || exit 1
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external open${protoName}Port fwTestIn fwTestOut 8000;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -o fwTestIn -p $proto -m $proto --dport 8000 -j ACCEPT
-A OUTPUT -o fwTestOut -p $proto -m $proto --sport 8000 -j ACCEPT
-A INPUT -i fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
-A INPUT -i fwTestIn -p $proto -m $proto --sport 8000 -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "open${protoName}Port checks test failed"
	exit 1
fi
# checks test

# duplication test
cat - > $jail/root/home/firewallCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall open${protoName}Port fwTestIn fwTestOut 8000
sh /home/firewallFront.sh \$fwInstrPath firewall open${protoName}Port fwTestIn fwTestOut 8000
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external open${protoName}Port fwTestIn fwTestOut 8000;
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -o fwTestIn -p $proto -m $proto --dport 8000 -j ACCEPT
-A OUTPUT -o fwTestOut -p $proto -m $proto --sport 8000 -j ACCEPT
-A INPUT -i fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
-A INPUT -i fwTestIn -p $proto -m $proto --sport 8000 -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "open${protoName}Port duplication test failed"
	exit 1
fi
# duplication test end

# duplication with the instruction file removed
cat - > $jail/root/home/firewallCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall open${protoName}Port fwTestIn fwTestOut 8000

# we remove the entry to see if the function can detect that
# the entries are already there without using the instructions file.
[ -e \$fwInstrPath ] && rm \$fwInstrPath
sh /home/firewallFront.sh \$fwInstrPath firewall open${protoName}Port fwTestIn fwTestOut 8000
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -o fwTestIn -p $proto -m $proto --dport 8000 -j ACCEPT
-A OUTPUT -o fwTestOut -p $proto -m $proto --sport 8000 -j ACCEPT
-A INPUT -i fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
-A INPUT -i fwTestIn -p $proto -m $proto --sport 8000 -j ACCEPT
EOF

if ! lift $jtPath start $jail sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules 2>/dev/null; then
	echo "open${protoName}Port duplication with the instruction file removed test failed"
	exit 1
fi
# duplication with the instruction file removed end

# rule deletion test
cat - > $jail/root/home/firewallCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall open${protoName}Port fwTestIn fwTestOut 8000
EOF

cat - > $jail/root/home/firewallExpectedInstr << EOF
firewall /tmp/firewallInstructions.txt external open${protoName}Port fwTestIn fwTestOut 8000;
EOF

cat - > $jail/root/home/firewallDeleteCmd << EOF
sh /home/firewallFront.sh \$fwInstrPath firewall -d open${protoName}Port fwTestIn fwTestOut 8000
EOF

cat - > $jail/root/home/firewallExpectedDeleteInstr << EOF
EOF

cat - > $jail/root/home/firewallExpectedIptablesRules << EOF
-A OUTPUT -o fwTestIn -p $proto -m $proto --dport 8000 -j ACCEPT
-A OUTPUT -o fwTestOut -p $proto -m $proto --sport 8000 -j ACCEPT
-A INPUT -i fwTestOut -p $proto -m $proto --dport 8000 -j ACCEPT
-A INPUT -i fwTestIn -p $proto -m $proto --sport 8000 -j ACCEPT
EOF

cat - > $jail/root/home/runTest.sh << EOF
#! /bin/sh

sh /home/singleTest.sh /home/firewallCmd /home/firewallExpectedInstr /home/firewallExpectedIptablesRules

echo Now we delete the inserted rules >&2

sh /home/singleTest.sh -d /home/firewallDeleteCmd /home/firewallExpectedDeleteInstr /home/firewallExpectedIptablesRules
EOF

if ! lift $jtPath start $jail sh /home/runTest.sh 2>/dev/null; then
	echo "open${protoName}Port deletion test failed"
	exit 1
fi
# rule deletion test end

exit 0
