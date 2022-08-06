#!/usr/bin/env bash
scriptVersion="1.0.011"

if [ -z "$lidarrUrl" ] || [ -z "$lidarrApiKey" ]; then
	lidarrUrlBase="$(cat /config/config.xml | xq | jq -r .Config.UrlBase)"
	if [ "$lidarrUrlBase" = "null" ]; then
		lidarrUrlBase=""
	else
		lidarrUrlBase="/$(echo "$lidarrUrlBase" | sed "s/\///g")"
	fi
	lidarrApiKey="$(cat /config/config.xml | xq | jq -r .Config.ApiKey)"
	lidarrUrl="http://127.0.0.1:8686${lidarrUrlBase}"
fi

agent="lidarr-extended ( https://github.com/RandomNinjaAtk/docker-lidarr-extended )"
musicbrainzMirror=https://musicbrainz.org

# Debugging Settings

if [ "$dlClientSource" = "tidal" ] || [ "$dlClientSource" = "both" ]; then
	sourcePreference=tidal
fi

log () {
	m_time=`date "+%F %T"`
	echo $m_time" :: Extended Video :: "$1
}

verifyApiAccess () {
	until false
	do
		lidarrTest=$(wget --timeout=0 -q -O - "$lidarrUrl/api/v1/system/status?apikey=${lidarrApiKey}" | jq -r .branch)
		if [ $lidarrTest = master ]; then
			lidarrVersion=$(wget --timeout=0 -q -O - "$lidarrUrl/api/v1/system/status?apikey=${lidarrApiKey}" | jq -r .version)
			log "Lidarr Version: $lidarrVersion"
			break
		else
			log "Lidarr is not ready, sleeping until valid response..."
			sleep 1
		fi
	done
}

log "-----------------------------------------------------------------------------"
log "|~) _ ._  _| _ ._ _ |\ |o._  o _ |~|_|_|"
log "|~\(_|| |(_|(_)| | || \||| |_|(_||~| | |<"
log "Presents: lidarr-extended ($scriptVersion)"
log "Docker Version: $dockerVersion"
log "May the vidz be with you!"
log "-----------------------------------------------------------------------------"
log "Donate: https://github.com/sponsors/RandomNinjaAtk"
log "Project: https://github.com/RandomNinjaAtk/docker-lidarr-extended"
log "Support: https://github.com/RandomNinjaAtk/docker-lidarr-extended/discussions"
log "-----------------------------------------------------------------------------"
sleep 5
log ""
log "Lift off in..."; sleep 0.5
log "5"; sleep 1
log "4"; sleep 1
log "3"; sleep 1
log "2"; sleep 1
log "1"; sleep 1


Configuration () {
	processstartid="$(ps -A -o pid,cmd|grep "start_video.sh" | grep -v grep | head -n 1 | awk '{print $1}')"
	processdownloadid="$(ps -A -o pid,cmd|grep "video.sh" | grep -v grep | head -n 1 | awk '{print $1}')"
	log "To kill script, use the following command:"
	log "kill -9 $processstartid"
	log "kill -9 $processdownloadid"
	sleep 2
	
	verifyApiAccess

    downloadPath="$downloadPath/videos"
    log "Download Location :: $downloadPath"
    log "Subtitle Language set to: $youtubeSubtitleLanguage"
}

CacheMusicbrainzRecords () {
    lidarrArtists=$(wget --timeout=0 -q -O - "$lidarrUrl/api/v1/artist?apikey=$lidarrApiKey" | jq -r .[])
	lidarrArtistIds=$(echo $lidarrArtists | jq -r .id)
	lidarrArtistIdsCount=$(echo "$lidarrArtistIds" | wc -l)
	processCount=0
	for lidarrArtistId in $(echo $lidarrArtistIds); do
		processCount=$(( $processCount + 1))
        lidarrArtistData=$(echo $lidarrArtists | jq -r "select(.id==$lidarrArtistId)")
		lidarrArtistName=$(echo $lidarrArtistData | jq -r .artistName)
		lidarrArtistMusicbrainzId=$(echo $lidarrArtistData | jq -r .foreignArtistId)
        lidarrArtistPath="$(echo "${lidarrArtistData}" | jq -r " .path")"
		lidarrArtistFolder="$(basename "${lidarrArtistPath}")"
        lidarrArtistFolder="$(echo "$lidarrArtistFolder" | sed "s/ (.*)$//g")" # Plex Sanitization, remove disambiguation
        lidarrArtistNameSanitized="$(echo "$lidarrArtistFolder" | sed 's% (.*)$%%g')"

        if  [ "$lidarrArtistName" == "Various Artists" ]; then
		    log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: Skipping, not processed by design..."
            continue
        fi

        log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: Processing..."
        log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: Checking Musicbrainz for recordings..."
        musicbrainzArtistRecordings=$(curl -s -A "$agent" "$musicbrainzMirror/ws/2/recording?artist=$lidarrArtistMusicbrainzId&limit=1&offset=0&fmt=json")
		sleep 1
		musicbrainzArtistRecordingsCount=$(echo "$musicbrainzArtistRecordings" | jq -r '."recording-count"')
        log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: $musicbrainzArtistRecordingsCount recordings found..."
        
        if [ ! -d /config/extended/cache/musicbrainz ]; then
            mkdir -p /config/extended/cache/musicbrainz
            chmod 777 /config/extended/cache/musicbrainz
            chown abc:abc /config/extended/cache/musicbrainz
        fi

        if [ -f "/config/extended/cache/musicbrainz/$lidarrArtistId--$lidarrArtistMusicbrainzId--recordings.json" ]; then
            if ! [[ $(find "/config/extended/cache/musicbrainz" -type f -name "$lidarrArtistId--$lidarrArtistMusicbrainzId--recordings.json" -mtime +7 -print) ]]; then
                log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: Previously cached, skipping..."
            else
                log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: Previously cached, data needs to be updated..."
                rm "/config/extended/cache/musicbrainz/$lidarrArtistId--$lidarrArtistMusicbrainzId--recordings.json"
            fi
            musibrainzArtistDownloadedRecordingsCount=$(cat "/config/extended/cache/musicbrainz/$lidarrArtistId--$lidarrArtistMusicbrainzId--recordings.json" | jq -r .id | wc -l)
            if [ $musicbrainzArtistRecordingsCount -ne $musibrainzArtistDownloadedRecordingsCount  ]; then
                log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: Previously cached, data needs to be updated..."
                rm "/config/extended/cache/musicbrainz/$lidarrArtistId--$lidarrArtistMusicbrainzId--recordings.json"
            fi

            if ! cat "/config/extended/cache/musicbrainz/$lidarrArtistId--$lidarrArtistMusicbrainzId--recordings.json" | grep -i "artist-credit" | read; then
                log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: Previously cached, data needs to be updated..."
                rm "/config/extended/cache/musicbrainz/$lidarrArtistId--$lidarrArtistMusicbrainzId--recordings.json"
            fi
        fi

        if [ ! -f "/config/extended/cache/musicbrainz/$lidarrArtistId--$lidarrArtistMusicbrainzId--recordings.json" ]; then
            offsetcount=$(( $musicbrainzArtistRecordingsCount / 100 ))
            for ((i=0;i<=$offsetcount;i++)); do
                if [ $i != 0 ]; then
                    offset=$(( $i * 100 ))
                    dlnumber=$(( $offset + 100))
                else
                    offset=0
                    dlnumber=$(( $offset + 100))
                fi

                log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: Downloading page $i... ($offset - $dlnumber Results)"
                curl -s -A "$agent" "$musicbrainzMirror/ws/2/recording?artist=$lidarrArtistMusicbrainzId&inc=artist-credits+url-rels+recording-rels+release-rels+release-group-rels&limit=100&offset=$offset&fmt=json" | jq -r ".recordings[]" >> "/config/extended/cache/musicbrainz/$lidarrArtistId--$lidarrArtistMusicbrainzId--recordings.json"
                sleep 1
        
            done
        fi

        log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: Checking records for videos..."
        musibrainzArtistVideoRecordings=$(cat "/config/extended/cache/musicbrainz/$lidarrArtistId--$lidarrArtistMusicbrainzId--recordings.json" | jq -r "select(.video==true)")
        musibrainzArtistVideoRecordingsCount=$(echo "$musibrainzArtistVideoRecordings" | jq -r .id | wc -l)
        log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: $musibrainzArtistVideoRecordingsCount videos found..."
        musibrainzArtistVideoRecordingsDataWithUrl=$(echo "$musibrainzArtistVideoRecordings" | jq -r "select(.relations[].url)" | jq -s "." | jq -r "unique | .[]")
        musibrainzArtistVideoRecordingsDataWithUrlIds=$(echo "$musibrainzArtistVideoRecordingsDataWithUrl" | jq -r .id)
        musibrainzArtistVideoRecordingsDataWithUrlIdsCount=$(echo "$musibrainzArtistVideoRecordingsDataWithUrl" | jq -r .id | wc -l)
        log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: $musibrainzArtistVideoRecordingsDataWithUrlIdsCount videos found with URL..."

        if [ $musibrainzArtistVideoRecordingsDataWithUrlIdsCount = 0 ]; then
            log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ERROR :: No vidoes with URLs to process, skipping..."
            continue
        fi

        for musicbrainzVideoId in $(echo "$musibrainzArtistVideoRecordingsDataWithUrlIds"); do
            musibrainzVideoRecordingData=$(echo "$musibrainzArtistVideoRecordingsDataWithUrl" | jq -r "select(.id==\"$musicbrainzVideoId\")")
            musibrainzVideoTitle="$(echo "$musibrainzVideoRecordingData" | jq -r .title)"
            musibrainzVideoTitleClean="$(echo "$musibrainzVideoTitle" | sed -e "s%[^[:alpha:][:digit:]]% %g" -e "s/  */ /g" | sed 's/^[.]*//' | sed  's/[.]*$//g' | sed  's/^ *//g' | sed 's/ *$//g')"
            musibrainzVideoArtistCredits="$(echo "$musibrainzVideoRecordingData" |  jq -r ".\"artist-credit\"[]")"
            musibrainzVideoArtistCreditsNames="$(echo "$musibrainzVideoArtistCredits" |  jq -r ".artist.name")"
            musibrainzVideoArtistCreditId="$(echo "$musibrainzVideoArtistCredits" |  jq -r ".artist.id" | head -n1)"
            musibrainzVideoDisambiguation=""
            musibrainzVideoDisambiguation="$(echo "$musibrainzVideoRecordingData" | jq -r .disambiguation)"
            if [ ! -z "$musibrainzVideoDisambiguation" ]; then
                musibrainzVideoDisambiguation=" ($musibrainzVideoDisambiguation)"
                musibrainzVideoDisambiguationClean=" ($(echo "$musibrainzVideoDisambiguation" | sed -e "s%[^[:alpha:][:digit:]]% %g" -e "s/  */ /g" | sed 's/^[.]*//' | sed  's/[.]*$//g' | sed  's/^ *//g' | sed 's/ *$//g'))"
            else
                musibrainzVideoDisambiguation=""
                musibrainzVideoDisambiguationClean=""
            fi
            musibrainzVideoRelations="$(echo "$musibrainzVideoRecordingData" | jq -r .relations[].url.resource)"

            if [ $sourcePreference = tidal ]; then
                if echo "$musibrainzVideoRelations" | grep -i "tidal" | read; then
                    videoDownloadUrl="$(echo "$musibrainzVideoRelations" | grep -i "tidal" | head -n1)"
                else
                    videoDownloadUrl="$(echo "$musibrainzVideoRelations" | grep -i "youtube" | head -n1)"
                fi
            else
                videoDownloadUrl="$(echo "$musibrainzVideoRelations" | grep -i "youtube" | head -n1)"
            fi

            log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: $videoDownloadUrl..."

            if ! echo "$musibrainzVideoDisambiguation" | grep -i "official" | read; then
                log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: ERROR :: Video is not Official, skipping..."
                continue
            else
                if echo "$musibrainzVideoDisambiguation" | grep -i "lyric" | read; then
                    plexVideoType="-lyrics"
                    videoDisambiguationTitle=" (lyric)"
                else
                    plexVideoType="-video"
                    videoDisambiguationTitle=""
                fi
            fi

            

            if [ -f "/music-videos/$lidarrArtistFolder/${musibrainzVideoTitleClean}${plexVideoType}.mkv" ]; then
                log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: Previously Downloaded, skipping..."
                continue
            fi

            if [ "$musibrainzVideoArtistCreditId" != "$lidarrArtistMusicbrainzId" ]; then
                log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: First artist does not match album arist, skipping..."
                continue
            fi

            if [ -d "$downloadPath/incomplete" ]; then
                rm -rf "$downloadPath/incomplete"
            fi

            if [ ! -d "$downloadPath/incomplete" ]; then
                mkdir -p "$downloadPath/incomplete"
                chmod 777 "$downloadPath/incomplete"
                chown abc:abc "$downloadPath/incomplete"
            fi 

            log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: Downloading..."

            if echo "$videoDownloadUrl" | grep -i "tidal" | read; then
                TidalClientTest
                sleep 1
                TidaldlStatusCheck
                videoId="$(echo "$videoDownloadUrl" | grep -o '[[:digit:]]*')"
                videoData="$(curl -s "https://api.tidal.com/v1/videos/$videoId?countryCode=$tidalCountryCode" -H 'x-tidal-token: CzET4vdadNUFQ5JU' | jq -r)"
                videoDate="$(echo "$videoData" | jq -r ".releaseDate")"
                videoYear="${videoDate:0:4}"
                videoImageId="$(echo "$videoData" | jq -r ".imageId")"
                videoImageIdFix="$(echo "$videoImageId" | sed "s/-/\//g")"
                videoThumbnail="https://resources.tidal.com/images/$videoImageIdFix/750x500.jpg"
                tidal-dl -o "$downloadPath/incomplete" -l "$videoDownloadUrl" &>/dev/null
                curl -s "$videoThumbnail" -o "$downloadPath/incomplete/${musibrainzVideoTitleClean}${plexVideoType}.jpg"
            fi

            if echo "$videoDownloadUrl" | grep -i "youtube" | read; then
                videoData="$(yt-dlp -j "$videoDownloadUrl")"
                videoThumbnail="$(echo "$videoData" | jq -r .thumbnail)"
                videoUploadDate="$(echo "$videoData" | jq -r .upload_date)"
                videoYear="${videoUploadDate:0:4}"
                yt-dlp -o "$downloadPath/incomplete/${musibrainzVideoTitleClean}${plexVideoType}" --embed-subs --sub-lang $youtubeSubtitleLanguage --merge-output-format mkv --remux-video mkv --no-mtime --geo-bypass "$videoDownloadUrl" &>/dev/null
                curl -s "$videoThumbnail" -o "$downloadPath/incomplete/${musibrainzVideoTitleClean}${plexVideoType}.jpg"
            fi

            find "$downloadPath/incomplete" -type f -regex ".*/.*\.\(mkv\|mp4\)"  -print0 | while IFS= read -r -d '' video; do
                count=$(($count+1))
                file="${video}"
				filenoext="${file%.*}"
                filename="$(basename "$video")"
                extension="${filename##*.}"
                filenamenoext="${filename%.*}"

                if python3 /usr/local/sma/manual.py --config "/config/extended/scripts/sma.ini" -i "$file" -nt &>/dev/null; then
					sleep 0.01
					log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: Processed with SMA..."
					rm  /usr/local/sma/config/*log*
				else
					log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: ERROR: SMA Processing Error"
					rm "$video"
                    log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: INFO: deleted: $filename"
				fi

                if [ ! -f "$filenoext.mkv" ]; then
                    break
                fi

                artistGenres=""
                OLDIFS="$IFS"
				IFS=$'\n'
				artistGenres=($(echo $lidarrArtistData | jq -r ".genres[]"))
				IFS="$OLDIFS"

                if [ ! -z "$artistGenres" ]; then
                    for genre in ${!artistGenres[@]}; do
                        artistGenre="${artistGenres[$genre]}"
                        OUT=$OUT"$artistGenre / "
                    done
                    genre="${OUT%???}"
                else
                    genre=""
                fi

                mv "$filenoext.mkv" "$filenoext-temp.mkv"
				log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: Tagging file"
				ffmpeg -y \
					-i "$filenoext-temp.mkv" \
					-c copy \
					-metadata TITLE="${musibrainzVideoTitle}${videoDisambiguationTitle}" \
					-metadata DATE_RELEASE="$videoYear" \
					-metadata DATE="$videoYear" \
					-metadata YEAR="$videoYear" \
					-metadata GENRE="$genre" \
					-metadata ARTIST="$lidarrArtistName" \
					-metadata ALBUMARTIST="$lidarrArtistName" \
					-metadata ENCODED_BY="lidarr-extended" \
					-attach "$downloadPath/incomplete/${musibrainzVideoTitleClean}${plexVideoType}.jpg" -metadata:s:t mimetype=image/jpeg \
					"$filenoext.mkv" &>/dev/null


                if [ ! -d "/music-videos/$lidarrArtistFolder" ]; then
                    mkdir -p "/music-videos/$lidarrArtistFolder"
                    chmod 777 "/music-videos/$lidarrArtistFolder"
                    chown abc:abc "/music-videos/$lidarrArtistFolder"
                fi 

                
                if [ -f "$downloadPath/incomplete/${musibrainzVideoTitleClean}${plexVideoType}.jpg" ]; then
                    mv "$downloadPath/incomplete/${musibrainzVideoTitleClean}${plexVideoType}.jpg" "/music-videos/$lidarrArtistFolder"/
                    chmod 666 "/music-videos/$lidarrArtistFolder/${musibrainzVideoTitleClean}${plexVideoType}.jpg"
                    chown abc:abc "/music-videos/$lidarrArtistFolder/${musibrainzVideoTitleClean}${plexVideoType}.jpg"
                fi

                log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: Writing NFO"
                nfo="/music-videos/$lidarrArtistFolder/${musibrainzVideoTitleClean}${plexVideoType}.nfo"
                if [ -f "$nfo" ]; then
                    rm "$nfo"
                fi
                echo "<musicvideo>" >> "$nfo"
                echo "	<title>${musibrainzVideoTitle}${videoDisambiguationTitle}</title>" >> "$nfo"
                echo "	<userrating/>" >> "$nfo"
                echo "	<track/>" >> "$nfo"
                echo "	<studio/>" >> "$nfo"
                if [ ! -z "$artistGenres" ]; then
                    for genre in ${!artistGenres[@]}; do
                        artistGenre="${artistGenres[$genre]}"
                        echo "	<genre>$artistGenre</genre>" >> "$nfo"
                    done
                fi
                echo "	<premiered/>" >> "$nfo"
                echo "	<year>$videoYear</year>" >> "$nfo"
                OLDIFS="$IFS"
			    IFS=$'\n'
                for artistName in $(echo "$musibrainzVideoArtistCreditsNames"); do 
                    echo "	<artist>$artistName</artist>" >> "$nfo"
                done
                IFS="$OLDIFS"
                echo "	<albumArtistCredits>" >> "$nfo"
			    echo "		<artist>$lidarrArtistName</artist>" >> "$nfo"
			    echo "		<musicBrainzArtistID>$lidarrArtistMusicbrainzId</musicBrainzArtistID>" >> "$nfo"
			    echo "	</albumArtistCredits>" >> "$nfo"
                if [ -f "/music-videos/$lidarrArtistFolder/${musibrainzVideoTitleClean}${plexVideoType}.jpg" ]; then
                    echo "	<thumb>${musibrainzVideoTitleClean}${plexVideoType}.jpg</thumb>" >> "$nfo"
                else
                    echo "	<thumb/>" >> "$nfo"
                fi
                echo "</musicvideo>" >> "$nfo"

                chmod 666 "$nfo"
                chown abc:abc "$nfo"

                log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: Moving completed download to: /music-videos/$lidarrArtistFolder/${musibrainzVideoTitleClean}${plexVideoType}.mkv"
                mv "$filenoext.mkv" "/music-videos/$lidarrArtistFolder/${musibrainzVideoTitleClean}${plexVideoType}.mkv"
                chmod 666 "/music-videos/$lidarrArtistFolder/${musibrainzVideoTitleClean}${plexVideoType}.mkv"
                chown abc:abc "/music-videos/$lidarrArtistFolder/${musibrainzVideoTitleClean}${plexVideoType}.mkv"          
                

            done
        done
    done
}

TidalClientSetup () {
	log "TIDAL :: Verifying tidal-dl configuration"
	touch /config/xdg/.tidal-dl.log
	if [ -f /config/xdg/.tidal-dl.json ]; then
		rm /config/xdg/.tidal-dl.json
	fi
	if [ ! -f /config/xdg/.tidal-dl.json ]; then
		log "TIDAL :: No default config found, importing default config \"tidal.json\""
		if [ -f /config/extended/scripts/tidal-dl.json ]; then
			cp /config/extended/scripts/tidal-dl.json /config/xdg/.tidal-dl.json
			chmod 777 -R /config/xdg/
		fi

	fi
	TidaldlStatusCheck
	tidal-dl -o $downloadPath/incomplete
		
	if [ ! -f /config/xdg/.tidal-dl.token.json ]; then
		TidaldlStatusCheck
		log "TIDAL :: ERROR :: Downgrade tidal-dl for workaround..."
		pip install tidal-dl==2022.3.4.2 --no-cache-dir &>/dev/null
		TidaldlStatusCheck
		log "TIDAL :: ERROR :: Loading client for required authentication, please authenticate, then exit the client..."
		tidal-dl
	fi

	if [ ! -d /config/extended/cache/tidal ]; then
		mkdir -p /config/extended/cache/tidal
		chmod 777 /config/extended/cache/tidal
		chown abc:abc /config/extended/cache/tidal
	fi
	
	if [ -d /config/extended/cache/tidal ]; then
		log "TIDAL :: Purging album list cache..."
		find /config/extended/cache/tidal -type f -name "*.json" -delete
	fi
	
	if [ ! -d "$downloadPath/incomplete" ]; then
		mkdir -p $downloadPath/incomplete
		chmod 777 $downloadPath/incomplete
		chown abc:abc $downloadPath/incomplete
	else
		rm -rf $downloadPath/incomplete/*
	fi
	
    TidaldlStatusCheck
	log "TIDAL :: Upgrade tidal-dl to newer version..."
	pip install tidal-dl==2022.07.06.1 --no-cache-dir &>/dev/null
	
}

TidalClientTest () { 
	log "TIDAL :: tidal-dl client setup verification..."
    TidaldlStatusCheck
	tidal-dl -o $downloadPath/incomplete -l "166356219" &>/dev/null
	
	downloadCount=$(find $downloadPath/incomplete/ -type f -regex ".*/.*\.\(flac\|opus\|m4a\|mp3\)" | wc -l)
	if [ $downloadCount -le 0 ]; then
		if [ -f /config/xdg/.tidal-dl.token.json ]; then
			rm /config/xdg/.tidal-dl.token.json
		fi
		log "TIDAL :: ERROR :: Download failed"
		log "TIDAL :: ERROR :: You will need to re-authenticate on next script run..."
		log "TIDAL :: ERROR :: Exiting..."
		rm -rf $downloadPath/incomplete/*
		exit
	else
		rm -rf $downloadPath/incomplete/*
		log "TIDAL :: Successfully Verified"
	fi
}

TidaldlStatusCheck () {
	until false
	do
        running=no
        if ps aux | grep "tidal-dl" | grep -v "grep" | read; then 
            running=yes
            log "STATUS :: TIDAL-DL :: BUSY :: Pausing/waiting for all active tidal-dl tasks to end..."
            sleep 2
            continue
        fi
		break
	done
}

ImvdbCache () {

    lidarrArtists=$(wget --timeout=0 -q -O - "$lidarrUrl/api/v1/artist?apikey=$lidarrApiKey" | jq -r .[])
	lidarrArtistIds=$(echo $lidarrArtists | jq -r .id)
	lidarrArtistIdsCount=$(echo "$lidarrArtistIds" | wc -l)
	processCount=0
	for lidarrArtistId in $(echo $lidarrArtistIds); do
		processCount=$(( $processCount + 1))
        lidarrArtistData=$(echo $lidarrArtists | jq -r "select(.id==$lidarrArtistId)")
        lidarrArtistName=$(echo $lidarrArtistData | jq -r .artistName)
		lidarrArtistMusicbrainzId=$(echo $lidarrArtistData | jq -r .foreignArtistId)
        lidarrArtistPath="$(echo "${lidarrArtistData}" | jq -r " .path")"
		lidarrArtistFolder="$(basename "${lidarrArtistPath}")"
        lidarrArtistFolder="$(echo "$lidarrArtistFolder" | sed "s/ (.*)$//g")" # Plex Sanitization, remove disambiguation
        artistImvdbUrl=$(echo $lidarrArtistData | jq -r '.links[] | select(.name=="imvdb") | .url')
        artistImvdbSlug=$(basename "$artistImvdbUrl")
        if [ -z "$artistImvdbSlug" ]; then
            continue
        fi
        if [ ! -f /config/extended/cache/imvdb/$artistImvdbSlug ]; then
            echo "$lidarrArtistName" > /config/extended/cache/imvdb/$artistImvdbSlug
        fi
        artistImvdbVideoUrls=$(curl -s "https://imvdb.com/n/$artistImvdbSlug" | grep "$artistImvdbSlug" | grep -Eoi '<a [^>]+>' |  grep -Eo 'href="[^\"]+"' | grep -Eo '(http|https)://[^"]+' |  grep -i ".com/video/$artistImvdbSlug/" | sed "s%/[0-9]$%%g" | sort -u)
        sleep 0.5
        for imvdbVideoUrl in $(echo "$artistImvdbVideoUrls"); do
            imvdbVideoUrlSlug=$(basename "$imvdbVideoUrl")
            imvdbVideoId=$(curl -s "$imvdbVideoUrl" | grep "<p>ID:" | grep -o "[[:digit:]]*")
            imvdbVideoJsonUrl="https://imvdb.com/api/v1/video/$imvdbVideoId?include=sources,countries,featured,credits,bts,popularity"
            imvdbVideoData="/config/extended/cache/imvdb/$lidarrArtistMusicbrainzId--$imvdbVideoId.json"
            #echo "$imvdbVideoUrl :: $imvdbVideoUrlSlug :: $imvdbVideoId"
            if [ ! -d "/config/extended/cache/imvdb" ]; then
                mkdir -p "/config/extended/cache/imvdb"
                chmod 777 "/config/extended/cache/imvdb"
                chown abc:abc "/config/extended/cache/imvdb"
            fi
            if [ ! -f "$imvdbVideoData" ]; then
                count=0
                until false; do
                    count=$(( $count + 1 ))
                    #echo "$count"
                    if [ ! -f "$imvdbVideoData" ]; then
                        curl -s "$imvdbVideoJsonUrl" -o "$imvdbVideoData"
                        sleep 0.5
                    fi
                    if [ -f "$imvdbVideoData" ]; then
                        if jq -e . >/dev/null 2>&1 <<<"$(cat "$imvdbVideoData")"; then
                            break
                        else
                            rm "$imvdbVideoData"
                        fi
                    fi
                done
            fi
            #cat "$imvdbVideoData"
            imvdbVideoTitle="$(cat "$imvdbVideoData" | jq -r .song_title)"
            videoTitleClean="$(echo "$imvdbVideoTitle" | sed -e "s%[^[:alpha:][:digit:]]% %g" -e "s/  */ /g" | sed 's/^[.]*//' | sed  's/[.]*$//g' | sed  's/^ *//g' | sed 's/ *$//g')"
            imvdbVideoYear="$(cat "$imvdbVideoData" | jq -r .year)"
            imvdbVideoImage="$(cat "$imvdbVideoData" | jq -r .image.o)"
            imvdbVideoArtistsSlug="$(cat "$imvdbVideoData" | jq -r .artists[].slug)"
            echo "$featuredArtistName" > /config/extended/cache/imvdb/$imvdbVideoArtistsSlug
            imvdbVideoFeaturedArtistsSlug="$(cat "$imvdbVideoData" | jq -r .featured_artists[].slug)"
            imvdbVideoYoutubeId="$(cat "$imvdbVideoData" | jq -r ".sources[] | select(.is_primary==true) | select(.source==\"youtube\") | .source_data")"
            #"/config/extended/cache/musicbrainz/$lidarrArtistId--$lidarrArtistMusicbrainzId--recordings.json"
            echo "$imvdbVideoTitle :: $imvdbVideoYear :: $imvdbVideoYoutubeId :: $imvdbVideoArtistsSlug"
            if [ -z "$imvdbVideoYoutubeId" ]; then
                continue
            fi
            videoDownloadUrl="https://www.youtube.com/watch?v=$imvdbVideoYoutubeId"
            plexVideoType="-video"
            if [[ -n $(find "/music-videos/$lidarrArtistFolder" -iname "${videoTitleClean}${plexVideoType}.*") ]]; then
                echo "already dl..."
                continue
            fi

            videoData="$(yt-dlp -j "$videoDownloadUrl")"
            videoThumbnail="$imvdbVideoImage"   
            videoUploadDate="$(echo "$videoData" | jq -r .upload_date)"
            videoYear="${videoUploadDate:0:4}"
           

            if [ ! -z "$imvdbVideoFeaturedArtistsSlug" ]; then
                for featuredArtistSlug in $(echo "$imvdbVideoFeaturedArtistsSlug"); do
                    if [ -f /config/extended/cache/imvdb/$featuredArtistSlug ]; then
                        featuredArtistName="$(cat /config/extended/cache/imvdb/$featuredArtistSlug)"
                    else
                        query_data=$(curl -s -A "$agent" "https://musicbrainz.org/ws/2/url?query=url:%22https://imvdb.com/n/$featuredArtistSlug%22&fmt=json")
                        count=$(echo "$query_data" | jq -r ".count")			
                        if [ "$count" != "0" ]; then
                            featuredArtistName="$(echo "$query_data" | jq -r ".urls[].\"relation-list\"[].relations[].artist.name")"
                            echo "$featuredArtistName" > /config/extended/cache/imvdb/$featuredArtistSlug
                            sleep 1
                        fi
                    fi
                    if [ -z "$featuredArtistName" ]; then
                        echo "$featuredArtistSlug :: not found"
                        continue
                    fi
                done
            fi
            
            DownloadVideo "$videoDownloadUrl" "$videoTitleClean" "$plexVideoType"
            DownloadThumb "$imvdbVideoImage" "$videoTitleClean" "$plexVideoType" 
            VideoProcessWithSMA
            VideoTagProcess "$videoTitleClean" "$plexVideoType" "$videoYear"
            VideoNfoWriter "$videoTitleClean" "$plexVideoType" "$imvdbVideoTitle" "" "imvdb" "$videoYear"
            
            if [ ! -d "/music-videos/$lidarrArtistFolder" ]; then
                mkdir -p "/music-videos/$lidarrArtistFolder"
                chmod 777 "/music-videos/$lidarrArtistFolder"
                chown abc:abc "/music-videos/$lidarrArtistFolder"
            fi 

            mv $downloadPath/incomplete/* "/music-videos/$lidarrArtistFolder"/
            
            
        done
    done
}


DownloadVideo () {

    if [ -d "$downloadPath/incomplete" ]; then
        rm -rf "$downloadPath/incomplete"
    fi

    if [ ! -d "$downloadPath/incomplete" ]; then
        mkdir -p "$downloadPath/incomplete"
        chmod 777 "$downloadPath/incomplete"
        chown abc:abc "$downloadPath/incomplete"
    fi 

    if echo "$1" | grep -i "youtube" | read; then
        yt-dlp -o "$downloadPath/incomplete/${2}${3}" --embed-subs --sub-lang $youtubeSubtitleLanguage --merge-output-format mkv --remux-video mkv --no-mtime --geo-bypass "$1" &>/dev/null
    fi
    chmod 666 "$downloadPath/incomplete/${2}${3}.mkv"
    chown abc:abc "$downloadPath/incomplete/${2}${3}.mkv"

}

DownloadThumb () {

    curl -s "$1" -o "$downloadPath/incomplete/${2}${3}.jpg"
    chmod 666 "$downloadPath/incomplete/${2}${3}.jpg"
    chown abc:abc "$downloadPath/incomplete/${2}${3}.jpg"

}

VideoProcessWithSMA () {
    find "$downloadPath/incomplete" -type f -regex ".*/.*\.\(mkv\|mp4\)"  -print0 | while IFS= read -r -d '' video; do
        count=$(($count+1))
        file="${video}"
        filenoext="${file%.*}"
        filename="$(basename "$video")"
        extension="${filename##*.}"
        filenamenoext="${filename%.*}"

        if python3 /usr/local/sma/manual.py --config "/config/extended/scripts/sma.ini" -i "$file" -nt &>/dev/null; then
            sleep 0.01
            log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: Processed with SMA..."
            rm  /usr/local/sma/config/*log*
        else
            log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: ERROR: SMA Processing Error"
            rm "$video"
            log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: INFO: deleted: $filename"
        fi
    done
}

VideoTagProcess () {
    find "$downloadPath/incomplete" -type f -regex ".*/.*\.\(mkv\|mp4\)"  -print0 | while IFS= read -r -d '' video; do
        count=$(($count+1))
        file="${video}"
        filenoext="${file%.*}"
        filename="$(basename "$video")"
        extension="${filename##*.}"
        filenamenoext="${filename%.*}"
        artistGenres=""
        OLDIFS="$IFS"
		IFS=$'\n'
		artistGenres=($(echo $lidarrArtistData | jq -r ".genres[]"))
		IFS="$OLDIFS"

        if [ ! -z "$artistGenres" ]; then
            for genre in ${!artistGenres[@]}; do
                artistGenre="${artistGenres[$genre]}"
                OUT=$OUT"$artistGenre / "
            done
            genre="${OUT%???}"
        else
            genre=""
        fi

        mv "$filenoext.mkv" "$filenoext-temp.mkv"
		log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${1}${2} $3 :: Tagging file"
		ffmpeg -y \
			-i "$filenoext-temp.mkv" \
			-c copy \
			-metadata TITLE="${1}" \
			-metadata DATE_RELEASE="$3" \
			-metadata DATE="$3" \
			-metadata YEAR="$3" \
			-metadata GENRE="$genre" \
			-metadata ARTIST="$lidarrArtistName" \
			-metadata ALBUMARTIST="$lidarrArtistName" \
			-metadata ENCODED_BY="lidarr-extended" \
			-attach "$downloadPath/incomplete/${1}${2}.jpg" -metadata:s:t mimetype=image/jpeg \
			"$filenoext.mkv" &>/dev/null
        rm "$filenoext-temp.mkv"
        chmod 666 "$filenoext.mkv"
        chown abc:abc "$filenoext.mkv"
    done
}

VideoNfoWriter () {
    log "$processCount of $lidarrArtistIdsCount :: MBZDB CACHE :: $lidarrArtistName :: ${musibrainzVideoTitle}${musibrainzVideoDisambiguation} :: Writing NFO"
    nfo="$downloadPath/incomplete/${1}${2}.nfo"
    if [ -f "$nfo" ]; then
        rm "$nfo"
    fi
    echo "<musicvideo>" >> "$nfo"
    echo "	<title>${3}${4}</title>" >> "$nfo"
    echo "	<userrating/>" >> "$nfo"
    echo "	<track/>" >> "$nfo"
    echo "	<studio/>" >> "$nfo"
    artistGenres=""
    OLDIFS="$IFS"
	IFS=$'\n'
	artistGenres=($(echo $lidarrArtistData | jq -r ".genres[]"))
	IFS="$OLDIFS"
    if [ ! -z "$artistGenres" ]; then
        for genre in ${!artistGenres[@]}; do
            artistGenre="${artistGenres[$genre]}"
            echo "	<genre>$artistGenre</genre>" >> "$nfo"
        done
    fi
    echo "	<premiered/>" >> "$nfo"
    echo "	<year>$6</year>" >> "$nfo"
    if [ "$5" = "musicbrainz" ]; then
        OLDIFS="$IFS"
        IFS=$'\n'
        for artistName in $(echo "$musibrainzVideoArtistCreditsNames"); do 
            echo "	<artist>$artistName</artist>" >> "$nfo"
        done
        IFS="$OLDIFS"
    fi
    if [ "$5" = "imvdb" ]; then
        echo "	<artist>$lidarrArtistName</artist>" >> "$nfo"
        for featuredArtistSlug in $(echo "$imvdbVideoFeaturedArtistsSlug"); do
            if [ -f /config/extended/cache/imvdb/$featuredArtistSlug ]; then
                featuredArtistName="$(cat /config/extended/cache/imvdb/$featuredArtistSlug)"
                echo "	<artist>$featuredArtistName</artist>" >> "$nfo"
            fi
        done
    fi
    echo "	<albumArtistCredits>" >> "$nfo"
	echo "		<artist>$lidarrArtistName</artist>" >> "$nfo"
	echo "		<musicBrainzArtistID>$lidarrArtistMusicbrainzId</musicBrainzArtistID>" >> "$nfo"
	echo "	</albumArtistCredits>" >> "$nfo"
    echo "	<thumb>${1}${2}.jpg</thumb>" >> "$nfo"
    echo "</musicvideo>" >> "$nfo"
    chmod 666 "$nfo"
    chown abc:abc "$nfo"


}

Configuration
#TidalClientSetup
#CacheMusicbrainzRecords
ImvdbCache

exit