#!/Users/kfischer/julia/julia
using OpenStack
include("signin.jl")
server = servers(nova,token;name=ARGS[1])[1]
run(`ssh -i ijulia.pem ubuntu@$(ips(nova,token,server)[1])`,(STDIN,STDOUT,STDERR))