#include <linux/capability.h>
#include <sys/prctl.h>
#include <unistd.h>
#include <string.h>

#include <stdlib.h>
#include <stdio.h>
#include <errno.h>

#include <seccomp.h>

#include "muzzler.h"
#include "version.h"

void
applyPreset(const Preset *link, int mode) {
	for (int i=0; i < link->syscallCount; i++)
		syscallState[link->syscalls[i].index] = mode;

	for (int i=0; i < link->presetCount; i++)
		applyPreset(link->presets[i], mode);
}

int
parseArg(char *input) {
	int mode = 0;
	switch (input[0]) {
		case '+':
			mode = 1;
		break;

		case '-':
			mode = 2;
		break;

		default:
			return 1;
		break;
	}

	input++;
	{
		int availPresetsCount = sizeof(availSyscallPresets) / sizeof(Preset*);

		/* all */
		if (!strncmp("all", input, 3)) {
			for (int i=0; i < availPresetsCount; i++) {
				const Preset *link = availSyscallPresets[i];
				for (int t=0; t < link->syscallCount; t++)
					syscallState[link->syscalls[t].index] = mode;
			}

			return 0;
		}

		/* presets */
		for (int i=0; i < availPresetsCount; i++) {
			const Preset *link = availSyscallPresets[i];
			if (!strncmp(link->name, input, strlen(link->name))) {
				applyPreset(link, mode);
				return 0;
			}
		}

		/* syscalls */
		{
			int syscallListCount = sizeof(syscallList) / sizeof(Syscall);
			for (int i=0; i < syscallListCount; i++) {
				if (!strncmp(syscallList[i].name, input, strlen(syscallList[i].name))) {
					syscallState[syscallList[i].index] = mode;
					return 0;
				}
			}
		}
	}

	return 1;
}

void
showHelp(char *progName) {
	printf("\nThis tool limits the syscalls that a given program can use.\n\n");
	printf("Usage: %s [-hebypv] [-i <preset>] [-s <filter rules>] Program [Arguments...] \n\
	-h 			This help message\n\
	-e			Carry on the enviroment variables to the program. Default is to purge the environment\n\
	-b			Use a blacklist method rather than the default whitelist\n\
	-s <filter rules>	Set the seccomp filter rules. (Presets and direct syscalls are possible) +/- prefix mandatory. Example : -s -all,+default\n\
	-y			Print all available syscalls\n\
	-p 			Print all available presets\n\
	-i <preset>		Print information on the given preset\n\
	-v			Print the version of this program\n\
\n"
	, progName);
}

int main(int argc, char **argv) {
	int cmdIndex = -1;
	char *elem;
	int _err = 0;
	int opt;
	int withEnvironment = 0;
	int withBlacklist = 0;

	if ( argc == 1) {
		showHelp(argv[0]);
		return 1;
	}

	while ((opt = getopt(argc, argv, "hebypvs:i:")) != -1) {
		switch (opt) {
			case 'h':
				showHelp(argv[0]);
				return 0;
			break;
			case 'v':
				printf("%s : version %s\n", argv[0], VERSION);
				return 0;
			break;
			case 'e':
				withEnvironment = 1;
			break;
			case 'b':
				withBlacklist = 1;
			break;
			case 'y':
				printf("Available syscalls : \n");
				{
					int syscallListCount = sizeof(syscallList) / sizeof(Syscall);
					for (int i=0; i < syscallListCount; i++) {
						printf("%s ", syscallList[i].name);
					}
					printf("\n");
				}
				return 0;
			break;
			case 'p':
				printf("Available presets : \n");
				{
					int availPresetsCount = sizeof(availSyscallPresets) / sizeof(Preset*);
					for (int i=0; i < availPresetsCount; i++) {
						const Preset *link = availSyscallPresets[i];
						printf("%s ", link->name);
					}
					printf("\n");
				}
				return 0;
			break;
			case 'i':
				{
					int availPresetsCount = sizeof(availSyscallPresets) / sizeof(Preset*);
					for (int i=0; i < availPresetsCount; i++) {
						const Preset *link = availSyscallPresets[i];
						if (!strncmp(link->name, optarg, strlen(link->name))) {
							printf("Content of the preset %s:\n\n", link->name);

							if (!link->syscallCount && !link->presetCount) {
								printf("\tThis preset is empty\n");
								return 0;
							}

							if (link->syscallCount) {
								printf("Syscalls : \n\t");
								for (int i=0; i < link->syscallCount; i++)
									printf("%s ", link->syscalls[i].name);
								printf("\n\n");
							}


							if (link->presetCount) {
								printf("Linked presets : \n\t");
								for (int i=0; i < link->presetCount; i++)
									printf("%s ", link->presets[i]->name);
								printf("\n\n");
							}

							return 0;
						}
					}
					printf("Given preset doesn't exist\n");
					return 1;
				}
				return 0;
			break;
			case 's':
				elem = realloc(NULL, strlen(optarg) + 1);
				strncpy(elem, optarg, strlen(optarg) + 1);

				elem = strtok(elem, ",");
				while (elem) {
					_err = parseArg(elem);
					if (_err)
						break;

					elem = strtok(NULL, ",");
				}

				free(elem);
				elem = NULL;
			break;
			default:
				printf("\nInvalid argument used\n\n");
				showHelp(argv[0]);
				return 1;
			break;
		}
	}

	if (_err) {
		printf("An error occured\n");
		return _err;
	} else {
#if debug
		for (int i = 0; i < (sizeof(syscallState) / sizeof(char)); i++) {
			switch (syscallState[i]) {
				case 0:
				break;

				case 1:
					printf("Add %d\n", i);
				break;

				case 2:
					printf("Forbid %d\n", i);
				break;

				default:
				break;
			}
		}
#endif /* debug */
	}

	if (argc <= optind) {
		printf("\nPlease supply the program to run with the limited seccomp rules\n\n");

		showHelp(argv[0]);
		return 1;
	}

	cmdIndex = optind;
	{
		char *baseName = strrchr(argv[cmdIndex], '/');
		char **newArgv = NULL;
		int argvIdx = 0;

		if (baseName)
			baseName = &baseName[1];
		else
			baseName = argv[cmdIndex];

		{
			scmp_filter_ctx ctx;
			int rc;

			if (withBlacklist) {
				ctx = seccomp_init(SCMP_ACT_ALLOW);
			} else {
				ctx = seccomp_init(SCMP_ACT_ERRNO(EPERM));
			}
			/* some systems can run many kinds of architecture at once, here's a few notable ones. */
			switch (seccomp_arch_native()) {
				case SCMP_ARCH_AARCH64:
					seccomp_arch_add(ctx, SCMP_ARCH_ARM);
				break;

				case SCMP_ARCH_ARM:
					seccomp_arch_add(ctx, SCMP_ARCH_AARCH64);
				break;

				case SCMP_ARCH_X86:
					seccomp_arch_add(ctx, SCMP_ARCH_X86_64);
				break;
					
				case SCMP_ARCH_X86_64:
					seccomp_arch_add(ctx, SCMP_ARCH_X86);
				break;

				default:
				break;
			}

			for (int i = 0; i < (sizeof(syscallState) / sizeof(char)); i++) {
				switch (syscallState[i]) {
					case 0:
					break;

					case 1:
						seccomp_rule_add(ctx, SCMP_ACT_ALLOW, i, 0);
					break;

					case 2:
						seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), i, 0);
					break;

					default:
					break;
				}
			}

			rc = seccomp_load(ctx);

			if (rc < 0) {
				printf("Unable to load seccomp rules into the kernel\n");
				seccomp_release(ctx);
				return 1;
			}

			seccomp_release(ctx);
		}

		newArgv = realloc(newArgv, sizeof(char *) * (argvIdx + 1));
		newArgv[argvIdx++] = baseName;

		for (int i = cmdIndex + 1; i < argc; i++) {
			newArgv = realloc(newArgv, sizeof(char *) * (argvIdx + 1));
			newArgv[argvIdx++] = argv[i];
		}

		newArgv = realloc(newArgv, sizeof(char *) * (argvIdx + 1));
		newArgv[argvIdx++] = NULL;

		if (withEnvironment) { /* preserve the env variables */
			_err = execvp(argv[cmdIndex], newArgv);
		} else { /* purge the env variables */
			char *emptyArray[] = {NULL};
			_err = execvpe(argv[cmdIndex], newArgv, emptyArray);
		}

		free(newArgv);
	}

	return _err;
}
