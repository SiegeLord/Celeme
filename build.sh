#!/bin/sh
xfbuild +omain +cldc +xldc +xtango *.d -O5 -L -L/usr/local/atistream/lib/x86_64 -L -lOpenCL -L -lpthread -L -ldl -unittest -L -lplplotd
