include("openstack-test.jl")

function build_backend(sname)
    serv = get_server(sname; flavor = "lg.12core")

    # Running this script will silently drop the SSH connection temporarily, but the client won't notice.
    # Since the server doesn't accept packages if the connection isn't already established, this command will never 
    # return. 10 seconds should be enough to overcome that
    @async run(ssh_cmd(nova,token,serv,"ijulia.pem","sudo bash /home/ubuntu/iptables.sh"))
    sleep(10.0)

    provision(serv,["apt","build-essential","git","gfortran","ncurses","julia","docker"])
    run(ssh_cmd(nova,token,serv,"ijulia.pem","sudo stop docker && sudo start docker"))
    build_docker_containers(sname)
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

if length(ARGS) == 1 && ARGS[1] == "containers"
    f = build_docker_containers
else
    f = build_backend
end

f("ijulia-backend-0")
wait()