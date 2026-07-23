Vagrant.configure(2) do |config|
  config.vm.box = "windows-2022-uefi-amd64" # see https://github.com/rgl/windows-vagrant
  config.vm.provider "libvirt" do |lv, config|
    lv.memory = 4*1024
    lv.cpus = 4
    lv.cpu_mode = "host-passthrough"
    lv.keymap = "pt"
    config.vm.synced_folder ".", "/vagrant", type: "smb", smb_username: ENV["USER"], smb_password: ENV["VAGRANT_SMB_PASSWORD"]
  end
  config.vm.provision "shell", inline: "$env:chocolateyVersion = '2.7.3'; Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')", name: "Install Chocolatey"
  config.vm.provision "shell", path: "setup.ps1"
end
