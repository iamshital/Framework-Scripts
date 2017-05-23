﻿#
#  THIS IS A WINDOWS POWERSHELL SCRIPT!!  IT ONLY WORKS ON WINDOWS!!
#
# Variables for common values
$resourceGroup = "azureSmokeResourceGroup"
$rg=$resourceGroup
$nm="azuresmokestoragesccount"
$location = "westus"
$vmName = "azureSmokeVM-1"

echo "********************************************************************"
echo "*              BORG, Phase II -- Assimilation by Azure             *"
echo "********************************************************************"

# Login-AzureRmAccount -Credential $cred
$tempRg="azureTempResourceGroup-5"
$tempRg2="azureTempResourceGroupSecond-5"
$cn="azuresmokecontainer-5"

$diskname="osdev64-cent7"
$diskUri="https://$nm.blob.core.windows.net/$cn/osdev64-cent7.vhd"
$imageName="MSKernelTestImage"

echo "Importing the context...."
Import-AzureRmContext -Path 'D:\Boot-Ready Images\ProfileContext.ctx'

echo "Selecting the Azure subscription..."
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4"

echo "Removing old resource groups."
echo "First, $tempRg"
Remove-AzureRmResourceGroup -Name $tempRg -Force
echo "Then, $tempRg2"
Remove-AzureRmResourceGroup -Name $tempRg2 -Force
echo "Whew!  That was painful.  Note to self -- make sure we have to do all of those"

echo "Setting the Azure Storage Account"
# New-AzureRmStorageAccount -ResourceGroupName $rg -Name $nm -Location westus -SkuName "Standard_LRS" -Kind "Storage"
Set-AzureRmCurrentStorageAccount –ResourceGroupName $rg –StorageAccountName $nm

echo "Removing and re-creating the container"
remove-AzureStorageContainer -name $cn -force
New-AzureStorageContainer -Name $cn -Permission Off 

# $azureCentOSSourceImage="https://azuresmokestoragesccount.blob.core.windows.net/azuresmokecontainer/osdev64-cent7.vhd"
$azureCentOSTargetImage="/osdev64-cent7.vhd"
$azureCentOSDiskImage='D:\Exported Images\CentOS 7.1 MSLK Test 1\Virtual Hard Disks\osdev64-cent7.vhd'
$hvCentOSVMName="CentOS 7.1 MSLK Test 1"

#
#  Create the checkpoint and snapshot
#
echo "Clearing the old VHD checkpoint directory"
remove-item "D:\Exported Images\$hvCentOSVMName" -recurse -force

echo "Stopping the running VMs"
Stop-VM -Name $hvCentOSVMName

echo "Creating checkpoints..."
echo "First CentOS..."
Checkpoint-vm -Name $hvCentOSVMName -Snapshotname "Ready for Azure"
echo "CentOS Checkpoint created.  Exporting VM"
Export-VMSnapshot -name "Ready for Azure" -VMName $hvCentOSVMName -path 'D:\Exported Images\'

#
#  Copy the blob to the storage container
$c = Get-AzureStorageContainer -Name $cn
$sas = $c | New-AzureStorageContainerSASToken -Permission rwdl
$blob = $c.CloudBlobContainer.Uri.ToString() + $azureCentOSTargetImage 
$uploadURI = $blob + $sas

echo "Uploading the CentOS VHD blob to the cloud"
Add-AzureRmVhd -Destination $uploadURI -LocalFilePath $azureCentOSDiskImage

#
#  Go from generalized to specialized state
#
echo "Setting the image on disk"
$imageConfig = New-AzureRmImageConfig -Location westus
Set-AzureRmImageOsDisk -Image $imageConfig -OsType "Linux" -OsState "Generalized" –BlobUri $blob

echo "Creating resource group $tempRg"
New-AzureRmResourceGroup -Name $tempRg -Location westus

echo "Creating the image"
New-AzureRmImage -ResourceGroupName $tempRg -ImageName $imageName -Image $imageConfig

#
#  Create the image from the VM
#
echo "########################################################################################"
echo "#                                                                                      #"
echo "#                                                                                      #"
echo "#                  GO DO THE WEB THING HERE UNTIL THIS IS FIXED!!                      #"
echo "#                                                                                      #"
echo "#                                                                                      #"
echo "########################################################################################"
az login

echo "Thank you.  Creating Azure VM as..."
az vm create -g $tempRg -n vm3 --image $imageName --generate-ssh-keys

#
#  Try starting it up
#
$image = Get-AzureRMImage -ImageName $imageName -ResourceGroupName $tempRg

$rgName = $tempRg2
echo "Creating another resrouce group for the test.  This is $tempRg2"
New-AzureRmResourceGroup -Name $rgName -Location $location

echo "Configuring the system..."
echo "User and password..."
# Definer user name and blank password
$securePassword = ConvertTo-SecureString 'P@$$w0rd!' -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ("azureuser", $securePassword)

# Create a subnet configuration
echo "Subnet..."
$subnetConfig = New-AzureRmVirtualNetworkSubnetConfig -Name smokeSubnet -AddressPrefix 10.0.0.0/24

# Create a virtual network
echo "Creating a virtual network"
$vnet = New-AzureRmVirtualNetwork -ResourceGroupName $tempRg2 -Location $location `
  -Name SMOKEvNET -AddressPrefix 10.0.0.0/16 -Subnet $subnetConfig

# Create a public IP address and specify a DNS name
echo "Assigning a public IP address and giving DNS"
$pip = New-AzureRmPublicIpAddress -ResourceGroupName $tempRg2 -Location $location `
  -Name "smokepip" -AllocationMethod Dynamic -IdleTimeoutInMinutes 4

# Create an inbound network security group rule for port 22
echo "Enabling port 22 for SSH"
$nsgRuleSSH = New-AzureRmNetworkSecurityRuleConfig -Name smokeNetworkSecurityGroupRuleSSH  -Protocol Tcp `
  -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
  -DestinationPortRange 22 -Access Allow

# Create an inbound network security group rule for port 443
echo "Enabling port 443 for OMI"
$nsgRuleOMI = New-AzureRmNetworkSecurityRuleConfig -Name smokeNetworkSecurityGroupRuleOMI  -Protocol Tcp `
  -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * `
  -DestinationPortRange 443 -Access Allow

# Create a network security group
echo "Creating a network security group"
$nsg = New-AzureRmNetworkSecurityGroup -ResourceGroupName $tempRg2 -Location $location `
  -Name smokeNetworkSecurityGroup -SecurityRules $nsgRuleSSH,$nsgRuleOMI

# Create a virtual network card and associate with public IP address and NSG
echo "Creating a NIC"
$nic = New-AzureRmNetworkInterface -Name smokeNic -ResourceGroupName $tempRg2 -Location $location `
  -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id

$vmName="CentOSSmoke1"
$computerName="Cent71-mslk-test-1"

$vmSize = "Standard_DS1_v2"

echo "Creating the full VM configuration..."
$vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize

echo "Setting the VM source image..."
$vm = Set-AzureRmVMSourceImage -VM $vm -Id $image.Id

echo "Setting the VM OS Source Disk...."
$vm = Set-AzureRmVMOSDisk -VM $vm  -StorageAccountType PremiumLRS -DiskSizeInGB 128 -CreateOption FromImage -Caching ReadWrite

echo "Setting the OS to Linux..."
$vm = Set-AzureRmVMOperatingSystem -VM $vm -Linux -Credential $cred -ComputerName $computerName

echo "Adding the network interface..."
$vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id

echo "And launching the VM..."
New-AzureRmVM -VM $vm -ResourceGroupName $rgName -Location $location
