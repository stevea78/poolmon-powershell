<# .SYNOPSIS #>
param (
	# comma seperated list of tags to display e.g. -tags mmst,fmfn
	[string[]]$tags,
	# comma seperated list of values to display e.g. -tags tag,pagedusedbytes
	[string[]]$values,
	# value to sort by e.g. -sortvalue pagedusedbytes
	[string]$sortvalue = 'TotalUsed',
	# direction to sort by e.g. -sortdir ascending|descending
	[string]$sortdir = 'Descending',
	# top X records to display e.g. -top 10
	[int]$top = 0,
	# output view e.g. -view table|csv|grid
	[string]$view = 'table',
	# file containing tag information e.g. -tagfile pooltag.txt
	[string]$tagfile = 'pooltag.txt',
	# loop interval in seconds e.g. -loop 10
	[int]$loop = 0
)
 
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Win32 {
	public enum NT_STATUS
	{
		STATUS_SUCCESS = 0x00000000,
		STATUS_BUFFER_OVERFLOW = unchecked((int)0x80000005),
		STATUS_INFO_LENGTH_MISMATCH = unchecked((int)0xC0000004)
	}
	public enum SYSTEM_INFORMATION_CLASS
	{
		SystemPoolTagInformation = 22,
	}
	[StructLayout(LayoutKind.Sequential)]
	public struct SYSTEM_POOLTAG
	{
		[MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)] public byte[] Tag;
		public uint PagedAllocs;
		public uint PagedFrees;
		public System.IntPtr PagedUsed;
		public uint NonPagedAllocs;
		public uint NonPagedFrees;
		public System.IntPtr NonPagedUsed;
	}
	public class PInvoke {
		[DllImport("ntdll.dll")]
		public static extern NT_STATUS NtQuerySystemInformation(
		[In] SYSTEM_INFORMATION_CLASS SystemInformationClass,
		[In] System.IntPtr SystemInformation,
		[In] int SystemInformationLength,
		[Out] out int ReturnLength);
	}
}
'@

Function Get-Pool() {
	if ($tagfile) {
		if (Test-Path $tagfile) {
			$tagFileHash = $null
			$tagFileHash = new-object System.Collections.Hashtable
			foreach($line in Get-Content $tagfile) {
				if(($line.trim() -ne '') -and ($line.trim() -like '*-*-*') -and ($line.trim().SubString(0,2) -ne '//') -and ($line.trim().SubString(0,3) -ne 'rem')){
					$t,$b,$d = $line.split('-')
					$t = $t.trim()
					$b = $b.trim()
					$d = $d.trim()
					if (!($tagFileHash.containsKey($t))) {
						$tagFileHash.Add($t,"$b|$d")
					}
				}
			}
		}
	}
	$ptrSize = 0
	while ($true) {
		[IntPtr]$ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($ptrSize)
		$ptrLength = New-Object Int
		$tagInfo = [Win32.PInvoke]::NtQuerySystemInformation([Win32.SYSTEM_INFORMATION_CLASS]::SystemPoolTagInformation, $ptr, $ptrSize, [ref]$ptrLength)
		if ($tagInfo -eq [Win32.NT_STATUS]::STATUS_INFO_LENGTH_MISMATCH) {
			[System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
			$ptrSize = [System.Math]::Max($ptrSize,$ptrLength)
		}
		elseif ($tagInfo -eq [Win32.NT_STATUS]::STATUS_SUCCESS) {
			break
		}
		else {
			[System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
			"An error occurred getting SystemPoolTagInformation"
			return
		}
	}
	$datetime = Get-Date
	$systemPoolTag = New-Object Win32.SYSTEM_POOLTAG
	$systemPoolTag = $systemPoolTag.GetType()
	$size = [System.Runtime.InteropServices.Marshal]::SizeOf([type]([Win32.SYSTEM_POOLTAG]))
	$offset = $ptr.ToInt64()
	$count = [System.Runtime.InteropServices.Marshal]::ReadInt32($offset)
	$offset = $offset + [System.IntPtr]::Size
	for ($i=0; $i -lt $count; $i++){
		$entryPtr = New-Object System.Intptr -ArgumentList $offset
		$entry = [system.runtime.interopservices.marshal]::PtrToStructure($entryPtr,[type]$systemPoolTag)
		$Tag = [System.Text.Encoding]::Default.GetString($entry.Tag)
		if (!$tags -or ($tags -and $tags -contains $Tag)) {
			$tagResult = $null
			$tagResult = [PSCustomObject]@{
				DateTime = Get-Date -Format s $datetime
				DateTimeUTC = Get-Date -Format s $datetime.ToUniversalTime()
				Tag = $Tag
				PagedAllocs = [int64]$entry.PagedAllocs
				PagedFrees = [int64]$entry.PagedFrees
				PagedDiff = [int64]$entry.PagedAllocs - [int64]$entry.PagedFrees
				PagedUsedBytes = [int64]$entry.PagedUsed
				NonPagedAllocs = [int64]$entry.NonPagedAllocs
				NonPagedFrees = [int64]$entry.NonPagedFrees
				NonPagedDiff = [int64]$entry.NonPagedAllocs - [int64]$entry.NonPagedFrees
				NonPagedUsedBytes = [int64]$entry.NonPagedUsed
				TotalUsedBytes = [int64]$entry.PagedUsed + [int64]$entry.NonPagedUsed
			}
			if ($tagFileHash) {
				if ($tagFileHash.containsKey($Tag)) {
					$Bin,$BinDesc = $tagFileHash.$tag.split('|')
					$tagResult | Add-Member NoteProperty 'Binary' $Bin
					$tagResult | Add-Member NoteProperty 'Description' $BinDesc
				} else {
					$tagResult | Add-Member NoteProperty 'Binary' ''
					$tagResult | Add-Member NoteProperty 'Description' ''
				}
			}
			$tagResult
		}
		$offset = $offset + $size
	}
	[System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
}

$expression = 'Get-Pool'
if ($sortvalue) {
	$expression += '|Sort-Object -Property $sortvalue'
	if ($sortdir -eq 'Descending') {
		$expression += ' -Descending'
	}
}
if ($top -gt 0) {
	$expression += '|Select-Object -First $top'
}
if ($values) {
	$expression += '|Select-Object $values'
}
if ($view -eq 'csv') {
	$expression += '|ConvertTo-Csv -NoTypeInformation'
} elseif ($view -eq 'grid') {
	$expression += '|Out-GridView -Title "Kernel Memory Pool (captured $(Get-Date -Format "dd/MM/yyyy HH:mm:ss"))" -Wait'
} else {
	$expression += '|Format-Table *'
}
if ($loop -gt 0) {
	while ($true) {
		Invoke-Expression $expression
		Start-Sleep -Seconds $loop
	}
} else {
	Invoke-Expression $expression
}