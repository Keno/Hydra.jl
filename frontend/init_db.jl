using SQLite
 
co = SQLite.connect("users")

query("CREATE TABLE users (
     id INTEGER NOT NULL PRIMARY KEY ASC,
     username VARCHAR NOT NULL,
     docker_host VARCHAR NOT NULL,
     ijulia_container CHAR(12),
     webdav_container CHAR(12),
     webdav_username CHAR(12),
     webdav_password CHAR(12),
     ready INTEGER NOT NULL
)",co)

query("CREATE TABLE admin_services (
     id INTEGER NOT NULL PRIMARY KEY ASC,
     container CHAR(12) NOT NULL,
     port INTEGER NOT NULL,
     service_port INTEGER NOT NULL
)",co)