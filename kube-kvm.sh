#!/bin/bash
#author: harsh.vardhan7896@gmail.com
#sudo nmap -sP 172.31.201.0/24 | awk '/Nmap scan report for/{printf $5;}/MAC Address:/{print " => "$3;}' | sort
echo "Make sure user has password less sudo setup for automation"
############## Exporting Variables #####################
export CONFIGDIR=~/.config/kube-kvm
export IMGDIR=$CONFIGDIR/IMGDIR
export CLUSTERDIR=$CONFIGDIR/CLUSTERDIR
export CLOUDCONFIGDIR=$CONFIGDIR/CLOUDCONFIGDIR
export VMINFODIR=$CLUSTERDIR/VMINFODIR
export SCRIPTDIR=$CLUSTERDIR/SCRIPTDIR
mkdir -pv {$VMINFODIR,$CLOUDCONFIGDIR,$CLUSTERDIR,$IMGDIR,$SCRIPTDIR}
############## Ubuntu Script for kube-installation ####

cat << eof > $SCRIPTDIR/ubuntu.sh
# Install Docker CE
## Set up the repository:
### Install packages to allow apt to use a repository over HTTPS
sudo apt-get update && sudo apt-get install apt-transport-https ca-certificates curl software-properties-common -y

### Add Docker’s official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

### Add Docker apt repository.
sudo add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
  \$(lsb_release -cs) \
  stable"

## Install Docker CE.
sudo apt-get update && apt-get install docker-ce=18.06.2~ce~3-0~ubuntu -y

# Setup daemon.
sudo cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

sudo mkdir -p /etc/systemd/system/docker.service.d

# Restart docker.
sudo systemctl daemon-reload
sudo systemctl restart docker

sudo apt-get update && sudo apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
sudo cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
eof

############## get network route #######################
function getRoute(){
  interface=${1}
  route | grep $interface | awk '$1 ~ 192{print $1}' | awk -F "." '{print $1"."$2"."$3".*"}'
}
############## ssh-public-key check   ##################
if [ -f ~/.ssh/id_rsa.pub ];
then
  echo "Using id_rsa.pub for passwordless-ssh"
  export public_key=$(cat ~/.ssh/id_rsa.pub)
else
  echo "Please generate public key for your machine by running the following command."
  echo "ssh-keygen -t rsa"
  exit 1
fi

############## Cloud Image Decider #####################

function downloadImage(){
  tagName=${1}
  if [ "$tagName" == "Ubuntu18.04" ];
  then
    echo "downloading image bionic-server-cloudimg-amd64.img"
    wget -c https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img -P $IMGDIR
    if [ -f ${IMGDIR}/bionic-server-cloudimg-amd64_base.img ];
    then
      echo "Base image for cloud config already exists..."
    else
      echo "creating base image for the cloud config..."
      echo "This may take some time...."
      cp ${IMGDIR}/bionic-server-cloudimg-amd64.img ${IMGDIR}/bionic-server-cloudimg-amd64_base.img
      qemu-img resize ${IMGDIR}/bionic-server-cloudimg-amd64_base.img +10G
    fi
  fi
}
function getImageName(){
  tagName=${1}
  if [ "$tagName" == "Ubuntu18.04" ];
  then
    echo "$IMGDIR/bionic-server-cloudimg-amd64.img"
  fi
}

############## Cluster Creator #########################

function clusterCreator(){
  clusterName=$1
  masterCount=$2
  slaveCount=$3
  clusterInterface=$4
  imgName=$5
  echo $imagName
  imageInfo=$(getImageName $imgName)
  echo $imageInfo
  ((totalCount=masterCount+slaveCount))
  for ((i=1;i<=$masterCount;i++));
  do
      rm -f $IMGDIR/${clusterName}_master_${i}.img
      qemu-img convert -f qcow2 -O qcow2 $IMGDIR/bionic-server-cloudimg-amd64_base.img $IMGDIR/${clusterName}_master_${i}.img
 done
 for ((i=1;i<=$slaveCount;i++));
 do
      rm -f $IMGDIR/${clusterName}_slave_${i}.img
      qemu-img convert -f qcow2 -O qcow2 $IMGDIR/bionic-server-cloudimg-amd64_base.img $IMGDIR/${clusterName}_slave_${i}.img
  done
  for ((i=1;i<=$masterCount;i++));
  do
      clusterhostname=${clusterName}_master_$i
      virsh destroy $clusterhostname
      virsh undefine $clusterhostname
      sudo virt-install 	--name $clusterhostname	--memory 4096 --vcpus 2 --disk $IMGDIR/${clusterName}_master_${i}.img,device=disk,bus=virtio --disk $IMGDIR/${clusterName}_master_${i}_definitiion.img,device=cdrom --os-type linux --os-variant ubuntu18.04 --network bridge:br0,model=virtio --graphics none --noautoconsole --import
  done
  for ((i=1;i<=$slaveCount;i++));
  do
      clusterhostname=${clusterName}_slave_$i
      virsh destroy $clusterhostname
      virsh undefine $clusterhostname
      sudo virt-install 	--name $clusterhostname	--memory 2048 --vcpus 2 --disk $IMGDIR/${clusterName}_slave_${i}.img,device=disk,size=20,bus=virtio --disk $IMGDIR/${clusterName}_slave_${i}_definitiion.img,device=cdrom --os-type linux --os-variant ubuntu18.04 --network bridge:br0,model=virtio --graphics none --noautoconsole --import
  done
}

############## Cloud Import image     ##################

function importImgCreatorForce(){
fileName=${1}_definitiion.img
configTxt=${1}.config
rm -f $IMGDIR/$fileName
cloud-localds $IMGDIR/$fileName $CLOUDCONFIGDIR/$configTxt
}

############## Cloud Config FUNCTIONS ##################
function cloudConfigCreator(){
  clusterName=$1
  masterCount=$2
  slaveCount=$3
  clusterInterface=$4
  imgName=$5
  checkInterface=$(brctl show | grep $clusterInterface | wc -l)
  echo "cluster name : " $clusterName
  if [ "$checkInterface" -gt 0 ];
  then
    downloadImage $imgName
  for ((i=1;i<=masterCount;i++));
  do
    clusterhostname=${clusterName}_master_$i
    cat << EOF > $CLOUDCONFIGDIR/$clusterhostname.config
#cloud-config
password: toor
chpasswd: { expire: False  }
ssh_pwauth: True
hostname: $clusterhostname
sudo: ALL=(ALL) NOPASSWD:ALL
runcmd:
  - echo "$public_key" >> /home/ubuntu/.ssh/authorized_keys
EOF
importImgCreatorForce $clusterhostname
done
for ((i=1;i<=slaveCount;i++));
do
  clusterhostname=${clusterName}_slave_$i
  cat << EOF > $CLOUDCONFIGDIR/$clusterhostname.config
#cloud-config
password: toor
chpasswd: { expire: False  }
ssh_pwauth: True
hostname: $clusterhostname
sudo: ALL=(ALL) NOPASSWD:ALL
runcmd:
- echo "$public_key" >> /home/ubuntu/.ssh/authorized_keys
EOF
importImgCreatorForce $clusterhostname
done
else
  echo "interface $clusterInterface does not exists"
fi
}
############## get ip info   #########################

function ipInfo(){
  clusterName=$1
  masterCount=$2
  slaveCount=$3
  clusterInterface=$4
  gateway=$(getRoute $clusterInterface)
  echo "sleeping for 30 seconds before starting nmap scan"
  sleep 30s
  sudo nmap -sP $gateway | awk '/Nmap scan report for/{printf $6;}/MAC Address:/{print "=>"tolower($3);}' | sort > $CLUSTERDIR/$clusterName.info
#  arp -na | awk '{print $2"=>"$4}' | tr -d "()" > $CLUSTERDIR/$clusterName.info
  cat $CLUSTERDIR/${clusterName}.info
  for ((i=1;i<=masterCount;i++));
  do
    mac=$(virsh domiflist ${clusterName}_master_${i} | awk '$2=="bridge"{print $NF}')
    ip=$(cat $CLUSTERDIR/${clusterName}.info | awk -F "=>" -v mac="$mac" '$2==mac{print $1}')
    #ip=$(arp -na | awk -v mac=$(virsh domiflist ${clusterName}_master_$i | awk '$2=="bridge"{print $NF}') '$0 ~ " at " mac {gsub("[()]", "", $2); print $2}')
    while [ "$ip" == "" ];
    do
      sudo nmap -sP $gateway | awk '/Nmap scan report for/{printf $6;}/MAC Address:/{print "=>"tolower($3);}' | sort > $CLUSTERDIR/$clusterName.info
      #arp -na | awk '{print $2"=>"$4}' | tr -d "()" > $CLUSTERDIR/$clusterName.info
      ip=$(cat $CLUSTERDIR/${clusterName}.info | awk -F "=>" -v mac="$mac" '$2==mac{print $1}')
      #ip=$(arp -na | awk -v mac=$(virsh domiflist ${clusterName}_master_$i | awk '$2=="bridge"{print $NF}') '$0 ~ " at " mac {gsub("[()]", "", $2); print $2}')
    done
    echo $ip | tr -d "() " > $CLUSTERDIR/${clusterName}_master_${i}.ip
    echo ubuntu@$ip | tr -d "() " > $CLUSTERDIR/${clusterName}.ip
  done
  for ((i=1;i<=slaveCount;i++));
  do
    mac=$(virsh domiflist ${clusterName}_slave_${i} | awk '$2=="bridge"{print $NF}')
    ip=$(cat $CLUSTERDIR/${clusterName}.info | awk -F "=>" -v mac="$mac" '$2==mac{print $1}')
    while [ "$ip" == "" ];
    do
      sudo nmap -sP $gateway | awk '/Nmap scan report for/{printf $6;}/MAC Address:/{print "=>"tolower($3);}' | tr -d "()" | sort > $CLUSTERDIR/$clusterName.info
      #arp -na | awk '{print $2"=>"$4}' | tr -d "()" > $CLUSTERDIR/$clusterName.info
      ip=$(cat $CLUSTERDIR/${clusterName}.info | awk -F "=>" -v mac="$mac" '$2==mac{print $1}')
    done
    echo $ip | tr -d "() " > $CLUSTERDIR/${clusterName}_slave_${i}.ip
    echo ubuntu@$ip | tr -d "() " >> $CLUSTERDIR/${clusterName}.ip
  done
}
############## Install Kube on KVMS ##################

function installKube(){
clusterName=${1}
for i in $(cat $CLUSTERDIR/${clusterName}.ip)
do
  sshpass -p "toor" scp -o StrictHostKeyChecking=no $SCRIPTDIR/ubuntu.sh $i:~/
  sshpass -p "toor" ssh -tty -o StrictHostKeyChecking=no $i "cd ~;sudo bash ubuntu.sh"
done
}
function configureMaster(){
  clusterName=${1}
  masterCount=${2}
  for ((i=1;i<=masterCount;i++));
  do
  ip=$(cat $CLUSTERDIR/${clusterName}_master_${i}.ip)
 sshpass -p "toor" ssh -tty -o StrictHostKeyChecking=no ubuntu@$ip 'sudo kubeadm init;mkdir -p $HOME/.kube;sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config;sudo chown ubuntu:ubuntu $HOME/.kube/config;kubectl apply -f https://docs.projectcalico.org/v3.8/manifests/calico.yaml'
 token=$(sshpass -p "toor" ssh -tty -o StrictHostKeyChecking=no ubuntu@$ip 'kubeadm token list | tail -n 1' | awk '{print $1}')
 shacode=$(sshpass -p "toor" ssh -tty -o StrictHostKeyChecking=no ubuntu@$ip "openssl x509 -in /etc/kubernetes/pki/ca.crt -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256" | awk -F "= " '{print $2}')


 echo "sudo kubeadm join $ip:6443 --token $token --discovery-token-ca-cert-hash sha256:$shacode" > $CLUSTERDIR/${clusterName}_master_${i}_token.sh
done
}
function configureSlave(){
  clusterName=${1}
  slaveCount=${2}
  for ((i=1;i<=slaveCount;i++));
  do
    ip=$(cat $CLUSTERDIR/${clusterName}_slave_${i}.ip)
    sshpass -p "toor" scp -o StrictHostKeyChecking=no $CLUSTERDIR/${clusterName}_master_1_token.sh ubuntu@$ip:~/
    sshpass -p "toor" ssh -tty -o StrictHostKeyChecking=no ubuntu@$ip "sudo hostnamectl set-hostname slave${i};bash ${clusterName}_master_1_token.sh"
  done
}
############## XML PARSER FUNCTIONS ##################
function getClusterInfo(){
file=${1}
filestring=$(cat $file | tr -d "\n\r ") ###to remove spaces and newlines from the file to form a single string
clusterCount=$(echo $filestring | awk -F "</cluster>" '{print NF-1}' )
for ((i=1;i<=$clusterCount;i++));
do
  clusterDet=$(echo $filestring | awk -F "</cluster>" -v i="$i" '{print $i}')
  clusterName=$(echo $clusterDet | awk -F '<name>|</name>' '{print $2}')
  imgName=$(echo $clusterDet | awk -F '<image>|</image>' '{print $2}')
  masterCount=$(echo $clusterDet | awk -F '<master>|</master>' '{print $2}' | awk -F '<count>|</count>' '{print $2}' )
  slaveCount=$(echo $clusterDet | awk -F '<slave>|</slave>' '{print $2}' | awk -F '<count>|</count>' '{print $2}' )
  clusterInterface=$(echo $clusterDet | awk -F '<interface>|</interface>' '{print $2}')
  echo "Setting cluster $clusterName & master count is $masterCount, slave count is $slaveCount will be setup on interface $clusterInterface"
  cloudConfigCreator $clusterName $masterCount $slaveCount $clusterInterface $imgName
  clusterCreator $clusterName $masterCount $slaveCount $clusterInterface $imgName
  ipInfo $clusterName $masterCount $slaveCount $clusterInterface
  installKube $clusterName
  configureMaster $clusterName $masterCount
  configureSlave $clusterName $slaveCount
done
}

getClusterInfo main.xml
