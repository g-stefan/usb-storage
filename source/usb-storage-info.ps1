# 
#  USB Storage Info
# 
#  Copyright (c) 2020-2021 Grigore Stefan <g_stefan@yahoo.com>
#  Created by Grigore Stefan <g_stefan@yahoo.com>
# 
#  MIT License (MIT) <http://opensource.org/licenses/MIT>
# 
#  Version 1.0.0 2020-07-09
#
# run from cmd :
# 	powershell -ExecutionPolicy Bypass -command ./usb-storage-info.ps1
#

#
# Setup API
#

$cp = New-Object CodeDom.Compiler.CompilerParameters 
$cp.CompilerOptions = "/unsafe"
$null = $cp.ReferencedAssemblies.Add([object].Assembly.Location)
$null = $cp.ReferencedAssemblies.Add([psobject].Assembly.Location)

$null = Add-Type -PassThru -CompilerParameters $cp -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

namespace SetupAPI {
	public class DeviceManager {

		[DllImport("setupapi.dll", ExactSpelling = true, SetLastError=true, CharSet = CharSet.Unicode)]
		unsafe internal static extern int CM_Locate_DevNodeW(ref int dnDevInst, string pDeviceID, int ulFlags);

		[DllImport("setupapi.dll", SetLastError=true)]
		unsafe internal static extern int CM_Get_Parent(ref int dnDevInstParent, int dnDevInst, int ulFlags);

		[DllImport("setupapi.dll", SetLastError=true)]
		unsafe internal static extern int CM_Get_Device_ID_Size(ref int ulLen, int dnDevInst, int ulFlags);

		[DllImport("setupapi.dll", ExactSpelling = true, SetLastError=true, CharSet = CharSet.Unicode)]
		unsafe internal static extern int CM_Get_Device_IDW(int dnDevInst,IntPtr Buffer, int BufferLen, int ulFlags);

		public static string getParent(string device) {
			int dnDevInst;
			int dnDevInstParent;
			int bufferLen;

			dnDevInst = 0;
			dnDevInstParent = 0;
			bufferLen = 0;

			if(CM_Locate_DevNodeW(ref dnDevInst, device, 0)!=0) {
				return null;
			};
			if(CM_Get_Parent(ref dnDevInstParent, dnDevInst, 0)!=0) {
				return null;
			};
			if(CM_Get_Device_ID_Size(ref bufferLen, dnDevInstParent, 0)!=0) {
				return null;
			};
			IntPtr ptrBuffer = Marshal.AllocHGlobal(bufferLen*2+4);
			if(CM_Get_Device_IDW(dnDevInstParent, ptrBuffer, bufferLen, 0)!=0) {
				Marshal.FreeHGlobal(ptrBuffer);
				return null;
			};
			Marshal.WriteIntPtr(ptrBuffer,bufferLen*2,IntPtr.Zero);
			string parent = Marshal.PtrToStringAuto(ptrBuffer);
			Marshal.FreeHGlobal(ptrBuffer);
			return parent;
		}

	}
}
"@

#
# Get Device List
#

$usbstorDeviceList = get-wmiobject -class "Win32_USBControllerDevice" | %{[wmi]($_.Dependent)} | where-object {$_.Service -eq "USBSTOR"}
$diskList = get-wmiobject -class "Win32_USBControllerDevice" | %{[wmi]($_.Dependent)} | where-object {$_.PNPClass -eq "DiskDrive"}

$usbStorageInfo=@{}

foreach ($usbstorDevice in $usbstorDeviceList) {
	$deviceID = $usbstorDevice.PNPDeviceID
	$deviceLocation = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Enum\$deviceID" -Name LocationInformation -ErrorAction SilentlyContinue
	if($deviceLocation) {
		$serialNumber = ($deviceID -split "\\")[-1]
		foreach ($disk in $diskList) {
			if($disk.PNPDeviceID.Contains($serialNumber)) {
				$deviceLocationInfo = ($deviceLocation.LocationInformation -split "\.")
				$portNumber = ($deviceLocationInfo[0] -split "#")[1] -as [int]
				$hubNumber = ($deviceLocationInfo[1] -split "#")[1] -as [int]
				$parentID = [SetupAPI.DeviceManager]::getParent($disk.PNPDeviceID)
				if($parentID) {
					$parentHUBID = [SetupAPI.DeviceManager]::getParent($parentID)
					if($parentHUBID) {
						$info = new-object -typename psobject -property @{
							"Name" = $disk.Name;
							"SerialNumber" = $serialNumber;
							"PNPDeviceID" = $disk.PNPDeviceID;
							"HubNumber" = $hubNumber;
							"HubPort" = $portNumber;
							"HubID" = $parentHUBID;
							"Hub" = "Unknown";
							"DeviceID" = "Unknwon";
							"DriveLetter" = "Unknwon";
						}
						$usbStorageInfo.Add($disk.PNPDeviceID, $info)
					}
				}
			}
		}
	}
}

#
# Set Drive Info
#

$diskList = get-wmiobject -class "Win32_DiskDrive" | Select-Object �Property * | where-object {$_.InterfaceType -eq "USB"}
foreach ($disk in $diskList) {
	foreach ($key in $usbStorageInfo.Keys) {
		if($usbStorageInfo[$key].PNPDeviceID -eq $disk.PNPDeviceID) {
			$usbStorageInfo[$key].DeviceID = $disk.DeviceID
		}
	}
}

#
# Set Drive Letter
#

$logicalDiskList = get-wmiobject -class "Win32_LogicalDisk"
foreach ($logicalDisk in $logicalDiskList) {
	$deviceID = $logicalDisk.GetRelated("Win32_DiskPartition").GetRelated("Win32_DiskDrive").DeviceID
	foreach ($key in $usbStorageInfo.Keys) {
		if($usbStorageInfo[$key].DeviceID -eq $deviceID) {
			$usbStorageInfo[$key].DriveLetter = $logicalDisk.DeviceID
		}
	}
}

#
# Set our hub physical label
#

$hubLabels = @{
	"USB\VID_05E3&PID_0612\5&17411534&0&20" = "Hub Marked with label [Hub 1]";  # Example
}

#
# Set info hub label
#

foreach ($key in $usbStorageInfo.Keys) {
	foreach ($keyLabel in $hubLabels.Keys) {
		if($usbStorageInfo[$key].HubID -eq $keyLabel) {
			$usbStorageInfo[$key].Hub = $hubLabels[$keyLabel]
		}
	}
}

#
# Show items
#

foreach ($key in $usbStorageInfo.Keys) {
	$usbStorageInfo[$key]
}

