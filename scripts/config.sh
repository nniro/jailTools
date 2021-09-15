#! /bin/sh

jailToolsPath=$1
jailDir=$2
shift 2

bb="$BB"
shower="$JT_SHOWER"
runner="$JT_RUNNER"


eval "$($shower jt_utils)"


if cat $jailDir/rootCustomConfig.sh | grep -q '^# Command part$'; then
	echo Please update your jail before you can use this command.
	exit 1
fi

commandHeader='################# Command part #################'
if cat $jailDir/rootCustomConfig.sh | grep -q "^$commandHeader$"; then
	:
else
	echo "There has been a modification to your rootCustomConfig.sh file that makes this functionality unable to do it's job"
	echo "Please don't remove or modify the section headers. They are used by this tool"
	exit 1
fi

listCore() {
	jailScript=$1

	cat $jailScript | sed -ne 's/^\([^# =]\+\)=.*$/\1/ p'
}

listConfigs() {
	jailDir=$1

	listCore $jailDir/rootDefaultConfig.sh
	listCore $jailDir/rootCustomConfig.sh
}

getCoreVal() {
	jailScript=$1
	confVal=$2

	res1=$(cat $jailScript | grep "^$confVal")

	[ "$res1" = "" ] && return 1

	if printf "%s" "$res1" | grep -q "EOF"; then
		cat $jailScript | sed -ne "/^$confVal/ {s/.*//; be ; :e ; N; $ p; /EOF/ {s/EOF// ; p; b}; be}" | sed -e '/^$/ d'
	else
		printf "%s\n" "$res1" | sed -ne "/^$confVal=[^ ]\+/ {s/^[^=]*=\(.*\)$/\1/ ; p}" | sed -e 's/^"\(.*\)"$/\1/' | sed -e 's/^\x27\(.*\)\x27$/\1/'
	fi
}

getDefaultVal() {
	jailDir=$1
	confVal=$2

	getCoreVal $jailDir/rootDefaultConfig.sh $confVal
}

getCurVal() {
	jailDir=$1
	confVal=$2

	listConfigs $jailDir | grep -q "$confVal" || return 1

	getCoreVal $jailDir/rootCustomConfig.sh $confVal && return 0
	getCoreVal $jailDir/rootDefaultConfig.sh $confVal
}

setCoreVal() {
	jailScript=$1
	confVal=$2
	newVal=$(printf "%s" "$3" | sed -e 's/%20/ /g')

	listConfigs $jailDir | grep -q "$confVal" || return 1

	res1=$(cat $jailScript | grep "^$confVal")

	newVal="$(printf "%s" "$newVal" | sed -e 's/\//%2f/g' | sed -e ':e ; N ; $ {s/\n/%0a/g} ; be' | sed -e 's/^"\([^"]*\)"$/\1/' | sed -e "s/^'\([^']*\)'$/\1/")"

	if [ "$res1" = "" ]; then # if the configuration was not already present, we add it
		sed -e "s/$commandHeader/$confVal=\"$newVal\"\n\n$commandHeader/" -e 's/%2f/\//g' -i $jailScript
	else
		if echo $res1 | grep -q "EOF"; then
			sed -e "/^$confVal/ {s/.*// ; :e ; N; /EOF/ {s/.*/@CONFIG_CHANGE_ME@\\nEOF/ ; {:a ; N ; $ q; ba}}; be}" -i $jailScript
			sed -e "s/@CONFIG_CHANGE_ME@/$confVal=$\(cat << EOF\\n$newVal/" -e 's/%2f/\//g' -e 's/%0a/\n/g' -i $jailScript
		else
			sed -e "s/^\($confVal\)=.*$/\1=\"$newVal\"/" -e 's/%2f/\//g' -i $jailScript
		fi
	fi
}

setDefaultVal() { # this sets to default value
	jailDir=$1
	confVal=$2

	defVal=$(getDefaultVal $jailDir $confVal) || return 1

	setCoreVal $jailDir/rootCustomConfig.sh $confVal "$defVal"
}

setCustomVal() {
	jailDir=$1
	confVal=$2
	newVal=$3

	setCoreVal $jailDir/rootCustomConfig.sh $confVal "$newVal"
}

result=$(callGetopt "config [OPTIONS]" \
	-o "d" "default" "Get the default configuration value" "getDefaultVal" "false" \
	-o "g" "get" "Get configuration value" "getVal" "true" \
	-o "s" "set" "Set configuration value" "setVal" "true" \
	-o "l"  "list" "List configuration values" "listConf" "false" \
	-o '' '' "" "arg1Data" "true" \
	-- "$@")

if [ "$?" = "0" ]; then
	if getVarVal 'listConf' "$result" >/dev/null ; then
		listConfigs $jailDir
	elif getVarVal 'getVal' "$result" >/dev/null ; then
		curConf=$(getVarVal 'getVal' "$result")

		if getVarVal 'getDefaultVal' "$result" >/dev/null; then
			getDefaultVal $jailDir $curConf || (echo "Configuration does not seem to exist"; exit 1)
		else
			getCurVal $jailDir $curConf || (echo "Configuration does not seem to exist"; exit 1)
		fi

	elif getVarVal 'setVal' "$result" >/dev/null ; then
		curConf=$(getVarVal 'setVal' "$result")
		confVal=$(getVarVal 'arg1Data' "$result" | sed -e 's/^\x27\(.*\)\x27$/\1/' | sed -e 's/"/\x27/g' | sed -e 's/%3B/;/g')

		if getVarVal 'getDefaultVal' "$result" >/dev/null; then
			echo "Setting the config $curConf to default value"
			setDefaultVal $jailDir $curConf
		else
			if [ "$confVal" = "" ]; then
				echo "Invalid configuration value entered"
				exit 1
			else
				echo "Setting the config $curConf with value : $confVal"
				setCustomVal $jailDir $curConf "$confVal"
			fi
		fi
	fi
fi
