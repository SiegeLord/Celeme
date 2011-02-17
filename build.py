#!/usr/bin/python

from sys import argv
from subprocess import call
from string import join
from glob import glob

opencl_path = '/usr/local/atistream/lib/x86_64'
amd_perf_str = ''#'-d-version=AMDPerf -L-lGPUPerfAPICL'

def shell(cmd):
	return call(cmd, shell=True)

def dbuild():
	return shell('xfbuild +q +omain +cldc +xldc +xtango main.d -L -L' + opencl_path + ' -L -lOpenCL -L -lpthread -L -ldl -unittest ' + amd_perf_str)

if len(argv) > 1:
	if argv[1] == 'lib':
		# Stupid DMD bugs
		files = glob('celeme/*.d')
		files.sort()
		files.reverse()
		file_str = ' '.join(files);
		
		ret = shell('ldc -c ' + file_str +  ' opencl/*.d -od=".objs_celeme"')
		
		if ret == 0:
			ret = shell('ar -r libceleme.a .objs_celeme/*.o')
	elif argv[1] == 'py':
		shell('xfbuild +D=".deps_pyceleme" +O=".objs_pyceleme" +opy_celeme +cldc +xldc +xtango +xopencl +xceleme pyceleme/main.d -L -L' + opencl_path + ' -L -lOpenCL -L -lpthread -L -ldl -L-L. -L-lceleme -L-lpython2.6 -I. -unittest')
	elif argv[1] == 'doc':
		shell('dil d doc/ --kandil -hl celeme/*.d -version=Doc')
	elif argv[1] == 'run':
		ret = dbuild()
		if ret == 0:
			shell('./main ' + join(argv[2:], ' '))
	elif argv[1] == 'c':
		shell('gcc test.c -o test -L/usr/local/d/ -L. -lceleme -ltango_nomain -lm -ldl -lpthread -L' + opencl_path + ' -lOpenCL -std=c99')
else:
	dbuild()
