export arguments, LogisticBinomial, HalfCauchy, args, stochastic, observed, parameters, rand

using MacroTools: striplines, flatten, unresolve, resyntax, @q
using MacroTools
using StatsFuns

function nobegin(ex)
    postwalk(ex) do x
        if @capture(x, begin body__ end)
            unblock(x)
        else
            x
        end
    end
end

pretty = striplines

function args(model)
    model.args.args
end

"A stochastic node is any `v` in a model with `v ~ ...`"
function stochastic(model)
    nodes :: Vector{Symbol} = []
    postwalk(model.body) do x
        if @capture(x, v_ ~ dist_)
            push!(nodes, v)
        else x 
        end
    end
    nodes
end

function parameters(model)
    nonpars = copy(args(model))
    pars :: Vector{Symbol} = []
    for line in model.body.args
        if @capture(line, v_ = ex_)
            push!(nonpars, v)
        elseif @capture(line, v_ ~ dist_) && (v ∉ nonpars)
            push!(pars, v)
        end
    end
    pars
end

observed(model) = setdiff(stochastic(model), parameters(model))

function supports(model)
    supps = Dict{Symbol, Any}()
    postwalk(model) do x
        if @capture(x, v_ ~ dist_)
            supps[v] = support(eval(dist))
        else x
        end
    end
    return supps
end

function xform(R, v, supp)
    @assert typeof(supp) == RealInterval
    lo = supp.lb
    hi = supp.ub
    body = begin
        if (lo,hi) == (-Inf, Inf)  # no transform needed in this case
        quote
            $v = $R
        end
    elseif (lo,hi) == (0.0, Inf)   
        quote
            $v = softplus($R)
            ℓ += abs($v - $R)
        end
    elseif (lo, hi) == (0.0, 1.0)
        quote 
            $v = logistic($R)
            ℓ += log($v * (1 - $v))
        end  
    else 
        throw(error("Transform not implemented"))                            
    end
    end
    return body
end

function logdensity(model)
    j = 0
    body = postwalk(model.body) do x
        if @capture(x, v_ ~ dist_)
            if v in parameters(model)

            j += 1
            supp = support(eval(dist)) 
            @assert (typeof(supp) == RealInterval) "Sampled values must have RealInterval support (for now)"
            quote
                $(xform(:(θ[$j]), v, supp ))
                ℓ += logpdf($dist, $v)
                end |> unblock
            elseif v in observed(model)
            quote
                ℓ += logpdf($dist, $v)
                end |> unblock
            else
                print("bad")
            end
        else x
        end
    end
    fQuoted = quote
        function($(model.args)...)
            function(θ::Vector{Float64})
            ℓ = 0.0
            $body
            return ℓ
        end
    end

    return pretty(fQuoted)
end

function mapbody(f,functionExpr)
    ans = deepcopy(functionExpr)
    ans.args[2] = f(ans.args[2])
    ans
end

function samp(m)
    func = postwalk(m) do x
        if @capture(x, v_ ~ dist_) 
            @q begin
                $v = rand($dist)
                val = merge(val, ($v=$v,))
            end
        else x
        end
    end

    mapbody(func) do body
        @q begin
            val = NamedTuple()
            $body
            val
        end
    end
end;

sampleFrom(m) = eval(samp(m))


HalfCauchy(s) = Truncated(Cauchy(0,s),0,Inf)

# Binomial distribution, parameterized by logit(p)
LogisticBinomial(n,x)=Binomial(n,logistic(x))

import Base.rand


function findsubexprs(ex, vs)
    result = Set()
    MacroTools.postwalk(ex) do y
      y in vs && push!(result, y)
    end
    return result
end



function updategraph!(g, v, rhs)

end

function graph(m)
    g = DefaultDict{Symbol, Set{Symbol}}(Set{Symbol}())
    for v in args(m)
        add_vertex!(g,v) 
    end

end



function rand(m :: Model)
    if (observed(m) == []) && (args(m) == [])
        print("ok")
    elseif args(m) != []
        throw(ArgumentError("rand called with nonempty args(m) == $(args(m))"))
    elseif observed(m) != []
        throw(ArgumentError("rand called with nonempty observed(m) == $(observed(m))"))
    end
end