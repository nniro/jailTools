#! /bin/sh

# this tests the function callGetopt from the utils.sh file.

sh=$1
testPath=$2
jtPath=$3
scriptsPath=../scripts

. $scriptsPath/paths.sh # set the bb variable

. $scriptsPath/utils.sh

stdTest() {
	local result=""
	result=$(callGetopt "status [OPTIONS] <argument 1> <argument 2>" \
	       -o "i" "" "display ip information" "showIp" "false" \
	       -o "" "ps" "display process information" "showProcessStats" "false" \
	       -o "t" "" "display temperature" "showTemp" "false" \
	       -o "o" "output" "some output needs an input" "outputData" "true" \
	       -o '' '' "" "arg1Data" "true" \
	       -o '' '' "" "arg2Data" "true" \
	       -- "$@" 2>&1)
	err=$?

	echo $result
	return $err
}

echo "Standard test"
echo "Testing the help output"
result="$(stdTest -h)"
err=$?
echo "return status must be 2"
echo $err | grep -q '2' || exit 1
echo "the help message format must be specific"
#echo $result >&2
expectedHelpMsg="status \[OPTIONS\] <argument 1> <argument 2>"
expectedHelpMsg="$expectedHelpMsg -h, --help display this help"
expectedHelpMsg="$expectedHelpMsg -i display ip information"
expectedHelpMsg="$expectedHelpMsg --ps display process information"
expectedHelpMsg="$expectedHelpMsg -t display temperature"
expectedHelpMsg="$expectedHelpMsg -o INPUT, --output=INPUT some output needs an input"
printf "%s" "$result" | grep -q "^$expectedHelpMsg" || exit 1

echo "first short option"
result="$(stdTest -i)"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "return value for showIp"
printf "%s" "$result" | grep -q 'showIp="1";showProcessStats="0";showTemp="0";outputData="";arg1Data="";arg2Data=""' || exit 1

echo "second long option"
result="$(stdTest --ps)"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "return value for showProcessStats"
printf "%s" "$result" | grep -q 'showIp="0";showProcessStats="1";showTemp="0";outputData="";arg1Data="";arg2Data=""' || exit 1

echo "third short option"
result="$(stdTest -t)"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "return value for showTemp"
printf "%s" "$result" | grep -q 'showIp="0";showProcessStats="0";showTemp="1";outputData="";arg1Data="";arg2Data=""' || exit 1

echo "test two short options at once"
result="$(stdTest -it)"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "return value for showIp and showTemp"
printf "%s" "$result" | grep -q 'showIp="1";showProcessStats="0";showTemp="1";outputData="";arg1Data="";arg2Data=""' || exit 1

echo "third option with argument"
echo "first testing without an argument"
result="$(stdTest -o)"
err=$?
echo "return status must be 1"
echo $err | grep -q '1' || exit 1
echo "result must contain the error message"
printf "%s" "$result" | grep -q "getopt: option requires an argument: o" || exit 1

echo "testing without an argument on long argument"
result="$(stdTest --output)"
err=$?
echo "return status must be 1"
echo $err | grep -q '1' || exit 1
echo "result must contain the error message"
printf "%s" "$result" | grep -q "getopt: option requires an argument: output" || exit 1

echo "setting a value to the short option"
result="$(stdTest -o one)"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "result must contain the value"
printf "%s" "$result" | grep -q 'showIp="0";showProcessStats="0";showTemp="0";outputData="one";arg1Data="";arg2Data=""' || exit 1

echo "setting a value to the long option"
result="$(stdTest --output=one)"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "result must contain the value"
printf "%s" "$result" | grep -q 'showIp="0";showProcessStats="0";showTemp="0";outputData="one";arg1Data="";arg2Data=""' || exit 1

echo "setting a value to the short option without a space"
result="$(stdTest -oone)"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "result must contain the value"
printf "%s" "$result" | grep -q 'showIp="0";showProcessStats="0";showTemp="0";outputData="one";arg1Data="";arg2Data=""' || exit 1

echo "setting a value to the short option in a quasi invalid way"
result="$(stdTest -o=one)"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "result must contain the value"
printf "%s" "$result" | grep -q 'showIp="0";showProcessStats="0";showTemp="0";outputData="=one";arg1Data="";arg2Data=""' || exit 1

echo "setting multiple arguments to a short option"
result="$(stdTest -o'foo bar avec du beurre')"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "result must contain the value"
printf "%s" "$result" | grep -q 'showIp="0";showProcessStats="0";showTemp="0";outputData="foo bar avec du beurre";arg1Data="";arg2Data=""' || exit 1

echo "setting multiple arguments to a short option v2"
result="$(stdTest -o 'foo bar avec du beurre')"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "result must contain the value"
printf "%s" "$result" | grep -q 'showIp="0";showProcessStats="0";showTemp="0";outputData="foo bar avec du beurre";arg1Data="";arg2Data=""' || exit 1

echo "values without flags"
echo "test first"
result="$(stdTest foo)"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "result must contain the value"
printf "%s" "$result" | grep -q 'showIp="0";showProcessStats="0";showTemp="0";outputData="";arg1Data="foo";arg2Data=""' || exit 1

echo "test first and second"
result="$(stdTest foo bar)"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "result must contain the value"
printf "%s" "$result" | grep -q 'showIp="0";showProcessStats="0";showTemp="0";outputData="";arg1Data="foo";arg2Data="bar"' || exit 1

echo "second should be catch all as it is the last"
result="$(stdTest foo bar avec du beurre)"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "result must contain the value"
printf "%s" "$result" | grep -q 'showIp="0";showProcessStats="0";showTemp="0";outputData="";arg1Data="foo";arg2Data="bar avec du beurre"' || exit 1

echo "test the catch all with some content in single quotes"
result="$(stdTest foo bar 'avec du' beurre)"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "result must contain the value"
printf "%s" "$result" | grep -q "showIp=\"0\";showProcessStats=\"0\";showTemp=\"0\";outputData=\"\";arg1Data=\"foo\";arg2Data=\"bar 'avec du' beurre\"" || exit 1

echo "test the catch all with some content in double quotes"
result="$(stdTest foo bar "avec du" beurre)"
err=$?
echo "return status must be 0"
echo $err | grep -q '0' || exit 1
echo "result must contain the value"
printf "%s" "$result" | grep -q "showIp=\"0\";showProcessStats=\"0\";showTemp=\"0\";outputData=\"\";arg1Data=\"foo\";arg2Data=\"bar 'avec du' beurre\"" || exit 1


exit 0
