using GnuTLS
using SQLite
using Docker
using DataFrames

include("settings.jl")

co = SQLite.connect("users")

function start_ijulia_container(working_dir)
    worker_id = Docker.create_container(docker_host,ijulia_image,
                     `ipython notebook --ip=\'*\' --profile=julia`;
                     attachStdin =  true, 
                     openStdin   =  true,
                     ports       =  [8998],
                     volumes     =  ["/files"],
                     pwd         =  "/files")["Id"] 
    Docker.start_container(docker_host,worker_id; binds = [working_dir=>"/files"])
    worker_id
end

function start_webdav_container(working_dir)
    worker_id = Docker.create_container(docker_host,webdav_image,
                     `apache2 -D FOREGROUND`;
                     attachStdin =  true, 
                     openStdin   =  true,
                     ports       =  [80],
                     volumes     =  ["/files"])["Id"] 
    println("/files:$working_dir")
    Docker.start_container(docker_host,worker_id; binds = [working_dir=>"/files"])
    worker_id
end

const services = {
    "ijulia" => ("ijulia_container",start_ijulia_container,8000,8998),
    "webdav" => ("webdav_container",start_webdav_container,8001,80)
}


function retrieve_container_id(cert,servicename)
    #show(cert)
    service = services[servicename]
    uid = nothing
    i = 0
    while true
        oid = bytestring(GnuTLS.subject(cert)[i,0].ava.oid)
        if oid == "1.2.840.113549.1.9.1\0"
            uid = bytestring(GnuTLS.subject(cert)[i,0].ava.value)
            break
        end
        i += 1
    end
    if uid === nothing
        error("Certificate did not contain email address")
    end
    da = query("SELECT id,$(service[1]) FROM users WHERE username = \"$uid\"",co)
    if isempty(da["id"]) || (length(da["id"]) == 1 && isna(da[service[1]][1]))
        container_id = service[2]("/home/ubuntu/files/$uid")
        if (length(da["id"]) == 1) && isna(da[service[1]][1])
            query("UPDATE users SET $(service[1]) = \"$container_id\" WHERE id = $(da["id"][1])")
        else
            query("INSERT INTO users (username,$(service[1])) VALUES(\"$uid\",\"$container_id\")",co)
        end
        sleep(1.5)
    elseif length(da["id"]) == 1
        container_id = da[service[1]][1]
    else
        error("Multiple entries with the same user id. Bailing!")
    end
    container_id
end

auth = GnuTLS.CertificateStore()
GnuTLS.load_certificate(auth,"cert/server.crt","cert/server.key",true)


# Reverse proxies
for (servicename,service) in services
    @async begin
        server = listen(service[3])
        try
            while true
                sess = GnuTLS.Session(true)
                set_priority_string!(sess)
                set_credentials!(sess,auth)
                GnuTLS.set_prompt_client_certificate!(sess,true)
                gc()
                client = accept(server)
                associate_stream(sess,client)
                try
                    handshake!(sess)
                catch e
                    println("Error establishing SSL connection: ", e)
                    close(client)
                    continue
                end
                container_id = retrieve_container_id(GnuTLS.get_peer_certificate(sess),servicename)
                args = (Docker.docker_uri(docker_host).host,uint16(Docker.getNattedPort(docker_host,container_id,service[4])))
                upstream = connect(args...)
                c1 = Condition()
                c2 = Condition()
                @async begin
                    try
                        while isopen(sess) && isopen(upstream)
                            write(upstream,readavailable(sess))
                        end
                    catch e
                        println(e)
                    end
                    notify(c1)
                end
                @async begin
                    try
                        while isopen(sess) && isopen(upstream)
                            write(sess,readavailable(upstream))
                        end
                    catch e
                        println(e)
                    end
                    notify(c2)
                end
                @async begin
                    wait(c1)
                    wait(c2)
                    isopen(sess) && close(sess)
                    isopen(upstream) && close(upstream)
                end
            end
        catch e
            println("FATAL Server Error:", e)
        end
    end
end
wait()