Param(
	[string]$Server = 'http://navidrome:4533',
	[string]$User,
	[string]$Pass,
	[string]$Source,
	[string]$Output
)

if(!$Server -or !$User -or !$Pass -or !$Source){
	"  >> -Server <http://navidrome:4533> -User <username> -Pass <password> -Source <csv> [-Output <csv>]"
	exit 1
}

$src = Import-Csv $Source |?{$_.artist -and $_.album -and $_.title}
if(!$src){
	"  >> error reading csv at '$Source'."
	exit 1
}

Add-Type -AssemblyName System.Web
$opts = "u=$User&p=$Pass&v=1.12&c=CsvToPlaylist"
$out = @()

$playlistId = $false
$r = Invoke-RestMethod "$Server/rest/ping?$opts"
if(($r.ChildNodes.xmlns -eq 'http://subsonic.org/restapi') -and ($r.ChildNodes.status -eq 'ok')){
	foreach($x in $src){
		$songFound = $false
		foreach($q in ($x.artist+' '+$x.album+' '+$x.title),($x.artist+' '+$x.title),($x.album+' '+$x.title),($x.artist+' '+$x.title.split(' ')[0]),($x.artist+' '+$x.title.split(' ')[-1])){
			if(!$songFound){
				$q = [System.Web.HttpUtility]::UrlEncode($q)
				$found = (Invoke-RestMethod "$Server/rest/search3?$opts&query=$q").ChildNodes.searchResult3.song
				if($found){
					if($found.Count -gt 1){ $found = $found |?{(($_.title -match [regex]::Escape($x.title)) -or ($x.title -match [regex]::Escape($_.title)))} }
					if($found.Count -gt 1){ $found = $found |?{$_.title -like $x.title} }
					if($found.id -and (!$found.Count -or ($found.Count -eq 1))){
						$songFound = $true
						$out += [PSCustomObject]@{id=$found.id;artist=$found.artist;album=$found.album;title=$found.title;artistIn=$x.artist;albumIn=$x.album;titleIn=$x.title}
						Invoke-RestMethod ("$Server/rest/star?$opts&id="+$found.id) |Out-Null
					}
				}
			}
		}
		if(!$songFound){
			$out += [PSCustomObject]@{artistIn=$x.artist;albumIn=$x.album;titleIn=$x.title}
		}
	}
	if($Output){ $out |Export-Csv $Output -NoTypeInformation }
}else{
	"  >> bad response from server '{0}'." -f $r.ChildNodes
}