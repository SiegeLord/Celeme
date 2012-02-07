# General configuration
DC                 := ldc2
DC_NAME            := ldc
D_FLAGS            := -unittest -w -wi -property
INSTALL_PREFIX     := /usr/local
#PERF_STR          := -d-version=Perf
PERF_STR           := 

# Dependencies
OPENCL_PATH        := /usr/local/amdapp/lib/x86_64
DUTIL_PATH         := /usr/local/include/d
DUTIL_FILES        := $(DUTIL_PATH)/dutil/General.d $(DUTIL_PATH)/dutil/Disposable.d
DGNUPLOT_PATH      := /usr/local/include/d
DGNUPLOT_FILES     := $(DGNUPLOT_PATH)/gnuplot.d
TANGO_LDFLAGS      := -L-ltango-$(DC_NAME)
LD_FLAGS           := -L-L$(OPENCL_PATH) -L-lOpenCL -L-lpthread -L-ldl $(TANGO_LDFLAGS) 

# Components
CELEME_FILES_NO_CL := $(wildcard celeme/*.d) $(wildcard celeme/internal/*.d)
CELEME_FILES       := $(CELEME_FILES_NO_CL) $(wildcard opencl/*.d)
D_EXAMPLE_NAME     := main
D_EXAMPLE_FILES    := main.d $(CELEME_FILES)
LIBRARY_NAME       := libceleme.a
C_EXAMPLE_NAME     := test
C_EXAMPLE_FILES    := test.c
PYCELEME_NAME      := py_celeme
PYCELEME_FILES     := $(wildcard pyceleme/*.d)
PYTHON_FILES       := python/python.d

# xfbuild specific
XFBUILD         := $(shell which xfbuild)

# Compiles a D program
# $1 - program name
# $2 - program files
# $3 - extra compiler flags
ifeq ($(XFBUILD),)
    define d_build
        $(DC) -of$1 -od=".objs_$1" $(D_FLAGS) $2 $3
    endef
else
    define d_build
        $(XFBUILD) +D=".deps_$1" +O=".objs_$1" +threads=6 +q +o$1 +c$(DC) +x$(DC_NAME) +xcore +xtango $2 $(D_FLAGS) $3
        rm -f *.rsp
    endef
endif

.PHONY : all
all : $(D_EXAMPLE_NAME)

.PHONY : lib
lib : $(LIBRARY_NAME)

.PHONY : c
c : $(C_EXAMPLE_NAME)

.PHONY : py
py : $(PYCELEME_NAME)

.PHONY : doc
doc : 
	dil d doc/ --kandil -hl $(CELEME_FILES_NO_CL) -version=Doc

$(D_EXAMPLE_NAME) : $(D_EXAMPLE_FILES)
	$(call d_build,$(D_EXAMPLE_NAME),$(D_EXAMPLE_FILES) $(DUTIL_FILES) $(DGNUPLOT_FILES), $(LD_FLAGS))

$(LIBRARY_NAME) : $(CELEME_FILES)
	$(DC) -c $(CELEME_FILES) $(DUTIL_FILES) -od=".objs_celeme" $(D_FLAGS) $(PERF_STR)
	ar -r $(LIBRARY_NAME) .objs_celeme/*.o

$(C_EXAMPLE_NAME) : $(C_EXAMPLE_FILES) $(LIBRARY_NAME)
	gcc $(C_EXAMPLE_FILES) -o $(C_EXAMPLE_NAME) -L. -lceleme -ltango-ldc -ldruntime-ldc -lrt -lm -ldl -lpthread -L$(OPENCL_PATH) -lOpenCL -std=c99

$(PYCELEME_NAME) : $(PYCELEME_FILES) $(CELEME_FILES)
	$(call d_build,$(PYCELEME_NAME),$(PYCELEME_FILES) $(CELEME_FILES) $(DUTIL_FILES) $(PYTHON_FILES), $(LD_FLAGS) -L-lpython2.6 $(PERF_STR))

.PHONY : clean
clean :
	rm -f $(D_EXAMPLE_NAME) $(LIBRARY_NAME) $(C_EXAMPLE_NAME) $(PYCELEME_NAME) .deps*
	rm -rf .objs*
	rm -rf doc
	rm -f *.rsp
