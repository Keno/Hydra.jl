apt_repository "julia-deps" do
  uri "http://ppa.launchpad.net/staticfloat/julia-deps/ubuntu"
  distribution node['lsb']['codename']
  components ["main"]
  keyserver "keyserver.ubuntu.com"
  key "3D3D3ACC"
end
apt_repository "julianighlies" do
  uri "http://ppa.launchpad.net/staticfloat/julianightlies/ubuntu"
  distribution node['lsb']['codename']
  components ["main"]
  keyserver "keyserver.ubuntu.com"
  key "3D3D3ACC"
end
package "julia"
