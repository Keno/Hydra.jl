using OpenStack
using JSON

function rsync(nova,token,server::Server,private_key,lpath,rpath; port = 22)
    ssh = "ssh -p $port -o StrictHostKeyChecking=no -i $private_key"
    run(`rsync -L --verbose --archive -z -e $ssh $lpath ubuntu@$(ips(nova,token,server)[1]):$rpath`)
end

ssh_cmd(nova,token,server::Server,private_key,cmd; port = 22) = 
    `ssh -p $port -o StrictHostKeyChecking=no -i $private_key ubuntu@$(ips(nova,token,server)[1]) $cmd`

image = Image("351fb917-505d-4c20-b3b4-f99e17689bfa")

include("signin.jl")

function get_server(sname; flavor = "s1.1core", fixed_ip = nothing)
    slist = servers(nova,token;name=sname)

    if isempty(slist)
        flist = flavors(nova,token)
        fflavor = flist[findfirst(x->x.name==flavor,flist)]
        networks = [
            {"uuid"=>"a4d00c60-f005-400e-a24c-1bf8b8308f98"}
            ]
        if fixed_ip === nothing
            unshift!(networks,{"uuid"=>"0a1d0a27-cffa-4de3-92c5-9d3fd3f2e74d"})
        else
            unshift!(networks,{"uuid"=>"0a1d0a27-cffa-4de3-92c5-9d3fd3f2e74d","fixed_ip"=>fixed_ip})
        end
        serv = createServer(nova,token,image,fflavor,sname;networks=networks,keyname = "IJulia") 
        wait_active(nova,token,serv)
        while true
            try 
                connect(ips(nova,token,serv)[1],22)
                break
            catch e
                @assert isa(e,Base.UVError)
                sleep(5.0)
            end
        end
    else 
        serv = slist[1]
    end

    serv
end

function provision(serv,recipes)
    cb_path = "/tmp/cookbooks/"

    solo_rb = """
        verbose_logging true
        file_cache_path "/tmp"
        file_backup_path "/tmp"
        log_level :info
        cookbook_path "$cb_path"
    """

    recipes = 

    solo_json = {
        "docker" => {
            "bind_uri" => "0.0.0.0:4243"
        },
        "run_list" => [ "recipe[$name]" for name in recipes ]
    }

    rsync(nova,token,serv,"ijulia.pem","cookbooks/",cb_path)
    cmd = (ssh_cmd(nova,token,serv,"ijulia.pem","cat > /tmp/solo.rb") .> STDERR)

    println(cmd)

    pp, p = writesto(cmd)
    write(pp,solo_rb)
    close(pp)

    pp, p = writesto(ssh_cmd(nova,token,serv,"ijulia.pem","cat > /tmp/solo.json") .> STDERR)
    write(pp,json(solo_json))
    close(pp)

    cmd = ssh_cmd(nova,token,serv,"ijulia.pem",
        "(chef-solo --version || 
         (sudo apt-get update && sudo apt-get install -q -y rubygems && sudo gem install chef --version 11.6.0)) && 
         sudo chef-solo -c /tmp/solo.rb -j /tmp/solo.json")

    run(cmd,(STDIN,STDOUT,STDERR))

end

function build_docker_container(serv::OpenStack.Server,port,c;cache = false)
    if cache
        run(`docker -H $(ips(nova,token,serv)[1]):$port build -t=$c $c/`)
    else
        run(`docker -H $(ips(nova,token,serv)[1]):$port -no-cache build -t=$c $c/`)
    end
end

function build_docker_container(serv::ASCIIString,port,c;cache = false)
    if cache
        run(`docker -H $serv:$port build -t=$c $c/`)
    else
        run(`docker -H $serv:$port build -no-cache -t=$c $c/`)
    end
end

function install_julia_dependencies(serv)
    run(ssh_cmd(nova,token,serv,"ijulia.pem","""git config --global user.email "kfischer@csail.mit.edu" """))
    run(ssh_cmd(nova,token,serv,"ijulia.pem","""git config --global user.name "Keno Fischer" """))
    run(ssh_cmd(nova,token,serv,"ijulia.pem","""julia -e 'Pkg.update(); Pkg.add("BinDeps"); Pkg.checkout("BinDeps"); Pkg.add("YAML"); Pkg.add("GnuTLS"); Pkg.checkout("GnuTLS"); Pkg.add("Morsel"); Pkg.add("JSON"); Pkg.add("SQLite"); Pkg.checkout("SQLite"); Pkg.add("Docker"); Pkg.add("Nettle")'"""))
    for pkg in ["HttpServer","HttpParser","Docker"]
        run(ssh_cmd(nova,token,serv,"ijulia.pem","""bash -c 'cd /home/ubuntu/.julia/$pkg && git checkout master && git pull https://github.com/loladiro/$pkg.jl'"""))
    end
end

function build_frontend(sname;ip=nothing)
    serv = get_server(sname; flavor = "m1.4core", fixed_ip=ip)
    provision(serv,["apt","build-essential","git","gfortran","ncurses","julia"])
    if !isfile("frontend/settings.yml") || (mtime("settings.yml") > mtime("frontend/settings.yml"))
        run(`cp settings.yml frontend/settings.yml`)
    end
    install_julia_dependencies(serv)
    rsync(nova,token,serv,"ijulia.pem","frontend/","/home/ubuntu/hydra")
end

function rsync_frontend(sname;ip=nothing)
    serv = get_server(sname; flavor = "m1.4core", fixed_ip=ip)
    rsync(nova,token,serv,"ijulia.pem","frontend/","/home/ubuntu/hydra")
end

function write_networking(serv)
    pp, p = writesto(ssh_cmd(nova,token,serv,"ijulia.pem","cat > /home/ubuntu/iptables.sh") .> STDERR)
    write(pp,iptables_script)
    close(pp)

    pp, p = writesto(ssh_cmd(nova,token,serv,"ijulia.pem","sudo sudo sh -c 'cat > /etc/network/interfaces'") .> STDERR)
    write(pp,interfaces)
    close(pp)

    pp, p = writesto(ssh_cmd(nova,token,serv,"ijulia.pem","sudo sudo sh -c 'cat > /etc/dhcp/dhclient.conf'") .> STDERR)
    write(pp,dhcpconfig)
    close(pp)

    run(ssh_cmd(nova,token,serv,"ijulia.pem","sudo restart networking"))
end

internal_network = Network("a4d00c60-f005-400e-a24c-1bf8b8308f98")
inet_network = Network("0a1d0a27-cffa-4de3-92c5-9d3fd3f2e74d")

frontend_instance = get_server("ijulia-frontend-1"; flavor = "m1.4core", fixed_ip="128.52.128.95")
frontend_ip = ips(nova,token,frontend_instance,"internal")[1]

dhcpconfig = """
option rfc3442-classless-static-routes code 121 = array of unsigned integer 8;

send host-name = gethostname();

request subnet-mask, broadcast-address, time-offset, routers,
        domain-name, domain-name-servers, domain-search, host-name,
        dhcp6.name-servers, dhcp6.domain-search,
        netbios-name-servers, netbios-scope, interface-mtu,
        rfc3442-classless-static-routes, ntp-servers,
        dhcp6.fqdn, dhcp6.sntp-servers;
"""

interfaces = """
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
auto eth0
iface eth0 inet dhcp

auto eth1
iface eth1 inet dhcp
dns-search ijulia.csail.mit.edu
dns-nameservers 8.8.8.8
"""

iptables_script = """
#!/bin/sh
# My system IP/set ip address of server
DOCKER_NETWORK="172.16.0.0/12"
FRONTEND_NODE="$(string(frontend_ip))"

# Flushing all rules
iptables -F
iptables -X
# Setting default filter policy
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP
# Allow unlimited traffic on loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A FORWARD -o lo -j ACCEPT

# Allow incoming ssh only
iptables -A INPUT -p tcp -s 0/0 --sport 513:65535 --dport 22 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -p tcp -d 0/0 --sport 22 --dport 513:65535 -m state --state ESTABLISHED -j ACCEPT

# Allow incoming docker
iptables -A INPUT -p tcp -s \$FRONTEND_NODE -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A FORWARD -p tcp -s \$FRONTEND_NODE -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -p tcp -d \$FRONTEND_NODE -m state --state ESTABLISHED -j ACCEPT

# Allow communication between the fontend node and the containers
iptables -A FORWARD -s \$DOCKER_NETWORK -d \$FRONTEND_NODE -j ACCEPT
iptables -A FORWARD -s \$FRONTEND_NODE -d \$DOCKER_NETWORK -j ACCEPT
iptables -A INPUT -s \$FRONTEND_NODE -d \$DOCKER_NETWORK -j ACCEPT

# Disallow container access to internal network
iptables -A FORWARD -s \$DOCKER_NETWORK -d 192.168.0.0/24 -j DROP

# But allow container network access otherwise
iptables -A FORWARD -s \$DOCKER_NETWORK -d 0/0 -j ACCEPT
iptables -A FORWARD -d \$DOCKER_NETWORK -s 0/0 -j ACCEPT

# Allow DNS resolution (for APT)
iptables -A OUTPUT -p udp --sport 1024:65535 --dport 53 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p udp --sport 53 --dport 1024:65535 -m state --state ESTABLISHED -j ACCEPT
iptables -A OUTPUT -p tcp --sport 1024:65535 --dport 53 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --sport 53 --dport 1024:65535 -m state --state ESTABLISHED -j ACCEPT

# Allow keyserver requests (port 11371)
iptables -A OUTPUT -p tcp --dport 11371 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --sport 11371 -m state --state ESTABLISHED -j ACCEPT

# Allow git clones (port 9418)
iptables -A OUTPUT -p tcp --dport 9418 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --sport 9418 -m state --state ESTABLISHED -j ACCEPT

# Allow HTTP and HTTPS access from this box for APT
iptables -A OUTPUT -p tcp --dport 80 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --sport 80 -m state --state ESTABLISHED -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -m state --state NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --sport 443 -m state --state ESTABLISHED -j ACCEPT

# make sure nothing else comes into this box
iptables -A INPUT -j DROP
"""