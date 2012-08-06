#!/bin/bash
# The Script will search the next id starting from the given one+1.
# Faengt bei ID+1 an und inkrementiert solange bis die neachste ID gueltig ist.

# This scripts knows two working modes.
#  1. Search next valid album ID on Jamendo.
#    - with different profiles, e.g. starting from beginning of jamendo or from id xxx...
#  2. Download/Open/Load m3u into Player a track/album based on trackid/albumid or a jamendo url.
#
#LICENSE="GPLv3"

## SETTINGS ##
jl__download_dest="$HOME/stack/music" #Where your music should be downloaded to.
jl__tmp_m3u=/tmp/jamendo/${$}_jamendo.m3u #Save m3u File to ... only temporary ... todo: remove temp data

## EXTERNAL PROGRAMS ##
jl__download_app=/usr/bin/chromium
jl__bin_mocp="mocp"
#"/home/apps/moc/bin/mocp"
jl__bin_vlc=$(which vlc)
jl__bin_mplayer=$(which mplayer)
jl__bin_mplayer2=$(which mplayer2)



## DO NOT EDIT BELOW THIS LINE ##
jl__dwl_baseurl="http://www.jamendo.com/de/download/album"
jl__next_id=0
arg__url_type='album'

jl__workdir="${HOME}/.local/share/jamendo_listen"

jl__lvurl_filename=lvurl
jl__downloaded_filename=jamendo_downloaded
jl__save_last_valid_url=${jl__workdir}/${jl__lvurl_filename} #Save the last valid url to this file.
jl__downloaded=${jl__workdir}/${jl__downloaded_filename}
arg__verbose=false
jl__stop_after_x_fails=200 #Stop after this count of failed IDs. Probably we are at the end of the ID List ... :P
arg__suffix=""

function help() {
cat << EOF
$0

Options
 -h|--help                		This help.
 -v|--verbose				Be verbose.
 -de|-debug|--debug			Use shell tracing "set -x"
 -i|--id				Album ID. ID is always an album ID. For others user -url.
 -url|--url				Instead of Album ID you can use the whole URL (without last /).
 -plv|--print-last-valid		Prints the last valid album ID from ${jl__save_last_valid_url} and exit.
 -sn|--searchnextid                     Search for the next valid album ID, store and display it.
 -d|--download                		Use app to download current song. (Currently ${jl__download_app}).
					Requesting a download for a track results in the complete album download :)
 -pd|--print-download-page-url		Print url to download page.
 -o|--open-album-page			Use app to open the album page. (Currently ${jl__download_app}).
 -lm PLAYER                             Downloads the m3u file of the id and loads it into player X (default is last valid id from ${jl__save_last_valid_url}).
 -snlm PLAYER                           Search next album ID and load album m3u into player X (-sn + -lm X).
                                        PLAYER can be:
                                           m|moc for Music On Console
                                           v|vlc for Video Lan Client
					   mp|mplayer for MPlayer
					   mp2|mplayer2 for MPlayer2
                                        This is neccessary because every player has different commands to load playlists etc.
 -3|--printm3uurl			Prints m3u URL of given ID (default is last valid id from ${jl__save_last_valid_url}).
 -lvf					Use given file to store last valid id instead of default ${jl__save_last_valid_url}.
 -sx|--suffix				By using a suffix (which will affect all used files/directories, but not jl__tmp_m3u) you can search
 					different id pools. E.g. -sx start for id=0 ... or -sx current...
					It adds the given parameter to ${jl__save_last_valid_url} with a _ between.
					Default suffix is empty. This replaces -lvf.
                                        For now you need to create this file
					and add the last line must contain any (valid or unvalid) Jamendo-ID. If this files does
                                        not exist it will be created and the process will start from 0.
 -ps|--print-suffixes			Print available suffixes


Note: The last valid ID will only be saved to ${jl__save_last_valid_url} when using -sn or -snlm.
EOF
}

#Get a download link for m3u file to the according id.
# $1 - Album ID
function get_m3u_url_from_id() {
    if [ "${arg__url_type}" = "album" ]
    then
    	#echo "http://api.jamendo.com/get2/stream/track/plain/?album_id=${1}&order=numalbum_asc&n=all&streamencoding=ogg2"
	echo "http://api.jamendo.com/get2/stream/track/m3u/?album_id=${1}&order=numalbum_asc&n=all"
    elif [ "${arg__url_type}" = 'track' ]
    then
	echo "http://api.jamendo.com/get2/stream/track/m3u/?track_id=${1}&order=numtrack_asc&n=all"
    fi
}

#Downloads the album m3u file according to the album id.
# $1 - album ID
function download_m3u() {
    local _id=$1
    local _url=$(get_m3u_url_from_id ${_id})
    [ ! -d "$(dirname ${jl__tmp_m3u})" ] && mkdir "$(dirname ${jl__tmp_m3u})"
    wget -O "${jl__tmp_m3u}" "${_url}" &>/dev/null

    #Special for better quality on jamendo :)
    #Jamendo gibt nur das Format mp31 fuer Streams als Standard raus; man kann jedoch auch das
    # beste Format streamen lassen, wenn man es selbst aendert; man muss statt format=mp31 format=irgendwasanderes angeben.
    # Siehe hier: http://developer.jamendo.com/fr/wiki/MusiclistApi -> List of Audio Encodings
    sed -i 's/\&format=mp31/\&format=ogg2/g' ${jl__tmp_m3u}

    #If any error occurs, exit here with status from wget.
    if [ "$?" !=  "0" ];
    then
        if [ "${arg__verbose}" = "true" ];
	then
	    echo "Error: wget exit status $?"
	fi
	exit $?
    fi
}

#Prints saved id in ${jl__save_last_valid_url}.
#No Arguments.
function print_saved_last_valid_id() {
    cat "${jl__save_last_valid_url}${arg__suffix}"
}

function print_suffixes() {
    #local _dirname="$(dirname ${jl__save_last_valid_url})"
    #local _suffix_files=$(find "${_dirname}" -iname "*_*")
    local _suffix_files=$(cd ${jl__workdir} && find -iname "${jl__lvurl_filename}_*" | grep -v "_history")
    for i in $(echo ${_suffix_files})
    do
      echo ${i##./lvurl_}
    done
}

function replace_m3u_redirects() {
    # Because Jamendo changed their url schema again, this is neccessary. This time they not only changed url schema,
    #  but they are also fixme dynamic host bla. So we need to replace every url in a m3u-file with its 
    #  redirection.
    
    #from http://storage-new.newjamendo.com?trackid=661833&format=ogg2&u=0
    #to different hosts like   http://storage-new[1|2].newjamendo.com/tracks/661833_112.ogg
    #but different hosts for almost every song...

    while read line;
    do
       ifmatch="$( echo $line | grep -i '^http')"
       if [ ! -z "$ifmatch" ]; then
           _redirected=$(curl -v "$line" 2>&1 | sed -n -r -e 's#.*Location: (http.*)$#\1#p')
	   sed -i "s#$line#${_redirected}#g" ${jl__tmp_m3u}
       fi
    done<${jl__tmp_m3u}
}

#Determines the given player and loads the m3u file into it.
# $1 - Player
function load_m3u_to_player() {
    replace_m3u_redirects 

    case ${1} in
      v|vlc)
	  "${jl__bin_vlc}" "${jl__tmp_m3u}" > /dev/null 2>&1 &
	;;
      m|moc)
	  "$jl__bin_mocp" -c &
	  sleep 1
	  "$jl__bin_mocp" -a "${jl__tmp_m3u}" &
	  
	  #We need this trick; without sleep x mocp would not start playing because it is still executing this script.
	  sleep 1.5 && "$jl__bin_mocp" -p & #Sleep times must be increased on heavy loaded systems.
        ;;
      mp|mplayer)
	  echo -e "Song count: $(grep '^http://' ${jl__tmp_m3u} | wc -l)"
	  echo -e "Album ID: ${jl__next_id}\n"
	  echo -e "Playlist file: ${jl__tmp_m3u}\n"
          "${jl__bin_mplayer}" -playlist ${jl__tmp_m3u}
	;;
      mp2|mplayer2)
	  echo -e "Song count: $(grep '^http://' ${jl__tmp_m3u} | wc -l)"
	  echo -e "Album ID: ${jl__next_id}\n"
	  echo -e "Playlist file: ${jl__tmp_m3u}\n"
          "${jl__bin_mplayer2}" -playlist ${jl__tmp_m3u}
	;;
    esac
}

#Uses ID+1 and increments to find the next valid ID.
# $1 - Album ID
function search_next_jid() {
    local _id=$1
    local _found=0
    local _counter=0

    _id=$((${_id}+1))
    while ! [ $_found == 1 ];
    do
        download_m3u ${_id}
	if [ "$(wc -l ${jl__tmp_m3u}|cut -d' ' -f1)" -gt "1" ]; #If the Album of ID x doesn't exist the m3u file contains only 1 line.
	then
	    _found=1
            jl__next_id=${_id}
	    
            echo "${jl__next_id}" > ${jl__save_last_valid_url}${arg__suffix} #Save last valid url to a file ... zur Sicherheit.
	    echo "${jl__next_id} at $(date)" >> "${jl__save_last_valid_url}${arg__suffix}_history"
	else
	    [ "${arg__verbose}" = "true" ] && echo "Album ID \"${_id}\" does not exist."
	fi

        _id=$((${_id}+1))
	_counter=$((${_counter}+1))
	if [ ${_counter} -gt ${jl__stop_after_x_fails} ]; then
	    [ "${arg__verbose}" = "true" ] && echo "No new valid ID for ${jl__stop_after_x_fails} times. Break..."
	    exit 3
	fi
    done
    return 0
}

#Starts application x to open the album download page.
# $1 - Album ID
function open_download_page() {
    #"${jl__download_app}" "${jl__dwl_baseurl}/$1/?output=contentonly#" &>/dev/null &
    #"${jl__download_app}" "http://www.jamendo.com/get/album/id/album/archiverestricted/redirect/$1/?are=ogg3" &>/dev/null &

    if [ "${arg__url_type}" = "album" ]
    then
    	#"${jl__download_app}" "http://www.jamendo.com/get/album/id/album/archiverestricted/redirect/$1/?are=ogg3" > /dev/null 2&>1 &
	#Direktdownload funktioniert nun...
	local __url="http://www.jamendo.com/get/album/id/album/archiverestricted/redirect/$1/?are=ogg3"
    	if [ "${arg__print_download_page_url}" = "true" ]
	then
		echo ${__url}
	else
		wget --trust-server-names --directory-prefix=${jl__download_dest} "${__url}" 
	        echo $1 >> ${jl__downloaded} #Save id to downloaded list.
	fi
    elif [ "${arg__url_type}" = 'track' ]
    then
        local __url="http://www.jamendo.com/get/album/id/track/archiverestricted/redirect/$1/?are=ogg3"
	if [ ${arg__print_download_page_url} = "true" ]
	then
		echo ${__url}
	else
	 	#"${jl__download_app}" "http://www.jamendo.com/get/album/id/track/archiverestricted/redirect/$1/?are=ogg3" > /dev/null 2&>1 &
 		wget --trust-server-names --directory-prefix=${jl__download_dest} "${__url}" 
	fi
    fi
}

#Starts the defined application to open the album page.
# Needs to know whether url is album or track.
# $1 = id
function open_album_page() {
    "${jl__download_app}" "http://www.jamendo.com/de/${arg__url_type}/${1}" > /dev/null 2&>1
}

#Reads an jamendo url and extracts the id.
# Returns id.
function get_id_from_url() { 
    _tmp=$(echo ${2} | egrep -o '(track|album)/[0-9]{1,7}$')
    print $(echo ${_tmp} | cut -d'/' -f2)
}

#Reads a jamendo url and extracts the type (track or album).
# Returns type.
function get_type_from_url() {
    _tmp=$(echo ${2} | egrep -o '(track|album)/[0-9]{1,7}$')
    print $(echo ${_tmp} | cut -d'/' -f1)
}

function main() {
    if [ ! -d "${jl__workdir}" ]; then
	mkdir -p "${jl__workdir}"
    fi

#Alway needed args/vars:
    if [ "${arg__debug}" = "true" ]; then
	set -x
    fi

    if [ ! -z "${arg__suffix}" ]; then
        echo "Using suffix: ${arg__suffix##_}"
    fi

    if [ -z "${arg__start_id}" ]; then
	arg__start_id=$(print_saved_last_valid_id)
    else
	#_start_id=$(print_saved_last_valid_id)
	echo "arg__start_id: ${arg__start_id}"
    fi

    if [ ! -z "${arg__url}" ]; then
	__tmp_inf=$(echo ${arg__url} | egrep -o '(track|album)/[0-9]{1,7}$')  #danach haben wir album/id oder /track/id
	arg__url_type=$(echo ${__tmp_inf} | cut -d'/' -f1) #can be track or album
	arg__start_id=$(echo ${__tmp_inf} | cut -d'/' -f2)
    fi

    if [ "${arg__print_suffixes}" = "true" ]; then
	print_suffixes
	exit 0
    fi

    if [ "${arg__printm3uurl}" = "true" ]; then
	get_m3u_url_from_id ${arg__start_id}
	exit 0
    fi

    if [ "${arg__print_saved_last_valid_id}" = "true" ]; then
	print_saved_last_valid_id
	exit 0
    fi


# All what starts external commands, to the end...
    if [ "${arg__loadm3uinto}" = "true" ]; then
	download_m3u ${arg__start_id}
	load_m3u_to_player "${arg__mediaplayer}"
	exit 0
    fi

    if [ "${arg__searchnextid}" = "true" ]; then
	search_next_jid ${arg__start_id} #Search from given or last valid id.
#	print_saved_last_valid_id

	if [ "${arg__searchnextloadmedia}" = "true" ]; then
	  download_m3u ${jl__next_id} #Then add the found new valid id to the player.
	  load_m3u_to_player "${arg__mediaplayer}"
	fi

	exit 0
    fi

    if [ "${arg__open_albumpage}" = "true" ]; then
	open_album_page "${arg__start_id}"
	exit 0
    fi

    if [ "${arg__download}" = "true" ]; then
	open_download_page "${arg__start_id}"
	exit 0
    fi
}

function parse_options()
{
    if [ ! "$#" -gt "0" ]; then
        help
        exit 0
    fi
    
    #Default settings
    #arg_start_id=$(print_saved_last_valid_id)

    while [ "$#" -gt "0" ]; do
        case ${1} in
            -plv|--print-last-valid)
		arg__print_saved_last_valid_id="true"
		shift
                ;;
            -i|-id|--id) #Uses this as the _start_id.
		arg__start_id="${2}"
                shift 2
                ;;
	    -url|--url) #Anstatt id kann man auch die ganze url verwenden
		arg__url="${2}"
		shift 2
		;;
            -lm |--loadm3uinto ) #Load the album m3u to the given player.
                arg__loadm3uinto="true"
		arg__mediaplayer="${2}"
                shift 2
                ;;
	    -sx|--suffix)
		arg__suffix="_${2}"
		shift 2
		;;
            -3|--printm3uurl)
		arg__printm3uurl="true"
		shift
                ;;
            -sn|--searchnextid) #The new found id will be stored in ~/.lvurl automatically when using this.
		arg__searchnextid="true"
                shift
                ;;
	    -snlm) #Search next ID and load according m3u file to player $2.
		arg__searchnextid="true"
		arg__searchnextloadmedia="true"
		arg__mediaplayer="${2}"
                shift 2
		;;
            -d|-download)
		arg__download="true"
                shift 
                ;;
	    -pd|--print-download-page-url)
		arg__download="true"
		arg__print_download_page_url="true"
                shift 
                ;;
            -o|--open-album-page)
		arg__open_albumpage="true"
                shift
                ;;
	    -ps|--print-suffixes)
		arg__print_suffixes="true"
		shift
		;;
            -v|--verbose)
		arg__verbose="true"
                shift
                ;;
	    -de|-debug|--debug)
		arg__debug="true"
		shift
		;;
            --help|-h|*)
		help
		exit 0
		;;
	esac
    done
}

parse_options "${@}"

main
