#define _OW_SOURCE
#include <crypt.h>
#include <stdlib.h>
#include <stdio.h>

#include <string.h>

int main (int argc, char **argv)
{
	char *result;
	char *salt = NULL;

	if (argc < 2)
	{
		printf("Synopsis: %s (clear text password) [salt]\n", argv[0]);
		printf("Please input a clear text password and optionally a salt\n");
		return 1;
	}

	if (argc >= 3)
	{
		salt = malloc(strlen(argv[2]) + 4); /* ending NULL + $1$ */
		strncpy(salt, "$6$", 3);
		strncpy(&salt[3], argv[2], strlen(argv[2]) + 1);
	}
	else
	{
		salt = malloc(4); /* $1$ + \0 */
		strncpy(salt, "$6$", 4);
	}

	result = crypt(argv[1], salt);
	free(salt);

	if (result == NULL)
	{
		perror("crypt_rn");
		return 1;
	}

	printf("%s\n", result);
	
	return 0;
}
