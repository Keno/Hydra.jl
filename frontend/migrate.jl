function migrate(host1,host2)
    run(`rm -rf /home/ubuntu/files-migrate/`)
    run(rsync_cmd(host1,"/home/ubuntu/files-migrate/","/home/ubuntu/files/";reverse=true))
    run(rsync_cmd(host2,"/home/ubuntu/files-migrate/","/home/ubuntu/files/"))
    query("UPDATE users SET ijulia_container=NULL,ready=0,docker_host=\"$host2\" WHERE docker_host=\"$host1\"")
    # TODO: live migration
end