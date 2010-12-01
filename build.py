#!/usr/bin/python

import sys
from subprocess import call
from string import join

#ret = call('xfbuild +D=".deps_celeme" +O=".objs_celeme" +nolink +cldc +xldc +xtango celeme/ -unittest', shell=True)
#if ret == 0:
#	ret = call('ar -r libceleme.a .objs_celeme/*.o', shell=True)
#if ret == 0:
#	ret = call('xfbuild +omain +cldc +xldc +xtango +xceleme +xopencl main.d -L -L/usr/local/atistream/lib/x86_64 -L -lOpenCL -L -lpthread -L -ldl -L -L. -L -lceleme -unittest', shell=True)

if len(sys.argv) > 1 and sys.argv[1] == 'lib':
	ret = call('ldc -c celeme/*.d opencl/*.d gnuplot.d -od=".objs_celeme"', shell=True)
	
	if ret == 0:
		ret = call('ar -r libceleme.a .objs_celeme/*.o', shell=True)
else:
	ret = call('xfbuild +omain +cldc +xldc +xtango main.d -L -L/usr/local/atistream/lib/x86_64 -L -lOpenCL -L -lpthread -L -ldl -unittest', shell=True)

if ret == 0 and len(sys.argv) > 1:
	if sys.argv[1] == 'run':
		call('./main ' + join(sys.argv[2:], ' '), shell=True)
