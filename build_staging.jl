#!/Users/kfischer/julia/julia
include("openstack-test.jl")
if length(ARGS) == 1 && ARGS[1] == "rsync"
    rsync_frontend("ijulia-staging",ip = "128.52.128.98")
else
    build_frontend("ijulia-staging",ip = "128.52.128.98")
end
wait()