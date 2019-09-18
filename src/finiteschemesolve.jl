##############################################################################
##
## Non Linear solver using Pseudo-Transient Continuation Method
##
##############################################################################

# Implicit time step
function implicit_timestep(F!, ypost, Δ; is_algebraic = fill(false, size(ypost)...), iterations = 100, verbose = true, method = :newton, autodiff = :forward, maxdist = 1e-9, J0c = (nothing, nothing))
    F_helper!(ydot, y) = (F!(ydot, y) ; ydot .+= .!is_algebraic .* (ypost .- y) ./ Δ)
    J0, colorvec = J0c
    if J0 == nothing
        result = nlsolve(F_helper!, ypost; iterations = iterations, show_trace = verbose, ftol = maxdist, method = method, autodiff = autodiff)
    else
        if autodiff == :forward
            jac_cache = ForwardColorJacCache(F_helper!, deepcopy(ypost); colorvec = colorvec, sparsity = J0)
            j_helper! = (J, y) -> forwarddiff_color_jacobian!(J, F_helper!, y, jac_cache)
        else
            j_helper! = (J, y) -> DiffEqDiffTools.finite_difference_jacobian!(J, F_helper!, y; colorvec = colorvec)
        end
        result = nlsolve(OnceDifferentiable(F_helper!, j_helper!, deepcopy(ypost), deepcopy(ypost), J0), ypost; iterations = iterations, show_trace = verbose, ftol = maxdist, method = method)
    end
    return result.zero, result.residual_norm
end

# Solve for steady state
function finiteschemesolve(F!, y0; Δ = 1.0, is_algebraic = fill(false, size(y0)...), iterations = 100, inner_iterations = 10, verbose = true, inner_verbose = false, method = :newton, autodiff = :forward, maxdist = 1e-9, scale = 10.0, J0c = (nothing, nothing))
    ypost = y0
    ydot = zero(y0)
    F!(ydot, ypost)
    distance = norm(ydot) / length(ydot)
    isnan(distance) && throw("F! returns NaN with the initial value")
    if Δ == Inf
        ypost, distance = implicit_timestep(F!, y0, Δ; is_algebraic = is_algebraic, verbose = verbose, iterations = iterations,  method = method, autodiff = autodiff, maxdist = maxdist, J0c = J0c)
    else
        coef = 1.0
        olddistance = distance
        iter = 0
        while (iter < iterations) & (Δ >= 1e-12) & (distance > maxdist)
            iter += 1
            y, nldistance = implicit_timestep(F!, ypost, Δ; is_algebraic = is_algebraic, verbose = inner_verbose, iterations = inner_iterations, method = method, autodiff = autodiff, maxdist = maxdist, J0c = J0c)
            F!(ydot, y)
            distance, olddistance = norm(ydot) / length(ydot), distance
            distance = isnan(distance) ? Inf : distance
            if nldistance <= maxdist
                # if the implicit time step is correctly solved
                verbose && @show iter, Δ, distance
                coef = (distance <= olddistance) ? scale * coef : 1.0
                Δ = Δ * coef * olddistance / distance
                ypost, y = y, ypost
            else
                verbose && @show iter, Δ, NaN
                # if the implict time step is not solved
                # revert and diminish the time step
                coef = 1.0
                Δ = Δ / 10
                distance = olddistance
            end
        end
    end
    verbose && (distance > maxdist) && @warn "Iteration did not converge"
    return ypost, distance
end





