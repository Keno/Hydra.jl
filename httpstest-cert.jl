using GnuTLS

auth = GnuTLS.CertificateStore()
GnuTLS.load_certificate(auth,"cert/server.crt","cert/server.key",true)


server = listen(8000)

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
    c = GnuTLS.get_peer_certificate(sess)
    show(c)
    show(bytestring(GnuTLS.subject(c)[6,0].ava.value))
    close(client)
end