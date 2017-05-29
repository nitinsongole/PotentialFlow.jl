"""
    @property kind name property_type

Macro to define common functions for computing vortex properties

`kind` can be one of:
- `induced`: when the property is induced by an external vortex source (e.g. velocity),
  the macro defines the following functions:
  ```julia
  allocate_<name>(target)
  induce_<name>(target, source)
  induce_<name>!(output, target source)
  ```
  where `source` can be
  - a single vortex element (e.g. a single point vortex)
  - a array of homogenous vortex elements (e.g. a group of point vortices)
  - a tuple of different vortex elements (e.g. a plate and two vortex sheets),
  `target` can be the same types as `source` as well as one or more positions,
  and `output` is the output array allocated by `allocate_<name>`
  The return type of `induce_<name>` will be `property_type`.
- `point`: when the property is pointwise defined (e.g. position),
  the macro defines a placeholder function
  ```julia
  function <name> end
  ```
  deferring the actual implementation to the indivual vortex types.
- `aggregate`: when the property can be summed over multiple elements (e.g. circulation),
  the macro defines
  ```julia
  <name>(source)
  ```

!!! note Why a macro?
    Originally, `induce_velocity` and friends were defined as regular
    functions.  However, computations of many other properties
    (e.g. complex potential, acceleration, etc.)  follow the same
    pattern of summing over sources and distributing over targets.
    Instead of writing separate code, it seems better to write one set
    of code that will work on all properties of this kind.  That way,
    defining new properties in the future will be eaiser, and we only
    have one set of bugs to fix.
"""
macro property(kind, name, prop_type)
    if kind == :point
        esc(quote
            function $name end
            end)
    elseif kind == :aggregate
        esc(quote
            $name(vs::Collection) = mapreduce($name, +, zero($prop_type), vs)
            end)
    elseif kind == :induced
        f_allocate = Symbol("allocate_$(lowercase(string(name)))")
        f_induce   = Symbol("induce_$(lowercase(string(name)))")
        f_induce!  = Symbol("induce_$(lowercase(string(name)))!")

        _f_allocate = Symbol("_allocate_$(lowercase(string(name)))")
        _f_induce   = Symbol("_induce_$(lowercase(string(name)))")
        _f_induce!  = Symbol("_induce_$(lowercase(string(name)))!")

        esc(quote
            $f_allocate(group::Tuple) = map($f_allocate, group)
            $f_allocate(targ) = $_f_allocate(unwrap_targ(targ), kind(eltype(unwrap_targ(targ))))
            $_f_allocate(targ, el::Type{Singleton}) = zeros($prop_type, size(targ))

            function $f_induce(targ, src)
                $_f_induce(unwrap_targ(targ), unwrap_src(src), kind(unwrap_targ(targ)), kind(unwrap_src(src)))
            end
            function $f_induce!(out, targ, src)
                $_f_induce!(out, unwrap_targ(targ), unwrap_src(src), kind(unwrap_targ(targ)), kind(unwrap_src(src)))
            end

            function $_f_induce(targ, src, ::Type{Singleton}, ::Type{Singleton})
                $f_induce(Vortex.position(targ), src)
            end

            function $_f_induce(targ, src, ::Type{Singleton}, ::Type{Group})
                w = zero($prop_type)
                for s in src
                    w += $f_induce(targ, s)
                end
                w
            end

            function $_f_induce(targ, src, ::Type{Group}, ::Any)
                out = $f_allocate(targ)
                $f_induce!(out, targ, src)
            end

            function $_f_induce!(out, targ, src, ::Type{Group}, ::Any)
                for i in eachindex(targ)
                    out[i] += $f_induce(targ[i], src)
                end
                out
            end

            function $f_induce!(out::Tuple, targ::Tuple, src)
                for i in eachindex(targ)
                    $f_induce!(out[i], targ[i], src)
                end
                out
            end
            end)
    else
        throw(ArgumentError("first argument must be `:induced`, `:point` or `:aggregate`"))
    end
end
