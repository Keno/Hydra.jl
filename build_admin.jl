#!/Users/kfischer/julia/julia
include("openstack-test.jl")

function build_admin(sname)
    serv = get_server(sname; flavor = "m1.4core")

    write_networking(serv)

    run(ssh_cmd(nova,token,serv,"ijulia.pem","sudo bash /home/ubuntu/iptables.sh"))

    provision(serv,["apt","build-essential","git","gfortran","ncurses","julia","docker","shipyard"])

    begin
        port = rand(10000:30000)
        p = spawn((`ssh -N -n -p 22 -o StrictHostKeyChecking=no -L $port:localhost:4243 -i ijulia.pem ubuntu@$(ips(nova,token,serv)[1])` |> STDOUT) .>STDERR)
        sleep(4.0) #Wait while SSH session is being established
        build_docker_container("127.0.0.1",port,"collectd-graphite";cache = true)
        kill(p)
    end

    install_julia_dependencies(serv)

    rsync(nova,token,serv,"ijulia.pem","admin/","/home/ubuntu/admin")
end

@async build_admin("ijulia-admin")
wait()