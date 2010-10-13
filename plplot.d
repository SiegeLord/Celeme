module plplot;

import tango.stdc.stringz;

extern (C)
{
	alias double PLFLT;
	alias int PLINT; 
	
	void c_plinit();
	
	void c_plenv( PLFLT xmin, PLFLT xmax, PLFLT ymin, PLFLT ymax, PLINT just, PLINT axis);
	
	void c_plline( PLINT n, PLFLT *x, PLFLT *y);
	
	void c_plpoin( PLINT n, PLFLT *x, PLFLT *y, PLINT code);
	
	void c_plsdev(char *devname);
	
	void c_plcol0(PLINT col);
	
	void c_plend();
	
	void c_pllab(char *xlabel, char *ylabel, char *tlabel);
	
	void c_plscolbg(PLINT r, PLINT g, PLINT b );
	void c_plscol0(PLINT idx, PLINT r, PLINT g, PLINT b );
}

void Init(char[] device, char[3] bg_color = [255,255,255])
{
	if(device)
		c_plsdev(toStringz(device));
	c_plscolbg(bg_color[0], bg_color[1], bg_color[2]);
	c_plinit();
}

void SetColor(int n, char[3] color)
{
	c_plscol0(n, color[0], color[1], color[2]);
}
void ChooseColor(int n)
{
	c_plcol0(n);
}

void SetEnvironment(PLFLT xmin, PLFLT xmax, PLFLT ymin, PLFLT ymax, PLINT just, PLINT axis)
{
	c_plenv(xmin, xmax, ymin, ymax, just, axis);
}

void SetLabels(char[] xlabel, char[] ylabel, char[] title)
{
	c_pllab(toStringz(xlabel), toStringz(ylabel), toStringz(title));
}

void PlotLine(PLFLT[] x, PLFLT[] y)
{
	assert(x.length == y.length);
	c_plline(x.length, x.ptr, y.ptr);
}

void PlotPoints(PLFLT[] x, PLFLT[] y, char symbol = '+')
{
	assert(x.length == y.length);
	c_plpoin(x.length, x.ptr, y.ptr, symbol);
}

void End()
{
	c_plend();
}
