import pyceleme as pc

model = pc.Model("stuff.xml")

model.TimeStepSize = 1
model.Generate(True, True)
