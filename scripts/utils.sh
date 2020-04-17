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
