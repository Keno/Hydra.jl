FROM ubuntu:12.10
MAINTAINER "Keno Fischer"<kfischer@college.harvard.edu>
run apt-get update
run DEBIAN_FRONTEND=noninteractive apt-get install software-properties-common -y
run DEBIAN_FRONTEND=noninteractive apt-get install python-software-properties -y
run sudo add-apt-repository ppa:staticfloat/julia-deps -y
run sudo add-apt-repository ppa:staticfloat/julianightlies -y
run DEBIAN_FRONTEND=noninteractive apt-get update -qq -y
run DEBIAN_FRONTEND=noninteractive apt-get install libpcre3-dev julia -y
run DEBIAN_FRONTEND=noninteractive apt-get install python-pip python-dev -y
run pip install ipython jinja2 tornado pyzmq
run DEBIAN_FRONTEND=noninteractive apt-get install curl -y
run DEBIAN_FRONTEND=noninteractive apt-get install libnettle4 -y
run julia -e 'Pkg.init(); Pkg.clone("https://github.com/staticfloat/Nettle.jl"); Pkg.add("IJulia"); Pkg.checkout("IJulia"); Pkg.add("PyPlot"); Pkg.fixup()'
run ln -s /usr/bin/julia-release-basic /usr/bin/julia-basic
run mkdir /.ipython/profile_default
run (echo "from IPython.external.mathjax import install_mathjax"; echo "install_mathjax(dest=\"/.ipython/profile_julia/static/mathjax\")") | python
