#! /bin/sh

getVersion() {
	git log --oneline --format=format:"%h%d" | awk '
{
	if ($0 ~ /tag/) {
		sub(/^.*tag: v/, "")
		sub(/(\)|,).*$/, "")
		print $0
		exit 0
	}
}
'
}

git show -s --oneline --format=format:"%h%d" HEAD | awk -v version=$(getVersion) '
{
	if ($0 ~ /tag/) {
		print version
	} else {
		print version "-" $1
	}
}'
