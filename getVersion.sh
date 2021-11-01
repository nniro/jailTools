#! /bin/sh

getVersion() {
	git log --oneline --format=format:"%h%d" | busybox awk '
{
	if ($0 ~ /tag/) {
		print gensub(/^.*tag: v([^\),]*)(\)|,).*$/, "\\1", 1)
		exit 0
	}
}
'
}

git show -s --oneline --format=format:"%h%d" HEAD | busybox awk -v version=$(getVersion) '
{
	if ($0 ~ /tag/) {
		print version
	} else {
		print version "-" $1
	}
}'
