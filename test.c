//gcc test.c -o test -L/usr/local/d/ -L. -lceleme -ltango_nomain -lm -ldl -lpthread -L/usr/local/atistream/lib/x86_64 -lOpenCL -std=c99
#include "celeme/celeme.h"
#include "stdio.h"

int main()
{
	const char* error;
	#define CHECK if(error = celeme_get_error()) goto ERROR;
	
	celeme_init();
	
	CELEME_MODEL model = celeme_load_model("stuff.xml"); CHECK;
	
	CELEME_NEURON_GROUP group = celeme_get_neuron_group(model, "Regular"); CHECK;
	
	printf("%d\n", group);
	int N = celeme_get_count(group); CHECK;
	
	celeme_generate_model(model, true, true, true); CHECK;
	
	char* arg_keys[] = {"P"};
	double arg_vals[] = {0.05};
	
	celeme_apply_connector(model, "RandConn", N, "Regular", 0, N, 0, "Regular", 0, N, 0, 1, arg_keys, arg_vals); CHECK;
	
	int tstop = 1000;
	
	CELEME_RECORDER rec = celeme_record(celeme_get_neuron_group(model, "Regular"), 0, "V");
	
	celeme_reset_run(model);
	celeme_init_run(model);
	celeme_run_until(model, 50);
	celeme_run_until(model, tstop + 1);
	
	size_t len = celeme_get_recorder_length(rec);
	printf("Len: %zu\n", len);
	
	double* t = celeme_get_recorder_time(rec);
	double* v = celeme_get_recorder_data(rec);
	
	for(int ii = 0; ii < len; ii++)
	{
		printf("%f\t%f\n", t[ii], v[ii]);
	}
	
	return 0;
ERROR:
	printf("Error: %s\n", error);
	return -1;
}
