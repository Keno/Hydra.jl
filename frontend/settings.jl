using YAML

f = open("settings.yml")
settings = YAML.load(f)
close(f)

docker_hosts = settings["docker_hosts"]
ijulia_image = settings["ijulia_image"]
webdav_image = settings["webdav_image"]
passwd_webdav_container = settings["passwd_webdav_container"]