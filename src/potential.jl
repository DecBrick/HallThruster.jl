#try new potential solver, ie having extra cells on boundary

"""
    solve_potential!(; U::Matrix{Float64}, params::NamedTuple)
function to solve the potential equation derived from the generalized Ohm's law
and employing charge conservation using quasineutrality. Second derivatives approximated
with 2nd order central difference scheme, first derivatives with central difference. 
Centers of computational mesh equivalent with centers of fluid mesh, but omitting boundary ghost cells. 
If required, interpolation is used to infer properties at mesh boundaries. Potential is a function of magnetic
field, anomalous and classical collision frequency, neutral and ion density as well as ion velocity, and electron density
and temperature leading to electron pressure. Solved by inverting a tridiagonal matrix. 
"""
function solve_potential!(U, params)
    #directly discretising the equation, conserves properties such as negative semidefinite etc...
    #add functionality for nonuniform cell size
    z_cell, z_edge, _ = params.z_cell, params.z_edge, params.cell_volume
    fluids, fluid_ranges = params.fluids, params.fluid_ranges
    fluid = fluids[1].species.element
    boundary_potential! = params.boundary_potential!
    source_potential! = params.source_potential!
    index = params.index
    N = length(z_cell)

    L_ch = 0.025 #add to params

    pe = @views U[index.pe, :]
    ne = @views U[index.ne, :]
    B = params.cache.B
    A = params.cache.A
    b = params.cache.b
    Tev = @views U[index.Tev, :] 
    νan = params.cache.νan
    μ = params.cache.μ

    Δz = z_edge[3] - z_edge[2]

    # This line allocates
    #OVS = Array{Union{Nothing, Bool}}(nothing, 1)
    #OVS[1] = false

    #bc_consts = (; fluid, N, pe, ne, B, Tev, νan, Δz, OVS, index)
    #boundary_potential!(A, b, U, bc_consts) #if OVS, this sets to true

    ϕ_L = 300.0
    ϕ_R = 0.0

    b[1] = ϕ_L
    b[end] = ϕ_R

    A.d[1] = 1.0
    A.du[1] = 0.0
    A.d[N] = 1.0
    A.dl[N-1] = 0.0

    for i in 2:(N - 1) #@tturbo

        ne⁻ = 0.5 * (ne[i] + ne[i - 1])
        ne⁺ = 0.5 * (ne[i] + ne[i + 1])

        nn⁻ = (U[1, i] + U[1, i - 1]) / (2 * fluid.m)
        nn⁺ = (U[1, i] + U[1, i + 1]) / (2 * fluid.m)

        B⁻ = 0.5 * (B[i - 1] + B[i])
        B⁺ = 0.5 * (B[i] + B[i + 1])
        νan⁻ = 0.5 * (νan[i - 1] + νan[i])
        νan⁺ = 0.5 * (νan[i + 1] + νan[i])
        νc⁻ = electron_collision_freq(0.5 * (Tev[i] + Tev[i - 1]), nn⁻, ne⁻, fluid.m)
        νc⁺ = electron_collision_freq(0.5 * (Tev[i] + Tev[i + 1]), nn⁺, ne⁺, fluid.m)
        μ⁻ = electron_mobility(νan⁻, νc⁻, B⁻)
        μ⁺ = electron_mobility(νan⁺, νc⁺, B⁺)

        if OVS[1] == true
            ne⁻ = ne⁺ = nn⁻ = nn⁺ = B⁻ = B⁺ = νan⁻ = νan⁺ = μ⁻ = μ⁺ = 1.0
        end

        #Δz = z_edge[i - 1] - z_edge[i]
        Δz = z_edge[4] - z_edge[3]

        Δz² = Δz^2

        #direct discretization, h/2 to each side
        A.dl[i - 1] = ne⁻ * μ⁻ / Δz²
        A.d[i] = -(ne⁻ * μ⁻ + ne⁺ * μ⁺) / Δz²
        A.du[i] = ne⁺ * μ⁺ / Δz²

        b[i] = (μ⁻ * pe[i - 1] - (μ⁺ + μ⁻) * pe[i] + μ⁺ * pe[i + 1]) / Δz² +
        ((U[3, i + 1]+U[3, i])/2 - (U[3, i]+U[3, i - 1])/2) / Δz / HallThruster.Xenon.m

        #=
        b[i] = (μ⁻ * pe[i - 1] - (μ⁺ + μ⁻) * pe[i] + μ⁺ * pe[i + 1]) / Δz² +
        0.5 * (U[3, i + 1] - U[3, i - 1]) / Δz / HallThruster.Xenon.m=#

        #product rule
        #=
        A.dl[i - 1] = ne[i-1]*μ[i-1] / Δz² - ne[i-1]*μ[i-1] / 2 / Δz
        A.d[i] = -2*ne[i]*μ[i] / Δz²
        A.du[i] = ne[i+1]*μ[i+1] / Δz² + ne[i+1]*μ[i+1] / 2 / Δz=#


        #s_consts = (; i, i, μ⁻, μ⁺, pe, Δz)
        #source_potential!(b, U, s_consts)

    end

    #make ghost cells correspond to boundary values

    #make sure ghost cells not used in tridiagonal solve
    return tridiagonal_solve!(@views(U[index.ϕ, :]), A, b)
end

function solve_potential_edge!(U, params)
    #directly discretising the equation, conserves properties such as negative semidefinite etc...
    #add functionality for nonuniform cell size
    z_cell, z_edge, _ = params.z_cell, params.z_edge, params.cell_volume
    fluids, fluid_ranges = params.fluids, params.fluid_ranges
    fluid = fluids[1].species.element
    boundary_potential! = params.boundary_potential!
    source_potential! = params.source_potential!
    index = params.index
    N = length(z_cell) - 1

    L_ch = 0.025 #add to params

    pe = @views U[index.pe, :]
    ne = @views U[index.ne, :]
    B = params.cache.B
    A = params.cache.A
    b = params.cache.b
    Tev = @views U[index.Tev, :] 
    νan = params.cache.νan
    μ = params.cache.μ

    Δz = z_edge[3] - z_edge[2]

    OVS = Array{Union{Nothing, Bool}}(nothing, 1)
    OVS[1] = false

    #bc_consts = (; fluid, N, pe, ne, B, Tev, νan, Δz, OVS, index)
    #boundary_potential!(A, b, U, bc_consts) #if OVS, this sets to true

    ϕ_L = 300.0
    ϕ_R = 0.0

    b[1] = ϕ_L
    b[end] = ϕ_R

    A.d[1] = 1.0
    A.du[1] = 0.0
    A.d[N] = 1.0
    A.dl[N-1] = 0.0

    for i in 2:(N - 1) #@tturbo

        ne⁻ = ne[i]
        ne⁺ = ne[i + 1]

        nn⁻ = U[1, i] / fluid.m
        nn⁺ = U[1, i + 1] /fluid.m

        B⁻ = B[i]
        B⁺ = B[i + 1]
        νan⁻ = νan[i]
        νan⁺ = νan[i + 1]
        νc⁻ = electron_collision_freq(Tev[i], nn⁻, ne⁻, fluid.m)
        νc⁺ = electron_collision_freq(Tev[i + 1], nn⁺, ne⁺, fluid.m)
        μ⁻ = electron_mobility(νan⁻, νc⁻, B⁻)
        μ⁺ = electron_mobility(νan⁺, νc⁺, B⁺)

        if OVS[1] == true
            ne⁻ = ne⁺ = nn⁻ = nn⁺ = B⁻ = B⁺ = νan⁻ = νan⁺ = μ⁻ = μ⁺ = 1.0
        end

        #Δz = z_edge[i - 1] - z_edge[i]
        Δz = z_edge[4] - z_edge[3]

        Δz² = Δz^2

        #direct discretization, h/2 to each side
        A.dl[i - 1] = ne⁻ * μ⁻ / Δz²
        A.d[i] = -(ne⁻ * μ⁻ + ne⁺ * μ⁺) / Δz²
        A.du[i] = ne⁺ * μ⁺ / Δz²

        #source term, h/2 to each side
        b[i] = (μ⁻ * (pe[i - 1] + pe[i])/2 - (μ⁺ + μ⁻) * (pe[i] + pe[i + 1])/2 + μ⁺ * (pe[i + 1] + pe[i + 2])/2) / Δz² + 
        (U[3, i + 1] - U[3, i]) / Δz / HallThruster.Xenon.m

        #s_consts = (; i, i, μ⁻, μ⁺, pe, Δz)
        #source_potential!(b, U, s_consts)

    end

    #make ghost cells correspond to boundary values

    #make sure ghost cells not used in tridiagonal solve
    return tridiagonal_solve!(@views(U[index.ϕ, 1:end-1]), A, b)
end


function tridiagonal_forward_sweep!(A::Tridiagonal, b)
    n = length(A.d)

    @inbounds for i in 2:n
        w = A.dl[i - 1] / A.d[i - 1]
        A.d[i] -= w * A.du[i - 1]
        b[i] -= w * b[i - 1]
    end
end

function tridiagonal_backward_sweep!(y, A::Tridiagonal, b)
    n = length(A.d)
    y[n] = b[n] / A.d[n]
    # back-substitution
    @inbounds for i in (n - 1):-1:1
        y[i] = (b[i] - A.du[i] * y[i + 1]) / A.d[i]
    end
end

# our matrix is diagonally dominant so we can use Thomas' algorithm to solve
# the tridiagonal system
function tridiagonal_solve!(y, A, b)
    tridiagonal_forward_sweep!(A, b)
    return tridiagonal_backward_sweep!(y, A, b)
end

function tridiagonal_solve(A, b)
    y = similar(b)
    A′ = copy(A)
    b′ = copy(b)
    tridiagonal_solve!(y, A′, b′)
    return y
end

"""
    boundary_conditions_potential!(A, b, U, bc_consts, ϕ_L, ϕ_R)
Applies dirichlet boundary conditions for potential. 
"""

function boundary_conditions_potential!(A, b, U, bc_consts, ϕ_L, ϕ_R)
    fluid, N, pe, ne, B, Tev, νan, Δz, OVS, index = bc_consts
    
    U[index.ϕ, 1] = ϕ_L
    U[index.ϕ, end] = ϕ_R

    #left boundary
    ne⁻ = ne[1]
    ne⁺ = 0.5 * (ne[2] + ne[3])
    nn⁻ = U[1, 1] / fluid.m
    nn⁺ = (U[1, 2] / fluid.m + U[1, 3] / fluid.m) / 2
    B⁻ = B[1]
    B⁺ = 0.5 * (B[2] + B[3])
    νan⁻ = νan[1]
    νan⁺ = 0.5 * (νan[2] + νan[3])
    μ⁻ = electron_mobility(νan⁻, electron_collision_freq(Tev[1], ne⁻, nn⁻, fluid.m), B⁻)
    μ⁺ = electron_mobility(νan⁺, electron_collision_freq((Tev[2] + Tev[3]) / 2, ne⁺, nn⁺, fluid.m), B⁺)
    
    A.d[1] = -1 * (ne⁻ * μ⁻ + ne⁺ * μ⁺) / (Δz)^2 #no interpolation on boundary
    A.du[1] = ne⁺ * μ⁺ / (Δz)^2
    b[1] = -ϕ_L * (ne⁻ * μ⁻) / ((Δz)^2) - 1 * (μ⁺ + μ⁻) * pe[2] / (Δz)^2 +
           μ⁺ * pe[3] / (Δz)^2 +
           (μ⁻) * pe[1] / (Δz)^2
    -(U[3, 1] / (Δz) + (U[3, 3] + U[3, 2]) / (2 * Δz)) / HallThruster.Xenon.m #no interpolation on boundary

    #right boundary
    ne⁻ = 0.5 * (ne[N] + ne[N + 1])
    ne⁺ = ne[N + 2]
    nn⁻ = (U[1, N + 1] / fluid.m + U[1, N] / fluid.m) / 2
    nn⁺ = U[1, N + 2] / fluid.m
    B⁻ = 0.5 * (B[N] + B[N + 1])
    B⁺ = B[N + 2]
    νan⁻ = 0.5 * (νan[N] + νan[N + 1])
    νan⁺ = νan[N + 2]
    μ⁻ = electron_mobility(νan⁻, electron_collision_freq((Tev[N + 1] + Tev[N]) / 2, ne⁻, nn⁻, fluid.m),
                               B⁻)
    μ⁺ = electron_mobility(νan⁺, electron_collision_freq(Tev[N + 2], ne⁺, nn⁺, fluid.m), B⁺)
   
    A.d[N] = -1 * (ne⁻ * μ⁻ + ne⁺ * μ⁺) / (Δz)^2 #no interpolation on boundary
    A.dl[N - 1] = ne⁻ * μ⁻ / (Δz)^2
    b[N] = -ϕ_R * (ne⁺ * μ⁺) / ((Δz)^2) + μ⁻ * pe[N] / (Δz)^2 -
           1 * (μ⁺ + μ⁻) * pe[N + 1] / (Δz)^2 + (μ⁺) * pe[N + 2] / (Δz)^2
    -((U[3, N] + U[3, N + 1]) / (2 * Δz) + U[3, N + 2] / (Δz)) / HallThruster.Xenon.m #no interpolation on boundary

end

"""
    potential_source_term!(b, U, s_consts)
Applies source term to potential.
"""

function potential_source_term!(b, U, s_consts)
    i, i, μ⁻, μ⁺, pe, Δz = s_consts
    Δz² = Δz^2
    b[i] = (μ⁻ * pe[i - 1] - (μ⁺ + μ⁻) * pe[i] + μ⁺ * pe[i + 1]) / Δz² +
    0.5 * (U[3, i + 1] - U[3, i - 1]) / Δz / HallThruster.Xenon.m
end

"""
    OVS_potential_source_term!(b, s_consts)
Applies a scalar as source term for potential OVS.
"""

function OVS_potential_source_term!(b, s_consts) #for OVS
    i, i, μ⁻, μ⁺, pe, Δz = s_consts
    b[i] = 50000.0
end

"""
    OVS_boundary_conditions_potential!(A, b, U, bc_consts, ϕ_L, ϕ_R)
Applies Dirichlet boundary conditions to potential equation for OVS.
"""

function OVS_boundary_conditions_potential!(A, b, U, bc_consts, ϕ_L, ϕ_R) #for OVS, need to implement interpolation on boundary for real case as well
    fluid, N, pe, ne, B, Tev, νan, Δz, OVS, index = bc_consts
    
    #make ghost cells correspond to boundary
    U[index.ϕ, 1] = ϕ_L
    U[index.ϕ, end] =  ϕ_R

    ne⁻ = ne⁺ = μ⁻ = μ⁺ = 1.0    
    #A.d[1] = -1 * (ne⁻ * μ⁻ + ne⁺ * μ⁺) / (Δz)^2 #no interpolation on boundary
    A.du[1] = ne⁺ * μ⁺ / (Δz)^2
    #b[1] = -ϕ_L / ((Δz)^2) #no interpolation on boundary

    #right boundary   
    #A.d[N] = -1 * (ne⁻ * μ⁻ + ne⁺ * μ⁺) / (Δz)^2 #no interpolation on boundary
    A.dl[N - 1] = ne⁻ * μ⁻ / (Δz)^2
    #b[N] = -ϕ_R / ((Δz)^2) #no interpolation on boundary

    #interpolation on boundary
    A.d[1] = -1.5 * (ne⁻ * μ⁻ + ne⁺ * μ⁺) / (Δz)^2
    b[1] = -2*ϕ_L / ((Δz)^2)
    A.d[N] = -1.5 * (ne⁻ * μ⁻ + ne⁺ * μ⁺) / (Δz)^2
    b[N] = -2*ϕ_R / ((Δz)^2)


    OVS[1] = true
 end
