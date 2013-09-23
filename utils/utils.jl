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

function start_rproxy(sess,upstream)
    c1 = Condition()
    c2 = Condition()
    @async begin
        try
            while isopen(sess) && isopen(upstream)
                write(upstream,readavailable(sess))
            end
        catch e
            showerror(STDOUT,e)
            println(STDOUT)
            Base.show_backtrace(STDOUT,Base.catch_backtrace())
        end
        notify(c1)
    end
    @async begin
        try
            while isopen(sess) && isopen(upstream)
                write(sess,readavailable(upstream))
            end
        catch e
            showerror(STDOUT,e)
            println(STDOUT)
            Base.show_backtrace(STDOUT,Base.catch_backtrace())
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
    set_priority_string!(sess)
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

