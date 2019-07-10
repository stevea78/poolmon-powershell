param (
	[string]$sortby = 'TotalUsed',
	[string]$sortdir = 'Descending',
	[int]$top = 0,
	[string]$csv = 'false',
	[string]$gridview = 'false'
)

if ($env:Processor_Architecture -ne "x86")
{
&"$env:windir\syswow64\windowspowershell\v1.0\powershell.exe" -executionpolicy bypass -noninteractive -noprofile -file $myinvocation.Mycommand.Path -sortby $sortby -sortdir $sortdir -top $top -csv $csv -gridview $gridview
exit
}

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

$pooTagInfo = $null
$length = 4096
do
{
    $ptr = [IntPtr]::Zero
    try
    {
        try {}
        finally
		{
            $ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($length)
        }
        $returnLength
        $pooTagInfo = [Win32.PInvoke]::NtQuerySystemInformation([Win32.SYSTEM_INFORMATION_CLASS]::SystemPoolTagInformation, $ptr, $length, [System.Management.Automation.PSReference]$returnLength)
        if ($pooTagInfo -eq [Win32.NT_STATUS]::STATUS_INFO_LENGTH_MISMATCH)
        {
            $length += 4096
        }
        elseif ($pooTagInfo -eq [Win32.NT_STATUS]::STATUS_SUCCESS)
        {
			$poolCount = [System.Runtime.InteropServices.Marshal]::ReadInt32($ptr)
            $offset = 4
            $size = [System.Runtime.InteropServices.Marshal]::SizeOf([System.Type]([Win32.SYSTEM_POOLTAG]))
			$poolHash = $null
			$poolHash = @{}
            for ($i = 0; $i -lt $poolCount; $i++)
            {
				$poolEntry = [Win32.SYSTEM_POOLTAG][System.Runtime.InteropServices.Marshal]::PtrToStructure([System.IntPtr]($ptr + $offset), [System.Type][Win32.SYSTEM_POOLTAG])
				$poolTag = [System.Text.Encoding]::Default.GetString($poolEntry.Tag)
				$poolPagedAllocs = [int]$poolEntry.PagedAllocs
				$poolPagedFrees = [int]$poolEntry.PagedFrees
				$poolPagedDiff = [int]($poolPagedAllocs - $poolPagedFrees)
				$poolPagedUsed = [int]$poolEntry.PagedUsed
				$poolPagedUsedHR = HRSize([int]$poolEntry.PagedUsed)
				$poolNonPagedAllocs = [int]$poolEntry.NonPagedAllocs
				$poolNonPagedFrees = [int]$poolEntry.NonPagedFrees
				$poolNonPagedDiff = [int]($poolNonPagedAllocs - $poolNonPagedFrees)
				$poolNonPagedUsed = [int]$poolEntry.NonPagedUsed
				$poolNonPagedUsedHR = HRSize([int]($poolEntry.NonPagedUsed))
				$poolTotalUsed = [int]($poolPagedUsed + $poolNonPagedUsed)
				$poolTotalUsedHR = HRSize([int]$poolTotalUsed)
				$poolEntryHash = $null
				$poolEntryHash = @{
					"Tag" = $poolTag
					"PagedAllocs" = $poolPagedAllocs
					"PagedFrees" = $poolPagedFrees
					"PagedDiff" = $poolPagedDiff
					"PagedUsed" = $poolPagedUsed
					"PagedUsedHR" = $poolPagedUsedHR
					"NonPagedAllocs" = $poolNonPagedAllocs
					"NonPagedFrees" = $poolNonPagedFrees
					"NonPagedDiff" = $poolNonPagedDiff
					"NonPagedUsed" = $poolNonPagedUsed
					"NonPagedUsedHR" = $poolNonPagedUsedHR
					"TotalUsed" = $poolTotalUsed
					"TotalUsedHR" = $poolTotalUsedHR
				}
				$poolHash.$poolTag = $poolEntryHash
				$offset += $size
            }
			$expression = '$(foreach ($poolEntry in $poolHash.Values) {new-object PSObject -Property $poolEntry})'
			$expression += '|Select-Object "Tag","PagedAllocs","PagedFrees","PagedDiff","PagedUsed","PagedUsedHR","NonPagedAllocs","NonPagedFrees","NonPagedDiff","NonPagedUsed","NonPagedUsedHR","TotalUsed","TotalUsedHR"'
			if ($sortdir -eq 'Ascending')
			{
				$expression += '|Sort-Object -Property $sortby'
			}
			elseif ($sortdir -eq 'Descending')
			{
				$expression += '|Sort-Object -Property $sortby -Descending'
			}
			if ($top -gt 0)
			{
				$expression += '|Select-Object -First $top'
			}
			if ($csv -eq 'true')
			{
				$expression += '|ConvertTo-Csv -NoTypeInformation'
			}
			elseif ($gridview -eq 'true')
			{
				$expression += '|Out-GridView -Title "Kernel Memory Pool (captured $(Get-Date -Format "dd/MM/yyyy HH:mm:ss"))" -Wait'
			}
			else
			{
				$expression += '|Format-Table *'
			}
			Invoke-Expression $expression
        }		
    }
    finally
    {
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    }
}
while ($pooTagInfo -eq [Win32.NT_STATUS]::STATUS_INFO_LENGTH_MISMATCH)
