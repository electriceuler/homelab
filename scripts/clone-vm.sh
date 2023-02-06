#!/bin/sh
# This needs to be copied to esx01
# Do not execute this script standalone
# it is called from the deploy-server.sh script
#
# TODO change the script to take command line arguments instead
#      add a check that the template is powered off or the disk cloning fails
#
#

vmname=$1
portgroup=$2
template_portgroup="INFRA"
template=centos8_template
datastorepath=/vmfs/volumes/datastorename/

cd $datastorepath
if [ ! -d $vmname ] ; then
	mkdir $vmname
else
	echo "VM with name $vmname already exists. Exiting"
	exit 1
fi

# continue creating the vm
cp ${template}/${template}.vmx ${vmname}/${vmname}.vmx
sed -i 's/'"$template"'/'"$vmname"'/g' ${vmname}/${vmname}.vmx
if [ "$portgroup" != "$template_portgroup" ] ; then
	sed -i '/^ethernet0.networkName/s/.*/ethernet0.networkName = "'$portgroup'"/' ${vmname}/${vmname}.vmx
fi
vmkfstools -i ${template}/${template}.vmdk ${vmname}/${vmname}.vmdk -d thin

# Register the vm
vmid=$(vim-cmd solo/registervm ${datastorepath}/${vmname}/${vmname}.vmx)

# Poweron the vm
# The vm will not start automatically since it's copied so we need to answer
# the question after running the poweron in the background
vim-cmd vmsvc/power.on $vmid &
sleep 1
questionid=$(vim-cmd vmsvc/message $vmid | head -1 | sed 's/.*message \([0-9]*\)[^0-9].*/\1/')
#Virtual machine message $questionid:
#This virtual machine might have been moved or copied. In order to configure certain management and networking features, VMware ESX needs to know if this virtual machine was moved or copied. If you don't know, answer "I Copied It".
#   0. button.uuid.cancel (Cancel)
#   1. button.uuid.movedTheVM (I Moved It)
#   2. button.uuid.copiedTheVM (I Copied It) [default]

vim-cmd vmsvc/message $vmid $questionid 2

if [ $(vim-cmd vmsvc/power.getstate $vmid | grep "Powered on" | wc -l) -ne 1 ] ; then
	>&2 vim-cmd vmsvc/power.getstate $vmid
	>&2 echo VM failed to power on
	>&2 echo Destroying the VM with vmid $vmid
	if [ ! -z $vmid ] ; then
		vim-cmd vmsvc/power.off $vmid
		vim-cmd vmsvc/destroy $vmid
	fi
else
	# print the new vm:s mac address and vmid
	macaddress=$(vim-cmd vmsvc/device.getdevices $vmid |grep macAddress | awk '{print $3}' | sed 's/[\",]*//g')
	echo mac: $macaddress
	>&2 echo mac: $macaddress
	echo vmid: $vmid
	>&2 echo vmid: $vmid
fi
