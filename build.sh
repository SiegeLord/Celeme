#!/bin/sh
xfbuild +omain +cldc +xldc +xtango *.d -L -L/usr/local/atistream/lib/x86_64 -L -lOpenCL -L -lpthread -L -ldl -unittest
if [ $1 = "run" -a $? -eq 0 ]; then
	./main
fi
