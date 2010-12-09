import pyceleme as pc

model = pc.Model("stuff.xml")

model.TimeStepSize = 1
model.Generate(True, True)

N = 10
model.ApplyConnector("RandConn", N, "Regular", (0, N), 0, "Regular", (0, N), 0, {"P": 0.05})
