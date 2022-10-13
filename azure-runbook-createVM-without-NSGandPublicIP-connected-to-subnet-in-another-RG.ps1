param (
		[Parameter(Mandatory)]
        [string] $Tag1, # Required parameter for Tag №1. It will be a value of tag, NOT a key of tag. This tag is attached to VM, NIC, ODDisk

        [Parameter(Mandatory)]
        [string] $Tag2, # Required parameter for Tag №2. It will be a value of tag, NOT a key of tag. This tag is attached to VM, NIC, ODDisk

		[Parameter(Mandatory = $false)]
        [string] $Location = "Location", # Location where VM have been created

		[Parameter(Mandatory = $false)]
        [string] $ResourceGroupName = "YourRG", # RG where you want to create VM

		[Parameter(Mandatory = $false)]
        [string] $ResourceGroupName2 = "Another_RG_if_needed", # another RG where the Vnet is contained

		[Parameter(Mandatory = $false)]
        [string] $Vnet = "YourVnet", # Vnet located in $ResourceGroupName2

		[Parameter(Mandatory = $false)]
        [string] $SubnetName = "YourSubnetInVnet", # Subnet of the $Vnet

		[Parameter(Mandatory = $false)]
        [string] $date = (Get-Date -Format "hhmmss"), # Date for unique value of names (VM name, NIC name, OSDisk name, Computer name)

		[Parameter(Mandatory = $false)]
        [string] $VMName = "Unique-VM-Name-$date", #VM name in Azure

		[Parameter(Mandatory = $false)]
        [string] $ComputerName = "Unique-Computer-Name-$date", # Computer name when you connect to VM. No more than 15 characters

		[Parameter(Mandatory = $false)]
        [string] $ImageName = "Image-Name", # The image from which the VM is being created. The image must be in $ResourceGroupName

		[Parameter(Mandatory = $false)]
        [string] $user = "ElonMusk", # Username for connect to the VM

		[Parameter(Mandatory = $false)]
        [string] $OSDiskName = "Unique-Disk-Name-$date", # Disk for VM

		[Parameter(Mandatory = $false)]
		[string] $NICname = "Unique-NIC-Name-$date" # Network interface of the VM
)

# The following 5 lines are needed in order for the runbook to start 
$connectionName = "AzureRunAsConnection" 
$servicePrincipalConnection = Get-AutomationConnection -Name $connectionName 
Add-AzAccount -ServicePrincipal -TenantId $servicePrincipalConnection.TenantId `
	-ApplicationId $servicePrincipalConnection.ApplicationId `
	-CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint | Out-Null 

function CreateVM {
# parameters for tags
    param (
        
        [Parameter(Mandatory)]
        [string] $Tag1, # Value of tag

        [Parameter(Mandatory)]
        [string] $Tag2 # Value of tag
        
    )

# Value for Tags
$DateOfCreationVM = Get-Date -Format d # Value of tag3 for
$tags = @{"KeyOfTag1" = "$RequestorEmail"; "KeyOfTag2" = "$TraineeEmail"; "KeyOfTag3" = "$DateOfCreationVM" }

# VM properties
$VMSize = "Standard_b4ms"
$OSDiskCaching = "ReadWrite"
$OSCreateOption = "FromImage"
$DeleteOption = "Delete" # It means when you delete only VM in Azure, it will delete NetworkInterface and OSDick that attached to VM
$StorageType = "StandardSSD_LRS"
$TagOperation = "Merge"

# Password generator
function Get-RandomPassword {
    param (
        [Parameter(Mandatory)]
        [int] $length
    )
    $charSet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.ToCharArray()
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytes = New-Object byte[]($length)
    $rng.GetBytes($bytes)
    $result = New-Object char[]($length)
    for ($i = 0 ; $i -lt $length ; $i++) {
        $result[$i] = $charSet[$bytes[$i] % $charSet.Length]
    }
    return (-join $result)
}

# Password
$pass = Get-RandomPassword 16 # random password that consist of 16 characters
$password = ConvertTo-SecureString $pass -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $user, $password

# VirtualNetwork and Subnet from $ResourceGroupName2
$Vnet = $(Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName2 -Name $Vnet)
$SubNet = ($Vnet.Subnets | Where-Object {$_.Name -eq $SubnetName})[0]

# Creating NIC
$NIC = New-AzNetworkInterface -Name $NICname -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $SubNet.Id -PublicIpAddressId $null -Force

# Waiting until NIC has been created, because you can get errors if it is created later by the VM 
Start-sleep -seconds 15

#VM Config
$VirtualMachine = New-AzVMConfig -VMName $VMName -VMSize $VMSize
$VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $ComputerName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate
$VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id -DeleteOption $DeleteOption
$VirtualMachine = Set-AzVMOSDisk -VM $VirtualMachine -Name $OSDiskName -StorageAccountType $StorageType -CreateOption $OSCreateOption -Windows -Caching $OSDiskCaching -DeleteOption $DeleteOption

# Set Image for VM
$image = Get-AzImage -ResourceGroupName $ResourceGroupName -ImageName $ImageName
$VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -Id $image.Id

# Creating a VM with the config above 
New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VirtualMachine -Verbose | Out-Null
 
# Waiting until VM has been created, because tags may not attach to the created resources
Start-sleep -seconds 20

# Add Tags to VM, NIC, OSDisk
$VmId = (get-AzVm -ResourceGroupName $ResourceGroupName -Name $VMName).Id
Update-AzTag -ResourceId $VmId -Operation $TagOperation -Tag $tags | Out-Null
$nicID = (Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -name $NICname).id
Update-AzTag -ResourceId $nicID -Operation $TagOperation -Tag $tags | Out-Null
Start-sleep -seconds 10
$DiskID = (Get-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $OSDiskName).id
Update-AzTag -ResourceId $DiskID -Operation $TagOperation -Tag $tags | Out-Null

# Information for the user to connect to the VM
$objOut = @{
    user = $user
    password = $pass
	VMname = $VMName
	IP = ($nic.IpConfigurations | Select-Object PrivateIpAddress)    
}

Write-Output ( $objOut | ConvertTo-Json)

}

# Use function with 2 parameters name and email
CreateVM $Tag1 $Tag2
