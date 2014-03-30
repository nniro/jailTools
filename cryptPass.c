#define _OW_SOURCE
#include <crypt.h>
#include <stdlib.h>
#include <stdio.h>

#include <string.h>

#define DATASIZE 32768

int main (int argc, char **argv)
{
	char *result;
	void *eData = NULL;
	int eSize = 0;
	char *salt = NULL;

	if (argc < 2)
	{
		printf("Synopsis: %s (clear text password) [salt]\n", argv[0]);
		printf("Please input a clear text password and optionally a salt\n");
		return 1;
	}

	/*eData = malloc(DATASIZE);*/

	if (argc >= 3)
	{
		salt = malloc(strlen(argv[2]) + 4); /* ending NULL + $1$ */
		strncpy(salt, "$6$", 3);
		strncpy(&salt[3], argv[2], strlen(argv[2]) + 1);
	}
	else
	{
		salt = malloc(4); /* $1$ + \0 */
		/* strncpy(salt, "$1$", 4);*/
		strncpy(salt, "$6$", 4);
	}

	/*result = crypt_r(argv[1], salt, &eData, &eSize);*/
	/*result = crypt_rn(argv[1], salt, eData, DATASIZE);*/
	result = crypt(argv[1], salt);
	free(salt);
	/*free(eData);*/

	if (result == NULL)
	{
		perror("crypt_rn");
		return 1;
	}

	printf("%s\n", result);
	
	return 0;
}
