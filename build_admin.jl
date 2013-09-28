#!/Users/kfischer/julia/julia
include("openstack-test.jl")

function build_admin(sname)
    serv = get_server(sname; flavor = "m1.4core")

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

    rsync_admin(serv)
end

admin_networking(serv::OpenStack.Server) = write_networking(serv,"""
        iptables -A INPUT -p tcp -s 0/0 --dport 8080 -m state --state NEW,ESTABLISHED -j ACCEPT
        iptables -A OUTPUT -p tcp -d 0/0 --sport 8080 -m state --state ESTABLISHED -j ACCEPT

        iptables -A INPUT -p tcp -s 0/0 --dport 4244 -m state --state NEW,ESTABLISHED -j ACCEPT
        iptables -A OUTPUT -p tcp -d 0/0 --sport 4244 -m state --state ESTABLISHED -j ACCEPT

        # Allow incoming collectd metrics
        iptables -A INPUT -p udp --dport 25826 -s 192.168.0.0/24 -j ACCEPT

        # Allow free access to the local network from within the container
        iptables -A FORWARD -d \$DOCKER_NETWORK -j ACCEPT
        iptables -A INPUT -d \$DOCKER_NETWORK -j ACCEPT
    """)

admin_networking(sname) = admin_networking(get_server(sname; flavor = "m1.4core"))

rsync_admin(serv::OpenStack.Server) = rsync(nova,token,serv,"ijulia.pem","admin/","/home/ubuntu/admin")
rsync_admin(sname) = rsync_admin(get_server(sname; flavor = "m1.4core"))

if length(ARGS) == 1 
    if ARGS[1] == "rsync"
        @async rsync_admin("ijulia-admin")
    elseif ARGS[1] == "network"
        @async admin_networking("ijulia-admin")
    else
        error("Unrecognized command")
    end
else
    @async build_admin("ijulia-admin")
end
wait()