mechanism Izhikevich
{
	state V = -65;
	immutable V_tol = 0.2;
	state u = -5;
	immutable u_tol = 0.02;
	
	local I;
	
	threshold spike
	{
		state = V;
		condition = "> 0";
		code =
		"
			V = c;
			u += d;
			delay = axon_delay;
		";
		event_source = true;
		reset_dt = true;
	}
	
	stage0 =
	"
		I = 0;
	";
	stage2 =
	"
		V' = (0.04f * V + 5) * V + 140 - u + I;
		u' = a * (b * V - u);
	";
	
	immutable a = 0.01;
	immutable b = 0.2;
	immutable c = -65;
	immutable d = 2;
	immutable axon_delay = 5;
}
