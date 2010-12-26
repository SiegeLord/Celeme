import pyceleme as pc
import numpy as np
import pylab as pl

model = pc.Model("stuff.cfg")

model.TimeStepSize = 1
model.Generate(True, True)

N = model["Regular"].Count
model.ApplyConnector("RandConn", N, "Regular", (0, N), 0, "Regular", (0, N), 0, {"P": 0.05})

vrec1 = model["Regular"].Record(1, "V")
vrec2 = model["Regular"].Record(2, "V")
vrec3 = model["Regular"].Record(3, "V")

model.ResetRun()
model.InitRun()
model.RunUntil(1000)

def arr(a):
	return np.array(a)

pl.figure()
pl.plot(arr(vrec1.T), arr(vrec1.Data))
pl.plot(arr(vrec2.T), arr(vrec2.Data))
pl.plot(arr(vrec3.T), arr(vrec3.Data))
pl.show()
