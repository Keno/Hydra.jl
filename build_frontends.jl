#!/Users/kfischer/julia/julia
include("openstack-test.jl")
if length(ARGS) == 1 && ARGS[1] == "rsync"
    rsync_frontend("ijulia-frontend-1",ip = "128.52.128.95")
else
    build_frontend("ijulia-frontend-1",ip = "128.52.128.95")
end
wait()