#!/usr/bin/python

import sys
import os

os.system('xfbuild +omain +cldc +xldc +xtango *.d -L -L/usr/local/atistream/lib/x86_64 -L -lOpenCL -L -lpthread -L -ldl -unittest')

if (len(sys.argv) > 1):
	if sys.argv[1] == 'run':
		os.system('./main')
