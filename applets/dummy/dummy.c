/* vi: set sw=4 ts=4: */
/*
 * Mini mu implementation for busybox
 *
 * Copyright (C) [YEAR] by [YOUR NAME] <YOUR EMAIL>
 *
 * Licensed under GPLv2, see file LICENSE in this source tree.
 */

#include "libbb.h"

//config:config DUMMY
//config:	bool "DUMMY"
//config:	default n
//config:	help
//config:	  Returns an indeterminate value.

//kbuild:lib-$(CONFIG_DUMMY) += dummy.o
//applet:IF_DUMMY(APPLET(dummy, BB_DIR_USR_BIN, BB_SUID_DROP))

//usage:#define dummy_trivial_usage
//usage:	"[-abcde] FILE..."
//usage:#define dummy_full_usage
//usage:	"Returns an indeterminate value\n"
//usage:     "\n	-a	First function"
//usage:     "\n	-b	Second function"

int dummy_main(int argc, char **argv) MAIN_EXTERNALLY_VISIBLE;
int dummy_main(int argc, char **argv)
{
	int fd;
	ssize_t n;
	char mu;

	fd = xopen("/dev/random", O_RDONLY);

	if ((n = safe_read(fd, &mu, 1)) < 1)
		bb_perror_msg_and_die("/dev/random");

	return mu;
}
