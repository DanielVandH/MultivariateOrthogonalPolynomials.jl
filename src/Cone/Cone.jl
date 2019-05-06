export Cone, DuffyCone, LegendreCone, Conic, DuffyConic, LegendreConic

### 
#  Conic
###

struct Conic <: Domain{Vec{3,Float64}} end
struct DuffyConic <: Space{Conic,Float64} end
struct LegendreConic <: Space{Conic,Float64} end

@containsconstants DuffyConic
@containsconstants LegendreConic

spacescompatible(::DuffyConic, ::DuffyConic) = true
spacescompatible(::LegendreConic, ::LegendreConic) = true

domain(::DuffyConic) = Conic()
domain(::LegendreConic) = Conic()

tensorizer(K::DuffyConic) = DiskTensorizer()
tensorizer(K::LegendreConic) = DiskTensorizer()

rectspace(::DuffyConic) = NormalizedJacobi(0,1,Segment(1,0))*Fourier()

conemap(t,x,y) = Vec(t, t*x, t*y)
conemap(txy) = ((t,x,y) = txy; conemap(t,x,y))
conicpolar(t,θ) = conemap(t, cos(θ), sin(θ))
conicpolar(tθ) = ((t,θ) = tθ; conicpolar(t,θ))

points(::Conic, n) = conicpolar.(points(rectspace(DuffyConic()), n))
checkpoints(::Conic) = conicpolar.(checkpoints(rectspace(DuffyConic())))


plan_transform(S::DuffyConic, n::AbstractVector) = 
    TransformPlan(S, plan_transform(rectspace(S),n), Val{false})
plan_itransform(S::DuffyConic, n::AbstractVector) = 
    ITransformPlan(S, plan_itransform(rectspace(S),n), Val{false})

*(P::TransformPlan{<:Any,<:DuffyConic}, v::AbstractArray) = P.plan*v
*(P::ITransformPlan{<:Any,<:DuffyConic}, v::AbstractArray) = P.plan*v

evaluate(cfs::AbstractVector, S::DuffyConic, txy) = evaluate(cfs, rectspace(S), ipolar(txy[Vec(2,3)]))
evaluate(cfs::AbstractVector, S::LegendreConic, txy) = evaluate(coefficients(cfs, S, DuffyConic()), DuffyConic(), txy)


# function transform(::DuffyConic, v)
#     n = (1 + isqrt(1+8*length(v))) ÷ 4
#     F = copy(reshape(v,n,2n-1))
#     Pt = plan_transform(NormalizedJacobi(0,1,Segment(1,0)), n)
#     Pθ = plan_transform(Fourier(), 2n-1)
#     for j = 1:size(F,2)
#         F[:,j] = Pt*F[:,j]
#     end
#     for k = 1:size(F,1)
#         F[k,:] = Pθ * F[k,:]
#     end
#     fromtensor(rectspace(DuffyConic()), F)
# end

function evaluate(cfs::AbstractVector, S::DuffyConic, txy::Vec{3})
    t,x,y = txy
    @assert t ≈ sqrt(x^2+y^2)
    θ = atan(y,x)
    Fun(rectspace(S), cfs)(t,θ)
end

function duffy2legendreconic!(triangleplan, F::AbstractMatrix)
    Fc = F[:,1:2:end]
    c_execute_tri_lo2hi(triangleplan, Fc)
    F[:,1:2:end] .= Fc
    # ignore first column
    Fc[:,2:end] .= F[:,2:2:end]
    c_execute_tri_lo2hi(triangleplan, Fc)
    F[:,2:2:end] .= Fc[:,2:end]
    F
end

function legendre2duffyconic!(triangleplan, F::AbstractMatrix)
    Fc = F[:,1:2:end]
    c_execute_tri_hi2lo(triangleplan, Fc)
    F[:,1:2:end] .= Fc
    # ignore first column
    Fc[:,2:end] .= F[:,2:2:end]
    c_execute_tri_hi2lo(triangleplan, Fc)
    F[:,2:2:end] .= Fc[:,2:end]
    F
end


function _coefficients(triangleplan, v::AbstractVector{T}, ::DuffyConic, ::LegendreConic) where T
    F = totensor(rectspace(DuffyConic()), v)
    F = pad(F, :, 2size(F,1)-1)
    duffy2legendreconic!(triangleplan, F)
    fromtensor(LegendreConic(), F)
end

function _coefficients(triangleplan, v::AbstractVector{T}, ::LegendreConic,  ::DuffyConic) where T
    F = totensor(LegendreConic(), v)
    F = pad(F, :, 2size(F,1)-1)
    legendre2duffyconic!(triangleplan, F)
    fromtensor(rectspace(DuffyConic()), F)
end

function coefficients(cfs::AbstractVector{T}, CD::DuffyConic, ZD::LegendreConic) where T
    c = totensor(rectspace(DuffyConic()), cfs)            # TODO: wasteful
    n = size(c,1)
    _coefficients(c_plan_rottriangle(n, zero(T), zero(T), zero(T)), cfs, CD, ZD)
end

function coefficients(cfs::AbstractVector{T}, ZD::LegendreConic, CD::DuffyConic) where T
    c = tridevec(cfs)            # TODO: wasteful
    n = size(c,1)
    _coefficients(c_plan_rottriangle(n, zero(T), zero(T), zero(T)), cfs, ZD, CD)
end

struct LegendreConicTransformPlan{DUF,CHEB}
    duffyplan::DUF
    triangleplan::CHEB
end

function LegendreConicTransformPlan(S::LegendreConic, v::AbstractVector{T}) where T 
    D = plan_transform(DuffyConic(),v)
    F = totensor(rectspace(DuffyConic()), D*v) # wasteful, just use to figure out `size(F,1)`
    P = c_plan_rottriangle(size(F,1), zero(T), zero(T), zero(T))
    LegendreConicTransformPlan(D,P)
end


*(P::LegendreConicTransformPlan, v::AbstractVector) = _coefficients(P.triangleplan, P.duffyplan*v, DuffyConic(), LegendreConic())

plan_transform(K::LegendreConic, v::AbstractVector) = LegendreConicTransformPlan(K, v)

struct LegendreConicITransformPlan{DUF,CHEB}
    iduffyplan::DUF
    triangleplan::CHEB
end

function LegendreConicITransformPlan(S::LegendreConic, v::AbstractVector{T}) where T 
    F = fromtensor(LegendreConic(), v) # wasteful, just use to figure out `size(F,1)`
    P = c_plan_rottriangle(size(F,1), zero(T), zero(T), zero(T))
    D = plan_itransform(DuffyConic(), _coefficients(P, v, S, DuffyConic()))
    LegendreConicITransformPlan(D,P)
end


*(P::LegendreConicITransformPlan, v::AbstractVector) = P.iduffyplan*_coefficients(P.triangleplan, v, LegendreConic(), DuffyConic())


plan_itransform(K::LegendreConic, v::AbstractVector) = LegendreConicITransformPlan(K, v)



### 
#  Cone
###

struct Cone <: Domain{Vec{3,Float64}} end

in(x::Vec{3}, d::Cone) = 0 ≤ x[1] ≤ 1 && x[2]^2 + x[3]^2 ≤ x[1]^2 

struct DuffyCone <: Space{Cone,Float64} end
struct LegendreCone <: Space{Cone,Float64} end

@containsconstants DuffyCone
@containsconstants LegendreCone

spacescompatible(::DuffyCone, ::DuffyCone) = true
spacescompatible(::LegendreCone, ::LegendreCone) = true

domain(::DuffyCone) = Cone()
domain(::LegendreCone) = Cone()

ConeTensorizer() = Tensorizer((Ones{Int}(∞),Base.OneTo(∞)))

tensorizer(K::DuffyCone) = ConeTensorizer()
tensorizer(K::LegendreCone) = ConeTensorizer()

rectspace(::DuffyCone) = NormalizedJacobi(0,1,Segment(1,0))*ZernikeDisk()

blocklengths(d::DuffyCone) = blocklengths(rectspace(d))

function points(d::Cone,n)
    N = ceil(Int, n^(1/3))
    pts=Array{float(eltype(d))}(undef,0)
    a,b = rectspace(DuffyCone()).spaces
    for y in points(b,N^2), x in points(a,N)
        push!(pts,Vec(x...,y...))
    end
    conemap.(pts)
end


checkpoints(::Cone) = conemap.(checkpoints(rectspace(DuffyCone())))


function plan_transform(sp::DuffyCone, n::AbstractVector{T})  where T
    rs = rectspace(sp)
    N = ceil(Int, length(n)^(1/3))
    M = length(points(rs.spaces[2], N^2))
    @assert N*M == length(n)
    TransformPlan(sp,((plan_transform(rs.spaces[1],T,N),N), (plan_transform(rs.spaces[2],T,M),M)), Val{false})
end
plan_itransform(S::DuffyCone, n::AbstractVector) = 
    ITransformPlan(S, plan_itransform(rectspace(S),n), Val{false})

function *(T::TransformPlan{<:Any,<:DuffyCone,true}, M::AbstractMatrix)
    n=size(M,1)

    for k=1:size(M,2)
        M[:,k]=T.plan[1][1]*M[:,k]
    end
    for k=1:n
        M[k,:] = (T.plan[2][1]*M[k,:])[1:size(M,2)]
    end
    M
end

function *(T::TransformPlan{<:Any,<:DuffyCone,true},v::AbstractVector) 
    N,M = T.plan[1][2],T.plan[2][2]
    V=reshape(v,N,M)
    fromtensor(T.space,T*V)
end

function *(T::TransformPlan{<:Any,SS,false},v::AbstractVector) where {SS<:DuffyCone}
    P = TransformPlan(T.space,T.plan,Val{true})
    P*AbstractVector{rangetype(SS)}(v)
end

*(P::ITransformPlan{<:Any,<:DuffyCone}, v::AbstractArray) = P.plan*v

evaluate(cfs::AbstractVector, S::DuffyCone, txy) = evaluate(cfs, rectspace(S), ipolar(txy[Vec(2,3)]))
evaluate(cfs::AbstractVector, S::LegendreCone, txy) = evaluate(coefficients(cfs, S, DuffyCone()), DuffyCone(), txy)


# function transform(::DuffyCone, v)
#     n = (1 + isqrt(1+8*length(v))) ÷ 4
#     F = copy(reshape(v,n,2n-1))
#     Pt = plan_transform(NormalizedJacobi(0,1,Segment(1,0)), n)
#     Pθ = plan_transform(Fourier(), 2n-1)
#     for j = 1:size(F,2)
#         F[:,j] = Pt*F[:,j]
#     end
#     for k = 1:size(F,1)
#         F[k,:] = Pθ * F[k,:]
#     end
#     fromtensor(rectspace(DuffyCone()), F)
# end

function evaluate(cfs::AbstractVector, S::DuffyCone, txy::Vec{3})
    t,x,y = txy
    @assert x^2+y^2 ≤ t^2
    a,b = rectspace(S).spaces
    mat = totensor(S, cfs)
    for j = 1:size(mat,2)
        # in place since totensor makes copy
        mat[1,j] = Fun(a, view(mat,:,j))(t)
    end
    Fun(b, view(mat,1,:))(x/t,y/t)
end

function duffy2legendrecone_column_J!(P, Fc, F, Jin)
    J = sum(1:Jin)
    for j = Jin:size(Fc,2)
        if 1 ≤ J ≤ size(F,2)
            Fc[:,j] .= view(F,:,J)
        else
            Fc[:,j] .= 0
        end
        J += j
    end
    c_execute_tri_lo2hi(P, Fc)
    J = sum(1:Jin)
    for j = Jin:size(Fc,2)
        J > size(F,2) && break
        F[:,J] .= view(Fc,:,j)
        J += j
    end
    F
end

function legendre2duffycone_column_J!(P, Fc, F, Jin)
    J = sum(1:Jin)
    for j = Jin:size(Fc,2)
        if 1 ≤ J ≤ size(F,2)
            Fc[:,j] .= view(F,:,J)
        else
            Fc[:,j] .= 0
        end
        J += j
    end
    c_execute_tri_hi2lo(P, Fc)
    J = sum(1:Jin)
    for j = Jin:size(Fc,2)
        J > size(F,2) && break
        F[:,J] .= view(Fc,:,j)
        J += j
    end
    F
end

function duffy2legendrecone!(triangleplan, F::AbstractMatrix)
    Fc = Matrix{Float64}(undef,size(F,1),size(F,1))
    for J = 1:(isqrt(1 + 8size(F,2))-1)÷ 2 # actually div 
        duffy2legendrecone_column_J!(triangleplan, Fc, F, J)
    end
    F
end

function legendre2duffycone!(triangleplan, F::AbstractMatrix)
    Fc = Matrix{Float64}(undef,size(F,1),size(F,1))
    for J = 1:(isqrt(1 + 8size(F,2))-1)÷ 2 # actually div 
        legendre2duffycone_column_J!(triangleplan, Fc, F, J)
    end
    F
end

function _coefficients(triangleplan, v::AbstractVector{T}, ::DuffyCone, ::LegendreCone) where T
    F = totensor(rectspace(DuffyCone()), v)
    for j = 1:size(F,2)
        F[:,j] = coefficients(F[:,j], NormalizedJacobi(0,1,Segment(1,0)), NormalizedJacobi(0,2,Segment(1,0)))
    end
    duffy2legendrecone!(triangleplan, F)
    fromtensor(LegendreCone(), F)
end

function _coefficients(triangleplan, v::AbstractVector{T}, ::LegendreCone, ::DuffyCone) where T
    F = totensor(LegendreCone(), v)
    legendre2duffycone!(triangleplan, F)
    for j = 1:size(F,2)
        F[:,j] = coefficients(F[:,j], NormalizedJacobi(0,2,Segment(1,0)), NormalizedJacobi(0,1,Segment(1,0)))
    end
    fromtensor(rectspace(DuffyCone()), F)
end

function coefficients(cfs::AbstractVector{T}, CD::DuffyCone, ZD::LegendreCone) where T
    c = totensor(rectspace(DuffyCone()), cfs)            # TODO: wasteful
    n = size(c,1)
    _coefficients(c_plan_rottriangle(n, zero(T), zero(T), one(T)), cfs, CD, ZD)
end

function coefficients(cfs::AbstractVector{T}, ZD::LegendreCone, CD::DuffyCone) where T
    c = totensor(LegendreCone(), cfs)            # TODO: wasteful
    n = size(c,1)
    _coefficients(c_plan_rottriangle(n, zero(T), zero(T), one(T)), cfs, ZD, CD)
end

struct LegendreConeTransformPlan{DUF,CHEB}
    duffyplan::DUF
    triangleplan::CHEB
end

function LegendreConeTransformPlan(S::LegendreCone, v::AbstractVector{T}) where T 
    D = plan_transform(DuffyCone(),v)
    F = totensor(rectspace(DuffyCone()), D*v) # wasteful, just use to figure out `size(F,1)`
    P = c_plan_rottriangle(size(F,1), zero(T), zero(T), one(T))
    LegendreConeTransformPlan(D,P)
end


*(P::LegendreConeTransformPlan, v::AbstractVector) = _coefficients(P.triangleplan, P.duffyplan*v, DuffyCone(), LegendreCone())

plan_transform(K::LegendreCone, v::AbstractVector) = LegendreConeTransformPlan(K, v)

struct LegendreConeITransformPlan{DUF,CHEB}
    iduffyplan::DUF
    triangleplan::CHEB
end

function LegendreConeITransformPlan(S::LegendreCone, v::AbstractVector{T}) where T 
    F = fromtensor(LegendreCone(), v) # wasteful, just use to figure out `size(F,1)`
    P = c_plan_rottriangle(size(F,1), zero(T), zero(T), one(T))
    D = plan_itransform(DuffyCone(), _coefficients(P, v, S, DuffyCone()))
    LegendreConeITransformPlan(D,P)
end


*(P::LegendreConeITransformPlan, v::AbstractVector) = P.iduffyplan*_coefficients(P.triangleplan, v, LegendreCone(), DuffyCone())


plan_itransform(K::LegendreCone, v::AbstractVector) = LegendreConeITransformPlan(K, v)

