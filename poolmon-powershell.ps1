param (
	[string]$sortby = 'TotalUsed',
	[string]$sortdir = 'Descending',
	[int]$top = 0,
	[string]$view = 'table'
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

function HRSize()
{
	Param(
		[int64]$sizeInBytes,
		[int]$decimalPlaces = 2
	)
	switch ($sizeInBytes)
	{
		{$sizeInBytes -ge 1TB} {"{0:n$decimalPlaces}" -f ($sizeInBytes/1TB) + " TB" ; break}
		{$sizeInBytes -ge 1GB} {"{0:n$decimalPlaces}" -f ($sizeInBytes/1GB) + " GB" ; break}
		{$sizeInBytes -ge 1MB} {"{0:n$decimalPlaces}" -f ($sizeInBytes/1MB) + " MB" ; break}
		{$sizeInBytes -ge 1KB} {"{0:n$decimalPlaces}" -f ($sizeInBytes/1KB) + " KB" ; break}
		Default { "{0:n$decimalPlaces}" -f $sizeInBytes + " Bytes" }
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
$poolTag = New-Object Win32.SYSTEM_POOLTAG
$poolTag = $poolTag.GetType()
$size = [System.Runtime.InteropServices.Marshal]::SizeOf([type]([Win32.SYSTEM_POOLTAG]))
$offset = $ptr.ToInt64()
$count = [System.Runtime.InteropServices.Marshal]::ReadInt32($offset)
$offset = $offset + [System.IntPtr]::Size
$poolHash = $null
$poolHash = @{}
for ($i=0; $i -lt $count; $i++){
	$entryPtr = New-Object System.Intptr -ArgumentList $offset
	$entry = [system.runtime.interopservices.marshal]::PtrToStructure($entryPtr,[type]$poolTag)
	$tag = [System.Text.Encoding]::Default.GetString($entry.Tag)
	$pagedAllocs = [int]$entry.PagedAllocs
	$pagedFrees = [int]$entry.PagedFrees
	$pagedDiff = [int]($pagedAllocs - $pagedFrees)
	$pagedUsed = [int]$entry.PagedUsed
	$pagedUsedHR = HRSize([int]$entry.PagedUsed)
	$nonPagedAllocs = [int]$entry.NonPagedAllocs
	$nonPagedFrees = [int]$entry.NonPagedFrees
	$nonPagedDiff = [int]($nonPagedAllocs - $nonPagedFrees)
	$nonPagedUsed = [int]$entry.NonPagedUsed
	$nonPagedUsedHR = HRSize([int]($entry.NonPagedUsed))
	$pooltotalUsed = [int]($pagedUsed + $nonPagedUsed)
	$pooltotalUsedHR = HRSize([int]$pooltotalUsed)
	$entryHash = $null
	$entryHash = @{
		"Tag" = $tag
		"PagedAllocs" = $pagedAllocs
		"PagedFrees" = $pagedFrees
		"PagedDiff" = $pagedDiff
		"PagedUsed" = $pagedUsed
		"PagedUsedHR" = $pagedUsedHR
		"NonPagedAllocs" = $nonPagedAllocs
		"NonPagedFrees" = $nonPagedFrees
		"NonPagedDiff" = $nonPagedDiff
		"NonPagedUsed" = $nonPagedUsed
		"NonPagedUsedHR" = $nonPagedUsedHR
		"TotalUsed" = $pooltotalUsed
		"TotalUsedHR" = $pooltotalUsedHR
	}
	$poolHash.$tag = $entryHash
	$offset = $offset + $size
}
[System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
$expression = '$(ForEach ($value in $poolHash.Values) {New-Object PSObject -Property $value})'
$expression += '|Select-Object "Tag","PagedAllocs","PagedFrees","PagedDiff","PagedUsed","PagedUsedHR","NonPagedAllocs","NonPagedFrees","NonPagedDiff","NonPagedUsed","NonPagedUsedHR","TotalUsed","TotalUsedHR"'
$expression += '|Sort-Object -Property $sortby'
if ($sortdir -eq 'Descending')
{
	$expression += ' -Descending'
}
if ($top -gt 0)
{
	$expression += '|Select-Object -First $top'
}
if ($view -eq 'csv') {
	$expression += '|ConvertTo-Csv -NoTypeInformation'
} elseif ($view -eq 'grid') {
	$expression += '|Out-GridView -Title "Kernel Memory Pool (captured $(Get-Date -Format "dd/MM/yyyy HH:mm:ss"))" -Wait'
} else {
	$expression += '|Format-Table *'
}
Invoke-Expression $expression
