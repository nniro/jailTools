#! /bin/sh

getVersion() {
	git log --oneline --format=format:"%h%d" HEAD | busybox awk '
{
	if ($2 == "(tag:") {
		a = $3
		sub(/^v/, "", a)
		sub(/)$/g, "", a)
		print a
		exit 0
	}
}
'
}

git show -s --oneline --format=format:"%h%d" HEAD | busybox awk -v version=$(getVersion) '
{
	if ($2 == "(tag:") {
		print version
	} else {
		print version "-" $1
	}
}'
