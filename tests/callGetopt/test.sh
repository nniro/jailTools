#! /bin/sh

# this tests the function callGetopt from the utils.sh file.

sh=$1
testPath=$2
jtPath=$3
scriptsPath=../scripts

bb=$testPath/../bin/busybox

. $scriptsPath/utils.sh

standardCLIOptions() {
	# note we may be tempted to put local on the result assignation below but
	# it turns out that "local" actually interferes with the returned status value.
	# this is why we set result as local before assigning it. And this should serve
	# as a warning to your implementations as well.
	local result=""
	result=$(callGetopt "status [OPTIONS] <argument 1> <argument 2>" \
	       -o "i" "" "display ip information" "showIp" "false" \
	       -o "" "ps" "display process information" "showProcessStats" "false" \
	       -o "t" "" "display temperature" "showTemp" "false" \
	       -o "o" "output" "some output needs an input" "outputData" "true" \
	       -o '' '' "" "arg1Data" "true" \
	       -o '' '' "" "arg2Data" "true" \
	       -- "$@" 2>&1)
	local err=$?

	echo $result
	return $err
}

doTestAttempt() {
	local sectionName="$1"
	local testName="$2"
	local expectedStatusResult="$3"
	local expectedValueResult="$4"
	shift 4 # the rest is the command to run and the arguments to it

	# got to use eval for when there are spaces in the arguments, otherwise
	# it won't work.
	actualValueResult="$(eval $@)"
	actualStatusResult=$?

	local isStatusResultError=0
	local isValueResultError=0

	if [ "$actualStatusResult" != "$expectedStatusResult" ]; then
		isStatusResultError=1
	fi

	if echo "$actualValueResult" | grep -q "^$expectedValueResult$"; then
		:
	else
		isValueResultError=1
	fi

	if [ "$isStatusResultError" = "1" ] || [ "$isValueResultError" = "1" ]; then
		echo "Section : $sectionName"
		echo "Test : $testName"

		if [ "$isStatusResultError" = "1" ]; then
			echo "Status result gave $actualStatusResult instead of the expected $expectedStatusResult"
		elif [ "$isValueResultError" = "1" ]; then
			echo "Value result gave : "
			echo "'$actualValueResult'"
			echo "instead of the expected "
			echo "'$expectedValueResult'"
		fi

		exit 1
	fi
}

doTestAttempt "Basic Core tests" "Testing a bare help output" \
	2 "-h, --help display this help" \
	"result=\$(callGetopt '' -- '-h' 2>&1); err=\$?; echo \$result; return \$err"

doTestAttempt "Basic Core tests" "Without any argument" \
	1 "" \
	"result=\$(callGetopt 2>&1); err=\$?; echo \$result; return \$err"

doTestAttempt "Basic Core tests" "Without '--'" \
	0 "" \
	"result=\$(callGetopt \"sample options\" foo 2>&1); err=\$?; echo \$result; return \$err"

doTestAttempt "Basic Core tests" "Without '--' v2" \
	0 'showIp="1"' \
	"result=\$(callGetopt \"sample options\" -o \"i\" \"\" \"display ip information\" \"showIp\" \"false\" -i 2>&1); err=\$?; echo \$result; return \$err"

expectedHelpMsg="status \[OPTIONS\] <argument 1> <argument 2>"
expectedHelpMsg="$expectedHelpMsg -h, --help display this help"
expectedHelpMsg="$expectedHelpMsg -i display ip information"
expectedHelpMsg="$expectedHelpMsg --ps display process information"
expectedHelpMsg="$expectedHelpMsg -t display temperature"
expectedHelpMsg="$expectedHelpMsg -o INPUT, --output=INPUT some output needs an input"

doTestAttempt "Basic Core tests" "Testing the help output" \
	2 "$expectedHelpMsg" "standardCLIOptions -h"

doTestAttempt "Basic Core tests" "Testing the first short option" \
	0 'showIp="1";showProcessStats="0";showTemp="0";outputData="";arg1Data="";arg2Data=""' \
	"standardCLIOptions -i"

doTestAttempt "Basic Core tests" "Testing the second long option" \
	0 'showIp="0";showProcessStats="1";showTemp="0";outputData="";arg1Data="";arg2Data=""' \
	"standardCLIOptions --ps"

doTestAttempt "Basic Core tests" "Testing the third short option" \
	0 'showIp="0";showProcessStats="0";showTemp="1";outputData="";arg1Data="";arg2Data=""' \
	"standardCLIOptions -t"

doTestAttempt "Basic Core tests" "Testing two short options at once" \
	0 'showIp="1";showProcessStats="0";showTemp="1";outputData="";arg1Data="";arg2Data=""' \
	"standardCLIOptions -it"

doTestAttempt "Options with arguments" "first testing without an argument" \
	1 'getopt: option requires an argument: o' \
	"standardCLIOptions -o"

doTestAttempt "Options with arguments" "testing without an argument on long argument" \
	1 'getopt: option requires an argument: output' \
	"standardCLIOptions --output"

doTestAttempt "Options with arguments" "setting a value to the short option" \
	0 'showIp="0";showProcessStats="0";showTemp="0";outputData="one";arg1Data="";arg2Data=""' \
	"standardCLIOptions -o one"

doTestAttempt "Options with arguments" "setting a value to the long option" \
	0 'showIp="0";showProcessStats="0";showTemp="0";outputData="one";arg1Data="";arg2Data=""' \
	"standardCLIOptions --output=one"

doTestAttempt "Options with arguments" "setting a value to the short option without a space" \
	0 'showIp="0";showProcessStats="0";showTemp="0";outputData="one";arg1Data="";arg2Data=""' \
	"standardCLIOptions -oone"

doTestAttempt "Options with arguments" "setting a value to the short option in a quasi invalid way" \
	0 'showIp="0";showProcessStats="0";showTemp="0";outputData="%3Done";arg1Data="";arg2Data=""' \
	"standardCLIOptions -o=one"

doTestAttempt "Options with arguments" "setting multiple arguments to a short option" \
	0 'showIp="0";showProcessStats="0";showTemp="0";outputData="foo bar avec du beurre";arg1Data="";arg2Data=""' \
	"standardCLIOptions -o'foo bar avec du beurre'"

doTestAttempt "Options with arguments" "setting multiple arguments to a short option v2" \
	0 'showIp="0";showProcessStats="0";showTemp="0";outputData="foo bar avec du beurre";arg1Data="";arg2Data=""' \
	"standardCLIOptions -o 'foo bar avec du beurre'"

doTestAttempt "Values without flags" "testing first" \
	0 'showIp="0";showProcessStats="0";showTemp="0";outputData="";arg1Data="foo";arg2Data=""' \
	"standardCLIOptions foo"

doTestAttempt "Values without flags" "testing first and second" \
	0 'showIp="0";showProcessStats="0";showTemp="0";outputData="";arg1Data="foo";arg2Data="bar"' \
	"standardCLIOptions foo bar"

doTestAttempt "Values without flags" "second should be catch all as it is the last" \
	0 'showIp="0";showProcessStats="0";showTemp="0";outputData="";arg1Data="foo";arg2Data="bar avec du beurre"' \
	"standardCLIOptions foo bar avec du beurre"

doTestAttempt "Values without flags" "test the catch all with some content in single quotes" \
	0 "showIp=\"0\";showProcessStats=\"0\";showTemp=\"0\";outputData=\"\";arg1Data=\"foo\";arg2Data=\"bar 'avec du' beurre\"" \
	"standardCLIOptions foo bar 'avec du' beurre"

doTestAttempt "Values without flags" "test the catch all with some content in double quotes" \
	0 "showIp=\"0\";showProcessStats=\"0\";showTemp=\"0\";outputData=\"\";arg1Data=\"foo\";arg2Data=\"bar 'avec du' beurre\"" \
	"standardCLIOptions foo bar \"avec du\" beurre"

# the character ';' is special because it's what is necessary to parse the result value.
# So it is converted to the value %3B and that has to be converted back by the calling
# process.
doTestAttempt "Values without flags" "test the catch all with quoted string and ';'" \
	0 "showIp=\"0\";showProcessStats=\"0\";showTemp=\"0\";outputData=\"\";arg1Data=\"foo\";arg2Data=\"bar 'avec du%3B cd ..%3B bah' beurre\"" \
	'standardCLIOptions foo bar "avec du; cd ..; bah" beurre'

exit 0
