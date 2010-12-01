//gcc test.c -o test -L/usr/local/d/ -L. -lceleme -ltango_nomain -lm -ldl -lpthread -L/usr/local/atistream/lib/x86_64 -lOpenCL

void celeme_init(void);
void celeme_test(void);

int main()
{
	celeme_init();
	celeme_test();
}
