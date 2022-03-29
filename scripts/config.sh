#! /bin/sh

bb="$BB"
shower="$JT_SHOWER"
runner="$JT_RUNNER"

eval "$($shower jt_utils)"

listCore() {
	jailScript=$1

	$bb cat $jailScript | $bb sed -ne 's/^\([^# =]\+\)=.*$/\1/ p'
}

listConfigs() {
	jailDir=$1

	listCore $jailDir/rootDefaultConfig.sh
	listCore $jailDir/rootCustomConfig.sh
}

getCoreVal() {
	jailScript=$1
	confVal=$2

	res1=$($bb grep "^$confVal" $jailScript)

	[ "$res1" = "" ] && return 1

	if $bb printf "%s" "$res1" | $bb grep -q "EOF"; then
		$bb cat $jailScript \
			| $bb sed -ne "/^$confVal/ { s/.*// ; be ; :e ; N; $ p; /EOF/ { s/EOF// ; p; b; } ; be; }" \
			| $bb sed -e '/^$/ d'
	else
		$bb printf "%s\n" "$res1" \
			| $bb sed -ne "/^$confVal=[^ ]\+/ { s/^[^=]*=\(.*\)$/\1/ ; p; }" \
			| $bb sed -e 's/^"\(.*\)"$/\1/' \
				-e 's/^\x27\(.*\)\x27$/\1/' \
				-e 's/\$/\\\$/g'
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

	listConfigs $jailDir | $bb grep -q "$confVal" || return 1

	getCoreVal $jailDir/rootCustomConfig.sh $confVal && return 0
	getCoreVal $jailDir/rootDefaultConfig.sh $confVal
}

setCoreVal() {
	jailScript=$1
	confVal=$2
	newVal=$($bb printf "%s" "$3" | $bb sed -e 's/%20/ /g')

	listConfigs $jailDir | $bb grep -q "$confVal" || return 1

	res1=$($bb grep "^$confVal" $jailScript)

	newVal="$($bb printf "%s" "$newVal" \
		| $bb sed -e 's/\//%2f/g' \
			-e ':e ; N ; $ { s/\n/%0a/g ; } ; be' \
			-e 's/^"\([^"]*\)"$/\1/' \
			-e "s/^'\([^']*\)'$/\1/")"

	if [ "$res1" = "" ]; then # if the configuration was not already present, we add it
		$bb sed -e "s/$commandHeader/$confVal=\"$newVal\"\n\n$commandHeader/" \
			-e 's/%2f/\//g' \
			-i $jailScript
	else
		if echo $res1 | $bb grep -q "EOF"; then
			$bb sed -e "/^$confVal/ { s/.*// ; :e ; N; /EOF/ { s/.*/@CONFIG_CHANGE_ME@\\nEOF/ ; { :a ; N ; $ q; ba; }}; be; }" -i $jailScript
			$bb sed -e "s/@CONFIG_CHANGE_ME@/$confVal=$\(cat << EOF\\n$newVal/" -e 's/%2f/\//g' -e 's/%0a/\n/g' -i $jailScript
		else
			$bb sed -e "s/^\($confVal\)=.*$/\1=\"$newVal\"/" -e 's/%2f/\//g' -i $jailScript
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

jailDir=$1
shift

if $bb cat $jailDir/rootCustomConfig.sh | $bb grep -q '^# Command part$'; then
	echo Please update your jail before you can use this command.
	exit 1
fi

commandHeader='################# Command part #################'
if $bb cat $jailDir/rootCustomConfig.sh | $bb grep -q "^$commandHeader$"; then
	:
else
	echo "There has been a modification to your rootCustomConfig.sh file that makes this functionality unable to do it's job"
	echo "Please don't remove or modify the section headers. They are used by this tool"
	exit 1
fi

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
		sQuote=$($bb printf "\x27")
		confVal=$(getVarVal 'arg1Data' "$result" \
			| $bb sed -e "s/^$sQuote\(.*\)$sQuote$/\1/" \
				-e "s/\"/$sQuote/g" \
				-e 's/%3B/;/g')

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
