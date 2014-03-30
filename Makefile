#! /bin/bash

BINARY=cryptPass
OBJECTS=cryptPass.o
CFLAGS=-O2 -pedantic -Wall -std=iso9899:1990
LIBS=-lcrypt
LDFLAGS=

ALL=$(BINARY)
	

$(BINARY): $(OBJECTS)
	gcc $(CFLAGS) $(LDFLAGS) $(LIBS) $(OBJECTS) -o $(BINARY)

%.o: %.c
	gcc $(CFLAGS) -c $<

clean:
	rm -f $(BINARY) *.o
