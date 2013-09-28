#!/Users/kfischer/julia/julia
include("openstack-test.jl")

function build_backend(sname)
    serv = get_server(sname; flavor = "lg.12core")

    backend_networking(serv)
    provision(serv,["apt","build-essential","git","gfortran","ncurses","julia","docker"])
    run(ssh_cmd(nova,token,serv,"ijulia.pem","sudo stop docker && sudo start docker"))
    install_collectd(serv)
    build_docker_containers(sname)
end


backend_networking(sname) = backend_networking(get_server(sname; flavor = "m1.12core"))
function backend_networking(serv::OpenStack.Server)
    write_networking(serv,"""
        # Allow communication between the fontend node and the containers
        iptables -A FORWARD -s \$DOCKER_NETWORK -d \$FRONTEND_NODE -j ACCEPT
        iptables -A FORWARD -s \$FRONTEND_NODE -d \$DOCKER_NETWORK -j ACCEPT
        iptables -A INPUT -s \$FRONTEND_NODE -d \$DOCKER_NETWORK -j ACCEPT

        # Disallow inter-container communication
        iptables -A FORWARD -s \$DOCKER_NETWORK -d \$DOCKER_NETWORK -j ACCEPT
        iptables -A FORWARD -d \$DOCKER_NETWORK -s \$DOCKER_NETWORK -j ACCEPT

        # Disallow container access to internal network
        iptables -A FORWARD -s \$DOCKER_NETWORK -d 192.168.0.0/24 -j DROP
    """)
end

function build_docker_containers(sname)
    serv = get_server(sname; flavor = "m1.12core")
    port = rand(10000:30000)
    p = spawn((`ssh -N -n -p 22 -o StrictHostKeyChecking=no -L $port:localhost:4243 -i ijulia.pem ubuntu@$(ips(nova,token,serv)[1])` |> STDOUT) .>STDERR)
    sleep(4.0) #Wait while SSH session is being established
    build_docker_container("127.0.0.1",port,"julia-container")
    build_docker_container("127.0.0.1",port,"webdav-container")
    build_docker_container("127.0.0.1",port,"webdav-passwd-container")
    kill(p)
end

if length(ARGS) >= 1 
    if ARGS[1] == "rsync"
        f = rsync_backend
    elseif ARGS[1] == "network"
        f = backend_networking
    elseif ARGS[1] == "container"
        f = build_docker_container
    else
        error("Unrecognized command")
    end
else
    error("must specify a command")
end
if length(ARGS) != 2
    error("must specify a container")
end
if ARGS[2] == "all"
    for b in ["ijulia-backend-0","ijulia-backend-2","ijulia-backend-3"]
        f(b)
    end
else
    f(ARGS[2])
end
wait()