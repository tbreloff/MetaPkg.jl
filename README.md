# MetaPkg

A repository of meta-packages and tools to keep them up to date.

There is a common theme among organizations and individuals to have many related packages, all developed and maintained in parallel.  Currently, the workflow involves making changes, testing, iterating, and then finally tagging new versions in [METADATA](https://github.com/JuliaLang/METADATA.jl).

For any non-static projects (pretty much everything I do), the time between tags is prohibitively long, and people inevitably want to check out `master` or `dev` branches to get the latest features.  This would normally be fine, but when new features are added, they are frequently due to development in more than one package.  The current solutions:

- Don't use the new features, and wait for tagged releases
- Do `Pkg.checkout` on a package, witness breakage, post an issue or ask in gitter, check out more packages, continue...

This doesn't need to be so difficult, especially when the solution is usually to just run `Pkg.checkout` on a few repos.  Additionally, it becomes annoying to `Pkg.free` all the related packages properly after a tagged release.

## The MetaPkg solution

A meta-package has a list of requirements, which will be used to update a local directory in your `.julia` folder.  This allows `Pkg` to handle updating in a proper way once your preferred versions are checked out or freed.

As an example, we'll set up a new meta package for the GLVisualize ecosystem.  To stay flexible, we'll assume the filename is in a constant, fixed location: `filename`:

```julia
julia 0.5
    tagged:
        Contour
    branch:
        GLPlot
        GLWindow
        GLAbstraction
        GLVisualize
        GeometryTypes
        FixedSizeArrays
        FreeType
        Reactive {master => sd/betterstop}
```

There are a few things to note about the format:

- We can have a separate section for each julia version
- The `tagged` section is for packages which we won't checkout... they stay on tagged releases.
- The `branch` section will track those packages all on the same branch, doing a `Pkg.checkout` all to the same branch.
- Mappings in `{...}` use alternate branches.  Use `{_ => mybranch}` to always checkout that branch.    

Now that the requirements are defined, we'll load this meta package:

```julia
import MetaPkg
MetaPkg.load_meta("MetaGL", filename)
```

Now use familiar `Pkg` commands: `checkout`, `free`, and `update`.  `MetaPkg` will make the appropriate calls to `Pkg` given your meta-spec.
