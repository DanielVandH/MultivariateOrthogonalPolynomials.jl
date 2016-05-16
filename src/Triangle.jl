export Triangle,KoornwinderTriangle



## Triangle Def
# currently right trianglel
immutable Triangle <: BivariateDomain{Float64} end


#canonical is rectangle [0,1]^2
# with the map (x,y)=(s,(1-s)*t)
fromcanonical(::Triangle,s,t)=s,(1-s)*t
tocanonical(::Triangle,x,y)=x,y/(1-x)
checkpoints(d::Triangle)=[fromcanonical(d,(.1,.2243));fromcanonical(d,(-.212423,-.3))]

# expansion in OPs orthogonal to
# x^α*y^β*(1-x-y)^γ
# defined as
# P_{n-k}^{2k+β+γ+1,α}(2x-1)*(1-x)^k*P_k^{γ,β}(2y/(1-x)-1)


immutable ProductTriangle <: AbstractProductSpace{Tuple{WeightedJacobi{Interval{Float64}},Jacobi{Float64,Interval{Float64}}},Float64,2}
    α::Float64
    β::Float64
    γ::Float64
    domain::Triangle
end

immutable KoornwinderTriangle <: Space{RealBasis,Triangle,2}
    α::Float64
    β::Float64
    γ::Float64
    domain::Triangle
end

ProductTriangle(K::KoornwinderTriangle) = ProductTriangle(K.α,K.β,K.γ,K.domain)


for TYP in (:ProductTriangle,:KoornwinderTriangle)
    @eval begin
        $TYP(α,β,γ)=$TYP(α,β,γ,Triangle())
        $TYP(T::Triangle)=$TYP(0.,0.,0.,T)
        spacescompatible(K1::$TYP,K2::$TYP)=K1.α==K2.α && K1.β==K2.β && K1.γ==K2.γ
    end
end



Space(T::Triangle)=KoornwinderTriangle(T)




# support for ProductFun constructor

function space(T::ProductTriangle,k::Integer)
    @assert k==2
    Jacobi(T.γ,T.β,Interval(0.,1.))
end

columnspace(T::ProductTriangle,k::Integer)=JacobiWeight(0.,k-1.,Jacobi(2k-1+T.β+T.γ,T.α,Interval(0.,1.)))


# convert coefficients

Fun(f::Function,S::KoornwinderTriangle) =
    Fun(Fun(f,ProductTriangle(S)),S)

function coefficients(f::AbstractVector,K::KoornwinderTriangle,P::ProductTriangle)
    C=totensor(f)
    D=Float64[2.0^(-k) for k=0:size(C,1)-1]
    fromtensor((C.')*diagm(D))
end

function coefficients(f::AbstractVector,K::ProductTriangle,P::KoornwinderTriangle)
    C=totensor(f)
    D=Float64[2.0^(k) for k=0:size(C,1)-1]
    fromtensor((C*diagm(D)).')
end

evaluate(f::AbstractVector,K::KoornwinderTriangle,x...) =
    evaluate(coefficients(f,K,ProductTriangle(K)),ProductTriangle(K),x...)


# Operators



function Derivative(K::KoornwinderTriangle,order::Vector{Int})
    @assert length(order)==2
    if order==[1,0] || order==[0,1]
        ConcreteDerivative(K,order)
    elseif order[1]>1
        D=Derivative(K,[1,0])
        DerivativeWrapper(TimesOperator(Derivative(rangespace(D),[order[1]-1,order[2]]),D),order)
    else
        @assert order[2]>1
        D=Derivative(K,[0,1])
        DerivativeWrapper(TimesOperator(Derivative(rangespace(D),[order[1],order[2]-1]),D),order)
    end
end


rangespace(D::ConcreteDerivative{KoornwinderTriangle})=KoornwinderTriangle(D.space.α+D.order[1],D.space.β+D.order[2],D.space.γ+sum(D.order),domain(D))
bandinds(D::ConcreteDerivative{KoornwinderTriangle})=0,sum(D.order)
blockbandinds(D::ConcreteDerivative{KoornwinderTriangle},k::Integer)=k==0?0:sum(D.order)

function getindex(D::ConcreteDerivative{KoornwinderTriangle},n::Integer,j::Integer)
    K=domainspace(D)
    α,β,γ = K.α,K.β,K.γ
    if D.order==[0,1]
        if j==n+1
            ret=bzeros(n,j,0,1)

            for k=1:size(ret,1)
                ret[k,k+1]+=(1+k+β+γ)
            end
        else
            ret=bzeros(n,j,0,0)
        end
    elseif D.order==[1,0]
        if j==n+1
            ret=bzeros(n,j,0,1)

            for k=1:size(ret,1)
                ret[k,k]+=(1+k+n+α+β+γ)*(k+γ+β)/(2k+γ+β-1)
                ret[k,k+1]+=(k+β)*(k+n+γ+β+1)/(2k+γ+β+1)
            end
        else
            ret=bzeros(n,j,0,0)
        end
    else
        error("Not implemented")
    end
    ret
end



## Conversion

conversion_rule(K1::KoornwinderTriangle,K2::KoornwinderTriangle) =
    KoornwinderTriangle(min(K1.α,K2.α),min(K1.β,K2.β),min(K1.γ,K2.γ))
maxspace_rule(K1::KoornwinderTriangle,K2::KoornwinderTriangle) =
    KoornwinderTriangle(max(K1.α,K2.α),max(K1.β,K2.β),max(K1.γ,K2.γ))

function Conversion(K1::KoornwinderTriangle,K2::KoornwinderTriangle)
    @assert K1.α≤K2.α && K1.β≤K2.β && K1.γ≤K2.γ &&
        isapproxinteger(K1.α-K2.α) && isapproxinteger(K1.β-K2.β) &&
        isapproxinteger(K1.γ-K2.γ)

    if (K1.α+1==K2.α && K1.β==K2.β && K1.γ==K2.γ) ||
            (K1.α==K2.α && K1.β+1==K2.β && K1.γ==K2.γ) ||
            (K1.α==K2.α && K1.β==K2.β && K1.γ+1==K2.γ)
        ConcreteConversion(K1,K2)
    elseif K1.α+1<K2.α || (K1.α+1==K2.α && (K1.β+1≥K2.β || K1.γ+1≥K2.γ))
        # increment α if we have e.g. (α+2,β,γ) or  (α+1,β+1,γ)
        Conversion(K1,KoornwinderTriangle(K1.α+1,K1.β,K1.γ),K2)
    elseif K1.β+1<K2.β || (K1.β+1==K2.β && K1.γ+1≥K2.γ)
        # increment β
        Conversion(K1,KoornwinderTriangle(K1.α,K1.β+1,K1.γ),K2)
    elseif K1.γ+1<K2.γ
        # increment γ
        Conversion(K1,KoornwinderTriangle(K1.α,K1.β,K1.γ+1),K2)
    else
        error("There is a bug")
    end
end
bandinds(C::ConcreteConversion{KoornwinderTriangle,KoornwinderTriangle})=(0,1)
blockbandinds(C::ConcreteConversion{KoornwinderTriangle,KoornwinderTriangle},k::Integer)=k==1?0:1


function getindex(C::ConcreteConversion{KoornwinderTriangle,KoornwinderTriangle},n::Integer,j::Integer)
    K1=domainspace(C);K2=rangespace(C)
    α,β,γ = K1.α,K1.β,K1.γ
    if K2.α==α+1 && K2.β==β && K2.γ==γ
        ret=bzeros(n,j,0,0)
        if n==j
            for k=1:size(ret,1)
                ret[k,k]=(n+k+α+β+γ)/(2n+α+β+γ)
            end
        elseif j==n+1
            for k=1:size(ret,1)
                ret[k,k]=(n+k+β+γ)/(2n+α+β+γ+2)
            end
        end
    elseif K2.α==α && K2.β==β+1 && K2.γ==γ
        if j==n
            ret=bzeros(n,j,0,1)

            for k=1:size(ret,1)
                ret[k,k]  += (n+k+α+β+γ)/(2n+α+β+γ)*(k+β+γ)/(2k+β+γ-1)
                if k+1 ≤ size(ret,2)
                    ret[k,k+1]-= (k+γ)/(2k+β+γ+1)*(n-k)/(2n+α+β+γ)
                end
            end
        elseif j==n+1
            ret=bzeros(n,j,0,1)
            for k=1:size(ret,1)
                ret[k,k]  -= (n-k+α+1)/(2n+α+β+γ+2)*(k+β+γ)/(2k+β+γ-1)
                if k+1 ≤ size(ret,2)
                    ret[k,k+1]+= (k+γ)/(2k+β+γ+1)*(n+k+β+γ+1)/(2n+α+β+γ+2)
                end
            end
        else
            ret=bzeros(k,j,0,0)
        end
    elseif K2.α==α && K2.β==β && K2.γ==γ+1
        if n==j
            ret=bzeros(n,j,0,1)

            for k=1:size(ret,1)
                ret[k,k]  += (n+k+α+β+γ)/(2n+α+β+γ)*(k+β+γ)/(2k+β+γ-1)
                if k+1 ≤ size(ret,2)
                    ret[k,k+1]-= (k+β)/(2k+β+γ+1)*(n-k)/(2n+α+β+γ)
                end
            end
        elseif j==n+1
            ret=bzeros(n,j,0,1)

            for k=1:size(ret,1)
                ret[k,k]  -= (n-k+α+1)/(2n+α+β+γ+2)*(k+β+γ)/(2k+β+γ-1)
                if k+1 ≤ size(ret,2)
                    ret[k,k+1]+= (k+β)/(2k+β+γ+1)*(n+k+β+γ+1)/(2n+α+β+γ+2)
                end
            end
        else
            ret=bzeros(n,j,0,0)
        end
    else
        error("Not implemented")
    end

    ret
end
