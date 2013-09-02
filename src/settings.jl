using YAML
f = open("../settings.yml")
settings = YAML.load(f)
close(f)
docker_host = settings["docker_host"]
