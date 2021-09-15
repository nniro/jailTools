#! /bin/sh

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

. $(dirname $0)/scripts/utils.sh

if [ ! -e $(dirname $0)/scripts/paths.sh ]; then
	echo "Please compile jailTools first."
	exit 1
fi

. $(dirname $0)/scripts/paths.sh # set the bb variable

if [ ! -e $bb ]; then
	echo "Busybox not available, Please compile jailTools first."
	exit 1
fi

toEmbed() {
	embedTable=$($bb sed -e "s/^/scripts\//" << EOF
config.sh jt_config
cpDep.sh jt_cpDep
jailUpgrade.sh jt_upgrade
newJail.sh jt_new
utils.sh jt_utils
paths.sh jt_paths
jailLib.template.sh jt_jailLib_template
startRoot.template.sh jt_startRoot_template
filesystem.template.sh jt_filesystem_template
rootCustomConfig.template.sh jt_rootCustomConfig_template
rootDefaultConfig.template.sh jt_rootDefaultConfig_template
EOF
)

	filesToEmbed=$(printf "%s" "$embedTable" | $bb cut -d " " -f 1)

	sed -e 's/^@EOF$/EOF/' << EOF
$(cat $ownPath/scripts/jailtools.template.sh | sed -ne '/^@EMBEDDEDFILES_LOCATION@/ q; /^@EMBEDDEDFILES_LOCATION@/ ! p')

embedTable=\$(cat << EOF
$embedTable
@EOF
)

embeddedFiles=\$(cat << EOF
$(cd $ownPath; $bb tar -jcf - $filesToEmbed | base64)
@EOF
)

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

	\$bb echo "\$embeddedFiles" | \$bb base64 -d | \$bb tar -jxOf - \$path | \$bb sh -s \$args
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
		file=\$1
		path=""

		if showFile \$file; then
			:
		else
			echo "No such file." >&2
			exit 1
		fi

		exit 0
	;;

	--run)
		file=\$1
		path=""
		shift

		if runFile \$file \$@; then
			:
		else
			echo "No such file." >&2
			exit 1
		fi

		exit 0
	;;
esac

$(cat $ownPath/scripts/jailtools.template.sh | sed -ne '/^@EMBEDDEDFILES_LOCATION@/ {s/.*// ; :e ; $ {p; q}; N; be}')
EOF

}

if [ "$1" != "" ]; then
	if [ ! -d $1 ]; then
		echo "Please ensure the path is a directory and is writable"
		exit 1
	else
		scriptsDir=$ownPath

		if [ "$(echo $scriptsDir | $bb sed -e 's/^\(.\).*$/\1/')" != "/" ]; then # if the directory is not an absolute path, we use PWD
			scriptsDir=$PWD/$ownPath
		fi

		if [ "$2" = "" ]; then
			# we change the internal path to the path where this script is
			cp $ownPath/build/busybox/busybox $1/jt
			chmod u+x $1/jt
			echo "Done. Installed \`jt' in $1"
		else # this is when jailtools is embedded in busybox
			toEmbed | $bb sed -e "s%@SCRIPT_PATH@%.%" > $1/$2
		fi
	fi
else
	echo "Please input a directory where you want to install the \`jailtools' master script"
	echo "Note that only that script is installed (along with the \`jt' and \`jtools' symlinks). It finds the other scripts by reference."
	exit 1
fi
