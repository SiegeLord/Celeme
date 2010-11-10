#!/usr/bin/python

import sys
from subprocess import call
from string import join

ret = call('xfbuild +omain +cldc +xldc +xtango main.d -L -L/usr/local/atistream/lib/x86_64 -L -lOpenCL -L -lpthread -L -ldl -unittest', shell=True)

if (ret == 0 and len(sys.argv) > 1):
	if sys.argv[1] == 'run':
		call('./main ' + join(sys.argv[2:], ' '), shell=True)
