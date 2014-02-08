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
run sudo apt-get install -y libfreetype6-dev libpng-dev
run easy_install -U distribute
run pip install jinja2 tornado pyzmq numpy 
run pip install matplotlib
run git clone https://github.com/ipython/ipython.git
run (cd ipython && python setup.py install)
run DEBIAN_FRONTEND=noninteractive apt-get install curl -y
run DEBIAN_FRONTEND=noninteractive apt-get install libnettle4 -y
run julia -e 'Pkg.init(); Pkg.clone("https://github.com/staticfloat/Nettle.jl"); Pkg.add("IJulia"); Pkg.checkout("IJulia"); Pkg.add("PyPlot"); Pkg.add("Gadfly"); Pkg.checkout("JSON"); Pkg.fixup()'
run (echo "from IPython.external.mathjax import install_mathjax"; echo "install_mathjax(dest=\"/.ipython/profile_julia/static/mathjax\")") | python
ADD 02assumeyes /etc/apt/apt.conf.d/02assumeyes
