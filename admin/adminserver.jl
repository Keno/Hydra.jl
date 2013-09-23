using GnuTLS
using SQLite
using Docker
using DataFrames

include("utils.jl")
docker_host = "127.0.0.1:4243"


function find_container(start_func,docker_host,image)
    containers = Docker.list_containers(docker_host)
    id = nothing
    for c in containers
        if c["Image"] == "$(passwd_webdav_container):latest"
            id = c["Id"]
            break
        end
    end
    if id === nothing
        id = start_func(image)
    end
    id
end

find_collectd_container(docker_host) = find_container(docker_host,"collectd-graphite") do
    worker_id = Docker.create_container(docker_host,passwd_webdav_container,
                     ``;
                     attachStdin =  true, 
                     openStdin   =  true)["Id"]
    Docker.start_container(docker_host,worker_id)
    worker_id
end

function adminserver(port,thunk)
    @async begin 
        server = listen(port)
        try
            while true
                sess = accept_sess(server,service[3]===nothing)
                sess === nothing && continue
                cert = GnuTLS.get_peer_certificate(sess)
                if cert != nothing
                    if get_uid(cert) == "kfischer@CSAIL.MIT.EDU"
                        thunk(sess)
                    else
                        close(sess)
                    end
                else
                    close(sess)
                end
            end
        catch e
            println("FATAL Server Error:", e)
        end
    end
end

adminserver(4243) do sess
    start_rproxy(sess,connect("127.0.0.1",4243))
end

adminserver(8080) do sess
    container_id = find_collectd_container(docker_host)
    args = (Docker.docker_uri(docker_host).host,uint16(Docker.getNattedPort(docker_host,container_id,8080)))
    start_rproxy(sess,connect(args...))
end

