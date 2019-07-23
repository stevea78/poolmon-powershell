# poolmon-powershell
Powershell script to view kernel memory pool tag information similar to poolmon

SYNTAX
    poolmon-powershell.ps1 [[-tags] <String[]>] [[-values] <String[]>] [[-sortvalue] <String>] [[-sortdir] <String>] [[-top] <Int32>] [[-view] <String>] [[-tagfile] <String>] [[-loop] <Int32>]
	
PARAMETERS
    -tags <String[]>
        comma separated list of tags to display

    -values <String[]>
        comma separated list of values to display

    -sortvalue <String>
        value to sort by

    -sortdir <String>
        direction to sort (ascending|descending)

    -top <Int32>
        top X records to display

    -view <String>
        output view (table|csv|grid)

    -tagfile <String>
        file containing tag information

    -loop <Int32>
        loop interval in seconds
