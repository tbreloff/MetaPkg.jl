using MetaPkg
using Base.Test

MetaPkg.dry_run()

# just check that they run without error
spec = MetaPkg.load_meta("MetaGL")
spec = MetaPkg.load_meta("MetaGL", Pkg.dir("MetaPkg","requires"))
meta_add("MetaGL")
meta_add("MetaGL", dir = Pkg.dir("MetaPkg","requires"))
meta_rm("MetaGL")
meta_free("MetaGL")
meta_checkout("MetaGL")
meta_checkout("MetaGL", "dev")
