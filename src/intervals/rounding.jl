# This file is part of the ValidatedNumerics.jl package; MIT licensed

# Rounding for rational intervals, e.g for sqrt of rational interval:
# Find the corresponding AbstractFloat type for a given rational type

Base.float{T}(::Type{Rational{T}}) = typeof(float(one(Rational{T})))

# better to just do the following ?
# Base.float(::Type{Rational{Int64}}) = Float64
# Base.float(::Type{Rational{BigInt}}) = BigFloat

# Use that type for rounding with rationals, e.g. for sqrt:

if VERSION < v"0.5.0-dev+1182"

    function Base.with_rounding{T}(f::Function, ::Type{Rational{T}},
        rounding_mode::RoundingMode)
        setrounding(f, float(Rational{T}), rounding_mode)
    end

else
    function Base.setrounding{T}(f::Function, ::Type{Rational{T}},
        rounding_mode::RoundingMode)
        setrounding(f, float(Rational{T}), rounding_mode)
    end
end


# Macros for directed rounding:

macro setrounding(T, expr, rounding_mode)
    quote
        setrounding($T, $rounding_mode) do
            $expr
        end
    end
end


doc"""The `@round` macro creates a rounded interval according to the current
interval rounding mode. It is the main function used to create intervals in the
library (e.g. when adding two intervals, etc.). It uses the interval rounding mode (see get_interval_rounding())"""
macro round(T, expr1, expr2)
    #@show "round", expr1, expr2
    quote
        mode = get_interval_rounding()

        if mode == :wide  #works with any rounding mode set, but the result will depend on the rounding mode
            # we assume RoundNearest
            Interval(prevfloat($expr1), nextfloat($expr2))

        else # mode == :narrow
            lo = @setrounding($T, $expr1, RoundDown)
            hi = @setrounding($T, $expr2, RoundUp)
            Interval(lo, hi)
        end
    end
end


doc"""`@thin_round` possibly saves one operation compared to `@round`."""
macro thin_round(T, expr)
    quote
        @round($T, $expr, $expr)
    end
end




doc"""`transform` transforms a string by applying the function `f` and type
`T` to each argument, i.e. `:(x+y)` is transformed to `:(f(T, x) + f(T, y))`
"""
transform(x, f, T) = :($f($(esc(T)), $(esc(x))))   # use if x is not an expression

function transform(expr::Expr, f::Symbol, T)

    if expr.head in ( :(.), :ref )   # of form  a.lo  or  a[i]
        return :($f($(esc(T)), $(esc(expr))))
    end

    new_expr = copy(expr)


    first = 1  # where to start processing arguments

    if expr.head == :call
        if expr.args[1] ∈ (:+, :-, :*, :/, :^)
            first = 2  # skip operator
        else   # escape standard function:
            new_expr.args[1] = :($(esc(expr.args[1])))
            first = 2
        end
    end

    if expr.head == :macrocall  # handles BigInts etc.
        return :($f($(esc(T)), $(esc(expr))))  # hack: pass straight through
    end

    for (i, arg) in enumerate(expr.args)
        i < first && continue
        #@show i,arg

        new_expr.args[i] = transform(arg, f, T)
    end

    return new_expr
end


# Called by interval and floatinterval macros
doc"""`make_interval` does the hard work of taking expressions
and making each literal (0.1, 1, etc.) into a corresponding interval construction,
by calling `transform`."""

function make_interval(T, expr1, expr2)
    expr1 = transform(expr1, :convert, :(Interval{$T}))

    if isempty(expr2)  # only one argument
        return expr1
    end

    expr2 = transform(expr2[1], :convert, :(Interval{$T}))

    :(hull($expr1, $expr2))
end


float(x::Interval) =
    # @round(BigFloat, convert(Float64, x.lo), convert(Float64, x.hi))
    convert(Interval{Float64}, x)

## Change type of interval rounding:


doc"""`get_interval_rounding()` returns the current interval rounding mode.
There are two possible rounding modes:

- :narrow  -- changes the floating-point rounding mode to `RoundUp` and `RoundDown`.
This gives the narrowest possible interval.

- :wide -- Leaves the floating-point rounding mode in `RoundNearest` and uses
`prevfloat` and `nextfloat` to achieve directed rounding. This creates an interval of width 2`eps`.
"""

get_interval_rounding() = parameters.rounding

function set_interval_rounding(mode)
    if mode ∉ [:wide, :narrow]
        throw(ArgumentError("Only possible interval rounding modes are `:wide` and `:narrow`"))
    end

    parameters.rounding = mode  # a symbol
end

big{T}(x::Interval{T}) = convert(Interval{BigFloat}, x)