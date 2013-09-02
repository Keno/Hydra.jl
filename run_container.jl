using Docker
using URIParser

include("settings.jl")

worker_id = Docker.create_container(docker_host,docker_image,
                 `ipython notebook --ip=\'*\' --profile=julia`;
                 attachStdin =  true, 
                 openStdin   =  true,
                 ports       =  [8998])["Id"] 
Docker.start_container(docker_host,worker_id)
port = uint16(Docker.getNattedPort(docker_host,worker_id,8998))

url = URI(Docker.docker_uri(docker_host); port = port, path = "")

sleep(0.5)

run(`open $(string(url))`)