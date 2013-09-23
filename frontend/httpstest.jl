using GnuTLS
using SQLite
using Docker
using DataFrames
using Nettle
using Codecs
require("HttpServer")


co = SQLite.connect("users")

include("utils/utils.jl")
include("settings.jl")

function get_working_dir(cert)
    "/home/ubuntu/files/$(get_uid(cert))"
end


create_user_dir(docker_host,dir) = run(ssh_cmd(docker_host,"mkdir -p $dir"))

function wait_for_notebook(docker_host, db_id,container_id)
    c = Condition()
    @async begin
        stream = Docker.open_logs_stream(docker_host,container_id; history = true)
        while isopen(stream)
            if search(readline(stream),"The IPython Notebook is running") != 0:-1
                if container_id !== nothing
                    query("UPDATE users SET ready=1,ijulia_container=\"$container_id\" WHERE id = $db_id")
                else 
                    query("UPDATE users SET ready=1 WHERE id = $db_id")
                end
                notify(c)
                break
            end
        end
        close(stream)
    end
    @async begin
        while true
            sleep(5.0)
            if query("SELECT ready FROM users WHERE id = $db_id")["ready"] == 1
                notify(c)
                break
            end
        end
    end
    wait(c)
end

function start_ijulia_container(docker_host,working_dir)
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

function start_webdav_container(docker_host,docker_hostworking_dir)
    worker_id = Docker.create_container(docker_host,webdav_image,
                     `apache2 -D FOREGROUND`;
                     attachStdin =  true, 
                     openStdin   =  true,
                     ports       =  [80],
                     volumes     =  ["/files"])["Id"]
    Docker.start_container(docker_host,worker_id; binds = [working_dir=>"/files"])
    worker_id
end

function start_passwd_webdav_container(docker_host,working_dir)
    write_apache_files()
    worker_id = Docker.create_container(docker_host,passwd_webdav_container,
                     ``;
                     attachStdin =  true, 
                     openStdin   =  true,
                     ports       =  [80],
                     volumes     =  ["/files"])["Id"]
    Docker.start_container(docker_host,worker_id; binds = [working_dir=>"/files"])
    worker_id
end


const disable_webdav = true

if !disable_webdav
    #
    # Write the apache server configuration
    #
    function write_apache_files()
        println("Writing apache files")
        df = query("SELECT username,webdav_username,webdav_password FROM users WHERE webdav_username IS NOT NULL")
        emailmap,_ = writesto(ssh_cmd("cat > /home/ubuntu/files/emailmap.txt"))
        htpasswd,_ = writesto(ssh_cmd("cat > /home/ubuntu/files/users.pwd"))
        for r in EachRow(df)
            println(emailmap,r["webdav_username"][1],' ',r["username"][1])
            s = HashState(SHA1)
            update!(s,r["webdav_password"][1])
            println(htpasswd,r["webdav_username"][1],":{SHA}",bytestring(encode(Base64,digest!(s))))
        end
        close(emailmap)
        close(htpasswd)
    end

    # 
    # Find most recently started webdav container
    #
    function find_webdav_container(docker_host)
        containers = Docker.list_containers(docker_host)
        id = nothing
        for c in containers
            if c["Image"] == "$(passwd_webdav_container):latest"
                id = c["Id"]
                break
            end
        end
        if id === nothing
            id = start_passwd_webdav_container("/home/ubuntu/files")
        end
        id
    end


    # Cache webdav container id and update it every 10 seconds
    global webdav_id = find_webdav_container()
    @async while true
        global webdav_id
        sleep(10.0)
        webdav_id = find_webdav_container()
    end

end

isdead(host,id) = Docker.inspect_container(host,id)["State"]["Running"] == false

function retrieve_container_id(cert,servicename)
    #show(cert)
    service = services[servicename]
    uid = get_uid(cert)
    da = query("SELECT id,docker_host,$(service[1]),ready FROM users WHERE username = \"$uid\"",co)
    if isempty(da["id"]) || (length(da["id"]) == 1 && isna(da[service[1]][1]))
        if isempty(da["id"]) || (length(da["id"]) == 1 && isna(da["docker_host"][1]))
            docker_host = docker_hosts[rand(1:length(docker_hosts))]
        else
            docker_host = da["docker_host"][1]
        end
        create_user_dir(docker_host,get_working_dir(cert))
        container_id = service[2](docker_host,get_working_dir(cert))
        if (length(da["id"]) == 1) && isna(da[service[1]][1])
            query("UPDATE users SET docker_host=\"$docker_host\",$(service[1]) = \"$container_id\" WHERE id = $(da["id"][1])")
            id = da["id"][1]
        else
            query("INSERT INTO users (username,docker_host,$(service[1]),ready) VALUES(\"$uid\",\"$docker_host\",\"$container_id\",0)",co)
            # stopgap should use SQL last inserted id
            id = query("SELECT id FROM users WHERE username=\"$uid\"",co)["id"][1]
        end
        if service[6] !== nothing
            service[6](docker_host,id,container_id)
        else
            sleep(3)
        end
    elseif length(da["id"]) == 1
        docker_host = da["docker_host"][1]
        if isdead(docker_host,da[service[1]][1])
            query("UPDATE users SET $(service[1])=NULL,ready=0 WHERE id = $(da["id"][1])")
            return retrieve_container_id(cert,servicename)
        end
        if isna(da["ready"][1]) || da["ready"][1] == 0
            wait_for_notebook(docker_host,da["id"][1],nothing)
            da = query("SELECT id,$(service[1]) FROM users WHERE username = \"$uid\"",co)
        end
        container_id = da[service[1]][1]
    else
        error("Multiple entries with the same user id. Bailing!")
    end
    docker_host, container_id
end

const services = {
    "ijulia" => ("ijulia_container",start_ijulia_container,nothing,8000,8998,wait_for_notebook)
}


if !disable_webdav

    function handle_anon(sess)
        global webdav_id
        args = (Docker.docker_uri(docker_host).host,uint16(Docker.getNattedPort(docker_host,webdav_id,80)))
        start_rproxy(sess,connect(args...))
    end

    function webdav_credentials(cert)
        uid = get_uid(cert)
        dir = get_working_dir(cert)
        da = query("SELECT id,webdav_username,webdav_password FROM users WHERE username = \"$uid\"",co)
        if isempty(da["id"]) || (length(da["id"]) == 1 && isna(da["webdav_username"][1]))
            username,password = (randstring(12),randstring(12))
            if (length(da["id"]) == 1) && isna(da["webdav_username"][1])
                query("UPDATE users SET webdav_username=\"$username\",webdav_password=\"$password\" WHERE id = $(da["id"][1])")
            else
                query("INSERT INTO users (username,webdav_username,webdav_password) VALUES(\"$uid\",\"$username\",\"$password\")",co)
                create_user_dir(get_working_dir(cert))
            end
            write_apache_files()
        elseif length(da["id"]) == 1
            username,password = (da["webdav_username"][1],da["webdav_password"][1])
        else
            error("Multiple entries with the same user id. Bailing!")
        end
        username,password
    end

    services["webdav"] = ("webdav_container",start_webdav_container,handle_anon,8001,80,nothing)
end


# Reverse proxies
for (servicename,service) in services
    @async begin
        server = listen(service[4])
        try
            while true
                sess = accept_sess(server,service[3]===nothing)
                sess === nothing && continue
                cert = GnuTLS.get_peer_certificate(sess)
                if cert != nothing
                    dir = get_working_dir(cert)
                    docker_host,container_id = retrieve_container_id(cert,servicename)
                    args = (Docker.docker_uri(docker_host).host,uint16(Docker.getNattedPort(docker_host,container_id,service[5])))
                    start_rproxy(sess,connect(args...))
                elseif service[3] != nothing
                    service[3](sess)
                else
                    close(sess)
                end
            end
        catch e
            println("FATAL Server Error:", e)
        end
    end
end

using HttpServer

if !disable_webdav
    http = HttpHandler() do req::Request, res::Response, cert
        username,password = webdav_credentials(cert)
        Response(200,(String=>String)["Content-Type"=>"text/plain"],"Username: $username\nPassword: $password")
    end

    https = Server( http )

    # Exchange client certificates for WebDAV credentials
    server = listen(8002)
    try
        while true
            sess = accept_sess(server,true)
            sess === nothing && continue
            cert = GnuTLS.get_peer_certificate(sess)
            if cert != nothing
                try
                    client = HttpServer.Client(0, sess)
                    client.client_cert = cert
                    client.parser = HttpServer.ClientParser(HttpServer.message_handler(https, client, false))
                    @async HttpServer.process_client(https, client, false) 
                catch e
                    println(e)
                end
            else
                close(sess)
            end
        end
    catch e
        println("FATAL Server Error:", e)
    end
end

wait()
