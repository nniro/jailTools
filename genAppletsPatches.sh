#! /bin/sh

for s in $(cd applets 2>/dev/null && ls *.sh); do
	(cd applets; sh $s) | (cd busybox; git apply 2>/dev/null; exit 0)
done
