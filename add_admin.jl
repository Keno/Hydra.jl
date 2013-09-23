using SQLite
using DataFrames

co = SQLite.connect("users")

print("Enter Docker ID: ")
did = chomp(readline(STDIN))
@assert length(did) == 12
print("Enter port on which to expose interface: ")
pi = parseint(chomp(readline(STDIN)))
print("Enter port inside the container: ")
pc = parseint(chomp(readline(STDIN)))

query("INSERT INTO admin_services (container,port,service_port) VALUES (\"$did\",$pi,$pc)")