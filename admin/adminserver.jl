using GnuTLS
using SQLite
using Docker
using DataFrames

include("utils/utils.jl")
docker_host = "127.0.0.1:4243"

#ccall((:gnutls_global_set_log_level,GnuTLS.gnutls),Void,(Cint,),10)

function find_container(start_func,docker_host,image)
    containers = Docker.list_containers(docker_host)
    id = nothing
    for c in containers
        if c["Image"] == "$(image):latest"
            id = c["Id"]
            break
        end
    end
    if id === nothing
        id = start_func(image)
    end
    id
end

find_collectd_container(docker_host) = find_container(docker_host,"collectd-graphite") do image
    worker_id = Docker.create_container(docker_host,image,
                     ``;
                     attachStdin =  true, 
                     openStdin   =  true)["Id"]
    Docker.start_container(docker_host,worker_id)
    worker_id
end

function adminserver(thunk,port)
    @async begin 
        server = listen(port)
        try
            while true
                sess = accept_sess(server,true)
                sess === nothing && continue
                cert = GnuTLS.get_peer_certificate(sess)
                if cert != nothing
                    if get_uid(cert) == "kfischer@CSAIL.MIT.EDU"
                        try 
                            thunk(sess)
                        catch e
                            Base.showerror(STDOUT,e)
                            Base.show_backtrace(STDOUT,catch_backtrace())
                        end
                    else
                        close(sess)
                    end
                else
                    close(sess)
                end
            end
        catch e
            println("FATAL Server Error:")
            Base.showerror(STDOUT,e)
            Base.show_backtrace(STDOUT,catch_backtrace())
        end
    end
end

adminserver(4244) do sess
    start_rproxy(sess,connect("127.0.0.1",4243))
end

adminserver(8080) do sess
    container_id = find_collectd_container(docker_host)
    args = (Docker.docker_uri(docker_host).host,uint16(Docker.getNattedPort(docker_host,container_id,8080)))
    start_rproxy(sess,connect(args...))
end

wait()