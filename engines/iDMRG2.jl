# additional contractions used in this scope
include("iDMRG2_contractions.jl")
include("iDMRG2_link_manipulations.jl")
using DMRG_types

# traditional growing algorithm -- starts from scratch with a given mpo tensor and variationally searches for the (2-site periodic) MPS
function iDMRG2(mpo::A; χ::Int64=64, numSteps::Int64=100, tol::Float64=KrylovDefaults.tol) where {A<:AbstractTensorMap{S,2,2} where {S<:EuclideanSpace}}

    # mpo_arr = convert(Array, mpo)
    # mpo = TensorMap(mpo_arr, ComplexSpace(2)*ComplexSpace(5), ComplexSpace(5)*ComplexSpace(2))
    
    # this extracts the link spaces from the MPO tensor legs
    physSpace = space(mpo)[1]
    mpoSpaceL = space(mpo)[2]
    # this is an outgoing leg so it must be conjugated for further purposes
    mpoSpaceR = space(mpo)[3]'

    # initial legs of the MPS (currently only ℤ₂ and ℂ, needs further adaption)
    if occursin("ComplexSpace",string(typeof(physSpace)))
        zeroIrrep = ℂ^1
    elseif occursin("ZNIrrep{2}",string(typeof(physSpace)))
        zeroIrrep = ℤ₂Space(0 => 1)
    elseif  occursin("SU2Irrep",string(typeof(physSpace)))
        zeroIrrep = SU₂Space(0 => 1)
    end
    mpsSpaceL = zeroIrrep
    mpsSpaceR = zeroIrrep
    mpoSpaceI = zeroIrrep
    mpoSpaceO = zeroIrrep
    mpsSpaceShared = computeSharedLink(mpsSpaceL, physSpace, physSpace, mpsSpaceR)
    
    # mpoBoundaryVecL = zeros(ComplexF64, dim(mpoSpaceI),dim(mpoSpaceL))
    # mpoBoundaryVecL[1] = 1
    # mpoBoundaryVecL = Array{ComplexF64}([1.0 0.0]);
    # mpoBoundaryVecR = zeros(ComplexF64, dim(mpoSpaceR),dim(mpoSpaceO))
    # mpoBoundaryVecR[2] = 1
    # mpoBoundaryVecR = Array{ComplexF64}([0.0 ; 1.0]);

    # mpoBoundaryTensL = TensorMap(reshape([1 0], (1 1 2)), mpoSpaceI*mpoSpaceL, zeroIrrep)
    mpoBoundaryTensL = TensorMap(zeros, mpoSpaceI, mpoSpaceL)
    tensorDictL = convert(Dict, mpoBoundaryTensL)
    dataDictL = tensorDictL[:data]
    dataDictL["Irrep[SU₂](0)"] = Array{ComplexF64}([1.0 0.0])
    tensorDictL[:data] = dataDictL
    mpoBoundaryTensL = convert(TensorMap, tensorDictL)

    mpoBoundaryTensR = TensorMap(zeros, mpoSpaceR, mpoSpaceO)
    tensorDictR = convert(Dict, mpoBoundaryTensR)
    dataDictR = tensorDictR[:data]
    dataDictR["Irrep[SU₂](0)"] = Array{ComplexF64}(reshape([0.0 ; 1.0], (2,1)))
    tensorDictR[:data] = dataDictR
    mpoBoundaryTensR = convert(TensorMap, tensorDictR)
    # mpoBoundaryTensL = reshape(mpoBoundaryTensL, dim())
    # mpoBoundaryTensL = TensorMap(mpoBoundaryTensL, space(mpoBoundaryTensL, 1), space(mpoBoundaryTensL, 2))
    # mpoBoundaryTensR = Tensor([0 1], mpoSpaceR*mpoSpaceO)

    # println(mpoBoundaryTensL)

    # initialize MPS tensors
    T1 = TensorMap(randn, ComplexF64, physSpace*mpsSpaceL, mpsSpaceShared)
    T2 = TensorMap(randn, ComplexF64, physSpace*mpsSpaceShared, mpsSpaceR)
    # println(T1)
    # println(T2)

    # initiliaze EL and ER
    IdL = TensorMap(ones, ComplexF64, mpsSpaceL, mpoSpaceI*mpsSpaceL)
    IdR = TensorMap(ones, ComplexF64, mpoSpaceO*mpsSpaceR, mpsSpaceR)
    @tensor EL[-1 ; -2 -3] := IdL[-1 1 -3] * mpoBoundaryTensL[1 -2]
    @tensor ER[-1 -2 ; -3] := mpoBoundaryTensR[-1 1] * IdR[1 -2 -3]
    @tensor energy[:] := EL[1 2 3] * ER[2 3 1]
    # println(energy)
    # println(EL)
    # println(ER)
    
    # initialize array to store energy
    groundStateEnergy = zeros(Float64, numSteps, 5)

    # initialize variables to be available outside of for-loop
    ϵ = 0
    current_χ = 0
    currEigenVal = 0
    currEigenVec = []
    prevEigenVal = 0
    prevEigenVec = []

    # initialize tensorTrain
    # tensorTrain = Vector{A}(undef,2*numSteps) where {T<:Number, S<:Array{T}}
    # tensorTrain = Vector{A}(undef,2*numSteps) where {A<:AbstractTensorMap}
    # tensorTrain = Vector{Any}(undef,4*numSteps)
    # tensorTrain = {}

    
    # construct and SVD initial wave function
    theta = initialWF(T1, T2)
    # U, S, Vdag, ϵ = tsvd(theta, (2,3), (1,4), trunc = truncdim(χ))
    # Vdag = permute(Vdag, (2,1), (3,))
    # @tensor theta[-1 -2 -3; -4] = U[-2 -3 1] * S[1 2] * Vdag[-1 1 -4]
    # theta = normalize!(theta)
    Spr = TensorMap(ones, zeroIrrep, zeroIrrep);
    
    # main growing loop
    for i = 1 : numSteps
        
        groundStateEnergy[i,1] = i
        
        # store previous eivenvalue
        prevEigenVal = currEigenVal;
        
        # optimize wave function
        eigenVal, eigenVec = 
            eigsolve(theta,1, :SR, Arnoldi(tol=tol)) do x
                applyH(x, EL, mpo, ER)
            end
        currEigenVal = eigenVal[1]
        currEigenVec = eigenVec[1]
        
        #  perform SVD and truncate to desired bond dimension
        S = Spr
        U, Spr, Vdag, ϵ = tsvd(currEigenVec, (2,3), (1,4), trunc = truncdim(χ))

        current_χ = dim(space(Spr,1))
        Vdag = permute(Vdag, (2,1), (3,))

        # update environments
        EL = update_EL(EL, U, mpo)
        ER = update_ER(ER, Vdag, mpo)

        # save the tensors
        # tensorTrain[2*(i-1)+i_bond] = U
        # tensorTrain[end-2*(i-1)-i_bond+1] = V

        # obtain the new tensors for MPS
        theta = guess(Spr, Vdag, S, U)

        # calculate ground state energy
        gsEnergy = 1/2*(currEigenVal - prevEigenVal)

        # # calculate overlap between old and new wave function
        # @tensor waveFuncOverlap[:] := currEigenVec[1 2 3] * conj(prevEigenVec[1 2 3]);

        # print simulation progress
        @printf("%05i : E_iDMRG / Convergence / Discarded Weight / BondDim : %0.15f / %0.15f / %d \n",i,real(gsEnergy),ϵ,current_χ)
        
    end
    
    # tensorTrain[2*numSteps+1] = gammaList[1]
    # tensorTrain[2*numSteps] = gammaList[2]

    # mps = DMRG_types.MPS([tensor for tensor in tensorTrain]);

    print(dim(Spr))

    return
    
end