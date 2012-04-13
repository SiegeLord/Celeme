# Celeme, an Open Source OpenCL neural simulator

By Pavel Sountsov

Celeme development is in rather early stages, but I am using it for my PhD research already. It currently can simulate multitudes of single compartmental neurons with adaptive time step (using the Heun method). Some documentation is in the doc/ subfolder.

Celeme is developed on Linux, and seems to work on Windows too. Celeme is also developed using AMD's OpenCL libraries, I do use some AMD specific extensions (that also exist for other implementations, but they are named differently) so for now AMD OpenCL is required.

## Compiling:

### General requirements:

Celeme core requires a D2 compiler and git trunk TangoD2 as well as AMD APP SDK. You can obtain the version of TangoD2 I use here: https://github.com/SiegeLord/Tango-D2 .
Celeme uses the DUtil utility modules that you can obtain here: https://github.com/SiegeLord/DUtil .
Plotting using the D binding requires gnuplot to be installed as well as the D bindings you can get here: https://github.com/SiegeLord/DGnuplot (you can just copy the gnuplot.d into root folder).

### Linux

You may want to edit the Makefile, changing the compiler and paths. By default it's set up to use the ldc2 compiler (https://github.com/ldc-developers/ldc).

Once that is done, run these commands from the command line:

    make     # Compile the D example
    make lib # Compile the libceleme.a static library

After building you can run the examples as follows:

    ./main   # Run the D example

### Windows

You may want to edit the Makefile.win, changing the compiler and paths. By default it's set up to use the dmd compiler. You will need an OpenCL import library which you can get here: https://github.com/Trass3r/cl4d/blob/master/OpenCL.lib .

Once that is done, run these commands from the command line:

    make -f Makefile.win     # Compile the D example
    make -f Makefile.win lib # Compile the libceleme.lib static library

After building you can run the examples as follows:

    main # Run the D example

## Licensing:

The code I wrote myself is under LGPL3.

OpenCL bindings came from cl4d @ https://github.com/Trass3r/cl4d

That's it for now. Again, many features are not yet implemented and there are probably tons of bugs. User friendliness is also rather low right now... if you're interested in helping out, contact me via this: http://slabode.exofire.net/contact_me.shtml
