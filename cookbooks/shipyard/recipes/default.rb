chef_gem "json" do
    action :install
end

docker_image "ehazlett/shipyard"
docker_container "ehazlett/shipyard" do
    command ""
    #port 8000
    detach true
end
