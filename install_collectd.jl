include("openstack-test.jl")

for x in ["ijulia-frontend-1","ijulia-admin","ijulia-staging","ijulia-backend-0","ijulia-backend-3","ijulia-backend-3"]
    serv = get_server(x)
    install_collectd(serv)
end
