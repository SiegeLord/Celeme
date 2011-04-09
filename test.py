import pyceleme as pc
import numpy as np
import pylab as pl

model = pc.Model("stuff.cfg", False)

model.AddNeuronGroup("Regular", 1000);
model.TimeStepSize = 1
model.Generate(True, True)

N = model["Regular"].Count
model.ApplyConnector("RandConn", N, "Regular", (0, N), 0, "Regular", (0, N), 0, {"P": 0.05})

rec = model["Regular"].Record(0, 1)

model.ResetRun()
model.InitRun()
model.RunUntil(1000)

def arr(a):
	return np.array(a)

pl.figure()
pl.plot(arr(rec.T), arr(rec.Data))
pl.show()
