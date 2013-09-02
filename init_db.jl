using SQLite
 
co = SQLite.connect("users")

query("CREATE TABLE users (
     id INTEGER NOT NULL PRIMARY KEY ASC,
     username VARCHAR NOT NULL,
     ijulia_container CHAR(12),
     webdav_container CHAR(12)
)",co)
