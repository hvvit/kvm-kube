# kubekvm
Project to spin up multiple kvm based vms with ubuntu cloud images and start a localised kubernetes cluster.
Requirements
>>Bridged adaptor.
execute "sudo bash add-bridge"
Note: "Only works if default enterface is enp2s0"
>> packages:
sudo apt update
sudo apt install nmap sshpass net-tools bridge-utils cloud-init cloud-image-utils qemu-kvm libvirt-bin virtinst cpu-checker
