#! /bin/sh

# this script prepares the 'jt' superscript before it is embedded into busybox.
# It encodes all the scripts of the jailTools project into itself and adds
# means to '--show' and '--run' them.

# this is an internal script, please don't use it

case "$(readlink -f /proc/$$/exe)" in
	*busybox)
		sh="$(readlink -f /proc/$$/exe) sh"
		echo "using shell : $sh"
	;;

	*)
		sh="$(readlink -f /proc/$$/exe)"
		echo "using shell : $sh"
	;;
esac

ownPath=$(dirname $0)

# convert the path of this script to an absolute path
if [ "$ownPath" = "." ]; then
	ownPath=$PWD
else
	if echo $ownPath | grep -q '^\/'; then
		# absolute path, we do nothing
		:
	else
		# relative path
		ownPath=$PWD/$ownPath
	fi
fi

toEmbed() {
	embedTable=$($bb sed -e "s/^/scripts\//" << EOF
config.sh jt_config
readElf.sh jt_readElf
cpDep.sh jt_cpDep
jailUpgrade.sh jt_upgrade
newJail.sh jt_new
utils.sh jt_utils
jailLib.template.sh jt_jailLib_template
startRoot.template.sh jt_startRoot_template
filesystem.template.sh jt_filesystem_template
firewall.template.sh jt_firewall
rootCustomConfig.template.sh jt_rootCustomConfig_template
rootDefaultConfig.template.sh jt_rootDefaultConfig_template
EOF
)

	filesToEmbed=$(printf "%s" "$embedTable" | $bb cut -d " " -f 1)

	sed -e 's/^@EOF$/EOF/' << EOF
$(cat $ownPath/scripts/jailtools.template.sh | sed -ne "s/\(JT_VERSION=\).*$/\1\"$(sh getVersion.sh)\"/" -e '/^@EMBEDDEDFILES_LOCATION@/ q; /^@EMBEDDEDFILES_LOCATION@/ ! p')

embedTable=\$(\$bb cat << EOF
$embedTable
@EOF
)

embeddedFiles=\$(\$bb cat << EOF
$(cd $ownPath; $bb tar -jcf - $filesToEmbed | $bb base64)
@EOF
)

existsFile() {
	file=\$1

	IFS="
"
	for st in \$embedTable; do
		IFS=" "
		set -- \$st

		if [ "\$file" = "\$2" ]; then
			return 0
		fi
	done

	return 1
}

runFile() {
	file=\$1
	path=""
	shift
	args="\$@"

	IFS="
"
	for st in \$embedTable; do
		IFS=" "
		set -- \$st

		if [ "\$file" = "\$2" ]; then
			path=\$1
			break
		fi
	done

	if [ "\$path" = "" ]; then
		return 1
	fi

	\$bb echo "\$embeddedFiles" | \$bb base64 -d | \$bb tar -jxOf - \$path | \$bb env IS_RUNNING=1 \$bb sh -s -- \$args
	return \$?
}

showFile() {
	file=\$1
	path=""

	IFS="
"
	for st in \$embedTable; do
		IFS=" "
		set -- \$st

		if [ "\$file" = "\$2" ]; then
			path=\$1
			break
		fi
	done

	if [ "\$path" = "" ]; then
		return 1
	fi

	\$bb echo "\$embeddedFiles" | \$bb base64 -d | \$bb tar -jxOf - \$path
	return 0
}

case \$cmd in
	"--show")
		file="\$1"
		path=""

		if ! existsFile \$file; then
			echo "No such file." >&2
			exit 1
		fi

		showFile \$file

		exit 0
	;;

	--run)
		file="\$1"
		path=""
		shift

		if ! existsFile \$file; then
			echo "No such file." >&2
			exit 1
		fi

		runFile "\$file" "\$@"

		exit \$?
	;;
esac

$(cat $ownPath/scripts/utils.sh)

$(cat $ownPath/scripts/jailtools.template.sh | sed -ne '/^@EMBEDDEDFILES_LOCATION@/ { s/.*// ; :e ; $ { p; q }; N; be }')
EOF
}

if [ "$1" != "" ] && [ "$2" != "" ]; then
	toEmbed | $bb sed -e "s%@SCRIPT_PATH@%.%" > $1/$2
	exit 0
else
	echo "This is an internal only script, please don't use it."
	exit 1
fi
