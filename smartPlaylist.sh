#!/bin/bash
# requires xmlstarlet
IFS=$'\n'

function usage {
	echo "usage: $0 [-b <baseUrl>] -l <playlist> -p <pass> [-s <size>] -t <type> -u <user>"
	echo "	-b default 'http://localhost:4533/rest'"
	echo "	-s default 100, this is a minimum, type 'star' gets all"
	echo "	-t is 'added' or 'star'"
	exit
}

while getopts 'b:l:p:s:t:u:' o; do
	case $o in
		b) baseUrl=$OPTARG ;;
		l) playlist=$OPTARG ;;
		p) pass=$OPTARG ;;
		s) size=$OPTARG ;;
		t) type=$OPTARG ;;
		u) user=$OPTARG ;;
		\?) usage ;;
	esac
done

if [[ -z "$playlist" || -z "$pass" || -z "$type" || -z "$user" ]]; then usage; fi
if [[ -z "$baseUrl" ]]; then baseUrl="http://localhost:4533/rest"; fi
if [[ -z "$size" ]]; then size=100; fi
typeInfo=`echo $type |cut -d':' -f2-`
opts="u=$user&p=$pass&v=1.12&c=smartPlaylist"

if [[ `curl -sk "$baseUrl/ping?$opts" |xmlstarlet sel -N ns=http://subsonic.org/restapi -t -m //ns:subsonic-response -v @status` != 'ok' ]]; then
	echo "	>> bad response from server, check <baseurl>, <user>, and <pass>."
	exit 1
fi

for i in `curl -sk "$baseUrl/getPlaylists?$opts" |xmlstarlet sel -N ns=http://subsonic.org/restapi -t -m //ns:playlist -v @id -o ':' -v @name -n`; do
	if [[ "`echo $i |cut -d':' -f2-`" == "$playlist" ]]; then
		playlistId=`echo $i |cut -d':' -f1`
	fi
done
if [[ "$playlistId" ]]; then
	source=()
	i=0
	case $type in
		'added')
			while [ ${#source[@]} -lt $size ]; do
				id=`curl -sk "$baseUrl/getAlbumList?type=newest&size=1&offset=$i&$opts" |xmlstarlet sel -N ns=http://subsonic.org/restapi -t -m //ns:album -v @id`
				source+=(`curl -sk "$baseUrl/getAlbum?&id=$id&$opts" |xmlstarlet sel -N ns=http://subsonic.org/restapi -t -m //ns:song -v @id -n`)
				((i++))
			done ;;
		'star')
			source+=(`curl -sk "$baseUrl/getStarred?$opts" |xmlstarlet sel -N ns=http://subsonic.org/restapi -t -m //ns:song -v @id -n`) ;;
		*)
			echo "	>> no type '$type' defined."
			exit 1
	esac
	if [[ "$source" ]]; then
		playlistItems=(`curl -sk "$baseUrl/getPlaylist?id=$playlistId&$opts" |xmlstarlet sel -N ns=http://subsonic.org/restapi -t -m //ns:entry -v @id -n`)
		for i in ${source[@]}; do
			if [[ " ${playlistItems[@]} " =~ " $i " ]]; then
				playlistItems=(${playlistItems[@]/$i})
			else
				curl -sk "$baseUrl/updatePlaylist?playlistId=$playlistId&songIdToAdd=$i&$opts" >/dev/null
			fi
		done
		remove=(${playlistItems[@]})
		if [[ "$remove" ]]; then
			for i in ${remove[@]}; do
				playlistItems=(`curl -sk "$baseUrl/getPlaylist?id=$playlistId&$opts" |xmlstarlet sel -N ns=http://subsonic.org/restapi -t -m //ns:entry -v @id -n`)
				for j in ${!playlistItems[@]}; do
					if [[ "${playlistItems[$j]}" == "$i" ]]; then
						curl -sk "$baseUrl/updatePlaylist?playlistId=$playlistId&songIndexToRemove=$j&$opts" >/dev/null
					fi
				done
			done
		fi
	else
		echo "	>> no songs found for type '$type'."
	fi
else
	echo "	>> playlist '$playlist' not found."
fi
