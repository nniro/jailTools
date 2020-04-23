#! /bin/sh

# detects if the path as argument contains a valid jail
detectJail() {
	local jPath=$1
	if [ -d $jPath/root ] && [ -d $jPath/run ] && [ -f $jPath/startRoot.sh ] && [ -f $jPath/rootCustomConfig.sh ]; then
		return 0
	else
		return 1
	fi
}

# substring offset <optional length> string
# cuts a string at the starting offset and wanted length.
substring() {
        local init=$1; shift
        if [ "$2" != "" ]; then toFetch="\(.\{$1\}\).*"; shift; else local toFetch="\(.*\)"; fi
        echo "$1" | sed -e "s/^.\{$init\}$toFetch$/\1/"
}

# arguments : <input file> [<to replace string> <replacement string>, ...]
populateFile() {
	local inFile=$1
	shift
	local result=""

	while [ "$1" != "" ] && [ "$2" != "" ]; do
		result="$result s%$1$%$2%g;"
		shift 2
	done

	cat $inFile | sed -e "$result"
}
