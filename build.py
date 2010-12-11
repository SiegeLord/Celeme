#!/usr/bin/python

import sys
from subprocess import call
from string import join
import glob

#ret = call('xfbuild +D=".deps_celeme" +O=".objs_celeme" +nolink +cldc +xldc +xtango celeme/ -unittest', shell=True)
#if ret == 0:
#	ret = call('ar -r libceleme.a .objs_celeme/*.o', shell=True)
#if ret == 0:
#	ret = call('xfbuild +omain +cldc +xldc +xtango +xceleme +xopencl main.d -L -L/usr/local/atistream/lib/x86_64 -L -lOpenCL -L -lpthread -L -ldl -L -L. -L -lceleme -unittest', shell=True)

if len(sys.argv) > 1:
	if sys.argv[1] == 'lib':
		files = glob.glob('celeme/*.d')
		files.sort()
		files.reverse()
		file_str = ' '.join(files);
		
		ret = call('ldc -c ' + file_str +  ' opencl/*.d gnuplot.d -od=".objs_celeme"', shell=True)
		
		if ret == 0:
			ret = call('ar -r libceleme.a .objs_celeme/*.o', shell=True)
	elif sys.argv[1] == 'py':
		ret = call('xfbuild +D=".deps_pyceleme" +O=".objs_pyceleme" +opy_celeme +cldc +xldc +xtango +xopencl +xceleme pyceleme/main.d -L -L/usr/local/atistream/lib/x86_64 -L -lOpenCL -L -lpthread -L -ldl -L-L. -L-lceleme -L-lpython2.6 -I. -unittest', shell=True)

if len(sys.argv) == 1 or (len(sys.argv) > 1 and sys.argv[1] == 'run'):
	ret = call('xfbuild +omain +cldc +xldc +xtango main.d -L -L/usr/local/atistream/lib/x86_64 -L -lOpenCL -L -lpthread -L -ldl -unittest', shell=True)
	

if ret == 0 and len(sys.argv) > 1:
	if sys.argv[1] == 'run':
		call('./main ' + join(sys.argv[2:], ' '), shell=True)
