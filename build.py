#!/usr/bin/python

from sys import argv
from subprocess import call
from string import join
from glob import glob
from os import remove

def rm(file_list):
	for s in file_list:
		remove(s)
		
def shell(cmd):
	return call(cmd, shell=True)

opencl_path = '/usr/local/atistream/lib/x86_64'
perf_str = '-d-version=Perf'
perf_str = ''

celeme_objs_nocl = glob("celeme/*.d") + glob("celeme/internal/*.d")
celeme_objs = celeme_objs_nocl + glob("opencl/*.d")

def _dbuild():
	ret = shell('xfbuild +threads=6 +q +omain +cldc +xldc +xtango main.d -g -L -L' + opencl_path + ' -L -lOpenCL -L -lpthread -L -ldl -unittest ' + perf_str)
	rm(glob("*.rsp"))
	return ret
	
def run():
	ret = _dbuild()
	if ret == 0:
		shell('./main ' + join(argv[2:]))

def lib():
	ret = shell('ldc -c ' + join(celeme_objs) + ' -od=".objs_celeme"')
	if ret == 0:
		ret = shell('ar -r libceleme.a ' + join(glob(".objs_celeme/*.o")))

def py():
	shell('xfbuild +threads=6 +D=".deps_pyceleme" +O=".objs_pyceleme" +opy_celeme +cldc +xldc +xtango +xopencl +xceleme pyceleme/main.d -L -L' + opencl_path + ' -L -lOpenCL -L -lpthread -L -ldl -L-L. -L-lceleme -L-lpython2.6 -I. -unittest')
	rm(glob("*.rsp"))

def doc():
	shell('dil d doc/ --kandil -hl ' + join(celeme_objs_nocl) + ' -version=Doc')

def c():
	shell('gcc test.c -o test -L/usr/local/d/ -L. -lceleme -ltango_nomain -lm -ldl -lpthread -L' + opencl_path + ' -lOpenCL -std=c99')

def clean():
	rm(glob(".objs/*.o"))
	_dbuild()

if len(argv) > 1:
	try:
		globals()[argv[1]]();
	except KeyError:
		print "Invalid option: " + argv[1]
else:
	_dbuild()
