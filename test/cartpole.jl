using MeshCat
using TrajOptPlots
using TrajectoryOptimization
using RobotZoo
using ForwardDiff
const TO = TrajectoryOptimization
include("problems.jl")

vis = Visualizer()
open(vis)
set_mesh!(vis, RobotZoo.Cartpole())

prob = Cartpole(N=21)
ilqr = iLQRSolver(prob)
TO.solve!(ilqr)
visualize!(vis, ilqr)

n,m,N = size(prob)
Z0 = LQR.Primals(prob).Z
zinds = [(k-1)*(n+m) .+ (1:n+m) for k = 1:N]
zinds[end] = (N-1)*(n+m) .+ (1:n)

_zinds = [SVector{length(ind)}(ind) for ind in zinds]
function f(Z)
	_Z = [StaticKnotPoint(prob.Z[k], Z[_zinds[k]]) for k = 1:N]
	J = zeros(eltype(Z), N)
	TrajOptCore.cost!(prob.obj, _Z, J)
	return sum(J)
end

∇f(Z) = ForwardDiff.gradient(f, Z0)
∇²f(Z) = ForwardDiff.hessian(f, Z0)

function c(Z)
	_Z = [StaticKnotPoint(prob.Z[k], Z[_zinds[k]]) for k = 1:N]
	val = state(_Z[1]) - prob.x0
	for k = 1:N-1
		dyn = discrete_dynamics(RK3, prob.model, _Z[k]) - state(_Z[k+1])
		val = [val; dyn]
	end
	return val
end
c(Z0)

ForwardDiff.jacobian(c, Z0)


TO.solve!(pn)
@which cost_expansion!(pn)

TO.update!(pn)
begin
    TO.update_constraints!(pn)
    TO.constraint_jacobian!(pn)
    TO.update_active_set!(pn)
    TO.cost_expansion!(pn)
    TO.copyto!(pn.P, pn.Z)
    TO.copy_constraints!(pn)
    TO.copy_jacobians!(pn)
    TO.copy_active_set!(pn)
end
pn.g
max_violation(pn)
G0 = Diagonal(pn.H)
D0,d0 = TO.active_constraints(pn)
HinvD = G0\D0'
S = Symmetric(D0*HinvD)
Sreg = cholesky(S + pn.opts.ρ*I)
# TO._projection_linesearch!(pn, (S,Sreg), HinvD)
δλ = TO.reg_solve(S, d0, Sreg, 1e-8, 30)
norm(S*δλ - d0)
δλ = S\d0
δZ = -HinvD*δλ
pn.P̄.Z .= pn.P.Z + 1.0*δZ
copyto!(pn.Z̄, pn.P̄)
TO.update_constraints!(pn, pn.Z̄)
max_violation(pn, pn.Z̄)

max_violation(solver)
LQR.update!(solver)
D,d = solver.conSet.D, solver.conSet.d
G = solver.G
G ≈ G0
D ≈ D0
d ≈ d0
pn.g ≈ solver.g
LQR._solve!(solver) ≈ δZ

merit = TrajOptCore.L1Merit(1.0)
ϕ = merit(solver)
ϕ′ = TrajOptCore.derivative(merit, solver)
ls = TrajOptCore.SimpleBacktracking()
crit = TrajOptCore.WolfeConditions()

LQR.update!(solver)
ϕ(0)
ϕ′(0)
norm(solver.g - solver.conSet.D'solver.λ)
@show max_violation(solver)
findmax_violation(solver)
LQR._solve!(solver)
norm(solver.conSet.D*solver.δZ.Z + solver.conSet.d, Inf)
norm(solver.G*solver.δZ.Z + solver.g + solver.conSet.D'solver.λ,Inf)

TrajOptCore.line_search(ls, crit, ϕ, ϕ′)
copyto!(solver.Z.Z, solver.Z̄.Z)

α = 0.5
solver.Z̄.Z .= solver.Z.Z .+ α*solver.δZ.Z
max_violation(solver, solver.Z̄.Z_)
LQR.update!(solver, solver.Z̄)
plot(ϕ.(range(-1,1,length=10)))

visualize!(vis, prob.model, get_trajectory(solver))
visualize!(vis, ilqr)
