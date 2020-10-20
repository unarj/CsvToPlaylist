Param(
	[string]$Server = 'http://navidrome:4533',
	[string]$User,
	[string]$Pass,
	[string]$Playlist,
	[string]$Source
)

if(!$Server -or !$User -or !$Pass -or !$Playlist -or !$Source){
	"  >> -Server <http://navidrome:4533> -User <username> -Pass <password> -Playlist <playlist name> -Source <csv file with artist,album,title>"
	exit 1
}

$src = Import-Csv $Source
if(!$src){
	" >> error reading CSV at '$Source'."
	exit 1
}

$opts = "u=$User&p=$Pass&v=1.12&c=CsvToPlaylist"

$playlistId = $false
$r = Invoke-RestMethod "$Server/rest/ping?$opts"
if(($r.ChildNodes.xmlns -eq 'http://subsonic.org/restapi') -and ($r.ChildNodes.status -eq 'ok')){
	$r = Invoke-RestMethod "$Server/rest/getPlaylists?$opts"
	foreach($pl in $r.ChildNodes.playlists.playlist){
		if($pl.name -eq $Playlist){
			$playlistId = $pl.id
			break
		}
	}
	if($playlistId){
		$playlistItems = (Invoke-RestMethod "$Server/rest/getPlaylist?$opts&id=$playlistId").ChildNodes.playlist.entry
		if(!$playlistItems){ $playlistItems = @() }
		"  >> source has {0} items, playlist '{1}' currently has {2} items in it." -f $src.Count,$Playlist,$playlistItems.Count
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
							if(!$playlistItems.id.Contains($found.id)){
								Write-Host ("query '{0}' found track '{1}'({2}), adding to playlist '{3}'... " -f $q,$found.title,$found.id,$Playlist) -NoNewLine
								(Invoke-RestMethod ("$Server/rest/updatePlaylist?$opts&playlistId=$playlistId&=songIdToAdd"+$found.id)).ChildNodes.status
							}else{
								$playlistItems = $playlistItems |?{$_.id -ne $found.id}
							}
						}
					}
				}
			}
			if(!$songFound){
				if($found.Count -gt 1){
					"  >> too many hits for '{0}' '{1}' '{2}'." -f $x.artist,$x.album,$x.title
				}else{
					"  >> not able to find '{0}' '{1}' '{2}'." -f $x.artist,$x.album,$x.title
				}
			}
		}
		if($playlistItems){
			"`n  >> items in playlist not accounted for..."
			$playlistItems |Select artist,album,title
		}
		do{
			$playlistItems = (Invoke-RestMethod "$Server/rest/getPlaylist?$opts&id=$playlistId").ChildNodes.playlist.entry
			$dupFound = $false
			$dup = @{}
			$playlistItems.id |%{$dup["$_"]++}
			foreach($x in $dup.keys |?{$dup["$_"] -gt 1}){
				$dupFound = $true
				$i = [array]::lastindexof($playlistItems.id,$x)
				Write-Host (" >> removing duplicate track '{0}' '{1}' from '{2}'... " -f $playlistItems[$i].artist,$playlistItems[$i].title,$Playlist) -NoNewLine
				(Invoke-RestMethod ("$Server/rest/updatePlaylist?$opts&playlistId=$playlistId&songIndexToRemove="+($i+1))).ChildNodes.status
				$playlistItems.RemoveAt($i)
			}
		}while($dupFound)
		"  >> '{0}' now has {1} items in it, ciao." -f $playlist,((Invoke-RestMethod "$Server/rest/getPlaylist?$opts&id=$playlistId").ChildNodes.playlist.entry).Count
	}else{
		"  >> error locating playlist '$Playlist'."
	}
}else{
	"  >> bad response from server '{0}'." -f $r.ChildNodes
}