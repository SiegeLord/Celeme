var g_moduleList = [
  "celeme.capi", "celeme.celeme", "celeme.celeme_util", "celeme.config",
  "celeme.configloader", "celeme.imodel", "celeme.ineurongroup",
  "celeme.recorder", "celeme.internal.adaptiveheun",
  "celeme.internal.alignedarray", "celeme.internal.amdperf",
  "celeme.internal.clconnector", "celeme.internal.clcore",
  "celeme.internal.clmiscbuffers", "celeme.internal.clmodel",
  "celeme.internal.clneurongroup", "celeme.internal.clrand",
  "celeme.internal.frontend", "celeme.internal.heun",
  "celeme.internal.iclmodel", "celeme.internal.iclneurongroup",
  "celeme.internal.integrator", "celeme.internal.sourceconstructor",
  "celeme.internal.util",
];

var g_packageTree = new PackageTree(P('', [
  P('celeme',[
    P('celeme.internal',[
      M('celeme.internal.adaptiveheun'),
      M('celeme.internal.alignedarray'),
      M('celeme.internal.amdperf'),
      M('celeme.internal.clconnector'),
      M('celeme.internal.clcore'),
      M('celeme.internal.clmiscbuffers'),
      M('celeme.internal.clmodel'),
      M('celeme.internal.clneurongroup'),
      M('celeme.internal.clrand'),
      M('celeme.internal.frontend'),
      M('celeme.internal.heun'),
      M('celeme.internal.iclmodel'),
      M('celeme.internal.iclneurongroup'),
      M('celeme.internal.integrator'),
      M('celeme.internal.sourceconstructor'),
      M('celeme.internal.util'),
    ]),
    M('celeme.capi'),
    M('celeme.celeme'),
    M('celeme.celeme_util'),
    M('celeme.config'),
    M('celeme.configloader'),
    M('celeme.imodel'),
    M('celeme.ineurongroup'),
    M('celeme.recorder'),
  ]),
])
);

var g_creationTime = 1313206367;
