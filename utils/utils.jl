using GnuTLS
using SQLite
using Docker
using DataFrames

function get_uid(cert)
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
    uid
end

n = 0

function start_rproxy(sess,upstream)
    c1 = RemoteRef()
    c2 = RemoteRef()
    @async begin
        try
            while isopen(upstream) && !eof(sess)
                data = readavailable(sess)
                if isopen(upstream) && length(data) > 0
                    write(upstream,data)
                else
                    break
                end
            end
        catch e
            println(STDOUT)
            showerror(STDOUT,e)
            Base.show_backtrace(STDOUT,Base.catch_backtrace())
        end
        put(c1,())
    end
    @async begin
        try
            while isopen(sess) && !eof(upstream)
                data = readavailable(upstream)
                if isopen(sess) && length(data) > 0
                    write(sess,data)
                else
                    break
                end
            end
        catch e
            println(STDOUT)
            showerror(STDOUT,e)
            Base.show_backtrace(STDOUT,Base.catch_backtrace())
        end
        put(c2,())
    end
    @async begin
        take(c1)
        take(c2)
        try; isopen(sess) && close(sess); end
        try; isopen(upstream) && close(upstream); end
    end
end

ssh_cmd(docker_host, cmd; port = 22) = 
    `ssh -p $port -o StrictHostKeyChecking=no -i ijulia.pem ubuntu@$(Docker.docker_uri(docker_host).host) $cmd` .> STDERR

function rsync_cmd(docker_host,lpath,rpath; port = 22, reverse = false)
    ssh = "ssh -p $port -o StrictHostKeyChecking=no -i ijulia.pem"
    if reverse
        return `rsync --verbose --archive -z -e $ssh ubuntu@$(Docker.docker_uri(docker_host).host):$rpath $lpathe`
    else
        return `rsync --verbose --archive -z -e $ssh $lpath ubuntu@$(Docker.docker_uri(docker_host).host):$rpath`
    end
end


const auth = GnuTLS.CertificateStore()
GnuTLS.load_certificate(auth,"cert/server.crt","cert/server.key",true)
GnuTLS.add_trusted_ca(auth,"trust/master.cer")
GnuTLS.add_trusted_ca(auth,"trust/mitca.crt")
GnuTLS.add_trusted_ca(auth,"trust/cacert.crt",true)
GnuTLS.add_trusted_ca(auth,"trust/client.cer")
GnuTLS.add_trusted_ca(auth,"trust/mitClient.crt")

function accept_sess(server,req)
    sess = GnuTLS.Session(true)
    set_priority_string!(sess,"NONE:+VERS-TLS-ALL:+MAC-ALL:+RSA:+AES-128-CBC:+SIGN-ALL:+COMP-NULL")
    set_credentials!(sess,auth)
    GnuTLS.set_prompt_client_certificate!(sess,req)
    gc()
    client = accept(server)
    associate_stream(sess,client)
    try
        handshake!(sess)
    catch e
        println("Error establishing SSL connection: ", e)
        close(client)
        return nothing
    end
    sess
end

