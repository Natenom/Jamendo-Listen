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
jl__tmp_m3u=/tmp/jamendo/${$}_jamendo.m3u #Save m3u File to ...
jl__next_id=0
jl__download_app=/usr/bin/chromium
jl__dwl_baseurl="http://www.jamendo.com/de/download/album"
jl__save_last_valid_url=$HOME/.jamendo_listen/lvurl #Save the last valid url to this file.
jl__downloaded=$HOME/.jamendo_listen/jamendo_downloaded
jl__bin_mocp="mocp"
#"/home/apps/moc/bin/mocp"
jl__bin_vlc=$(which vlc)
jl__bin_mplayer=$(which mplayer2)
jl__verbose=0
jl__stop_after_x_fails=200 #Stop after this count of failed IDs. Probably we are at the end of the ID List ... :P
_url_type='album'
jl__download_dest="$HOME/stack/music"
_print_only=0
## DO NOT EDIT BELOW THIS LINE ##

function help() {
cat << EOF
$0

Options
 -h|--help                		This help.
 -v|--verbose				Be verbose (must be the first or second argument).
 -i|--id				Album ID (must be the first argument). ID is always an album ID. For others user -url.
 -url|--url				Instead of Album ID you can use the whole URL (without last /).
 -purl					ONLY PRINT JAMENDO OGG URL
 -s|--savedid			       	Use the last valid id from ${jl__save_last_valid_url} (default behavior).
 -plv|--print-last-valid		Prints the last valid album ID from ${jl__save_last_valid_url} and exit.
 -sn|--searchnextid                     Search for the next valid album ID, store and display it.
 -d|--download-album                    Use app to download current song. (Currently ${jl__download_app}).
					Requesting a download for a track results in the complete album download :)
 -o|--open-album-page			Use app to open the album page. (Currently ${jl__download_app}).
 -lm PLAYER                             Downloads the m3u file of the id and loads it into player X (default is last valid id from ${jl__save_last_valid_url}).
 -snlm PLAYER                           Search next album ID and load album m3u into player X (-sn + -lm X).
                                        PLAYER can be:
                                           m|moc for Music On Console
                                           v|vlc for Video Lan Client
					   mp|mplayer for MPlayer
                                        This is neccessary because every player has different commands to load playlists etc.
 -3|--printm3uurl			Prints m3u URL of given ID (default is last valid id from ${jl__save_last_valid_url}).
 -lvf					Use given file to store last valid id instead of default ${jl__save_last_valid_url}.
					Must be the first argument.

Note: The last valid ID will only be written to ${jl__save_last_valid_url} when using -sn or -snlm with any other option.
EOF
}

#Get a download link for m3u file to the according id.
# $1 - Album ID
function get_m3u_url_from_id() {
    if [ "${_url_type}" == "album" ]
    then
    	#echo "http://api.jamendo.com/get2/stream/track/plain/?album_id=${1}&order=numalbum_asc&n=all&streamencoding=ogg2"
	echo "http://api.jamendo.com/get2/stream/track/m3u/?album_id=${1}&order=numalbum_asc&n=all"
    elif [ "${_url_type}" == 'track' ]
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
        if [ "${jl__verbose}" == "1" ];
	then
	    echo "Error: wget exit status $?"
	fi
	exit $?
    fi
}

#Prints saved id in ${jl__save_last_valid_url}.
#No Arguments.
function print_saved_last_valid_id() {
    cat ${jl__save_last_valid_url}
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
	  echo -e "Number of Songs: $(grep '^http://' ${jl__tmp_m3u} | wc -l)"
	  echo -e "AlbumID: ${jl__next_id}\n"
	  echo -e "Playlist: ${jl__tmp_m3u}\n"
          "${jl__bin_mplayer}" -playlist ${jl__tmp_m3u}
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
	    
            echo "${jl__next_id}" > ${jl__save_last_valid_url} #Save last valid url to a file ... zur Sicherheit.
	    echo "${jl__next_id} at $(date)" >> "${jl__save_last_valid_url}_history"
	else
	    [ "${jl__verbose}" == "1" ] && echo "Album ID \"${_id}\" does not exist."
	fi

        _id=$((${_id}+1))
	_counter=$((${_counter}+1))
	if [ ${_counter} -gt ${jl__stop_after_x_fails} ]; then
	    [ "${jl__verbose}" == "1" ] && echo "No new valid ID for ${jl__stop_after_x_fails} times. Break..."
	    exit 3
	fi
    done
    return 0
}

#Starts application x to open the album download page.
# $1 - Album ID
function open_download_page() {
#TODO Unterscheidung zwischen Album und Track...
    #"${jl__download_app}" "${jl__dwl_baseurl}/$1/?output=contentonly#" &>/dev/null &
    #"${jl__download_app}" "http://www.jamendo.com/get/album/id/album/archiverestricted/redirect/$1/?are=ogg3" &>/dev/null &

    if [ "${_url_type}" == "album" ]
    then
    	#"${jl__download_app}" "http://www.jamendo.com/get/album/id/album/archiverestricted/redirect/$1/?are=ogg3" > /dev/null 2&>1 &
	#Direktdownload funktioniert nun...
	local __url="http://www.jamendo.com/get/album/id/album/archiverestricted/redirect/$1/?are=ogg3"
    	if [ ${_print_only} -eq 1 ]
	then
		echo ${__url}
	else
		wget --trust-server-names --directory-prefix=${jl__download_dest} "${__url}" 
	        echo $1 >> ${jl__downloaded} #Save id to downloaded list.
	fi
    elif [ "${_url_type}" == 'track' ]
    then
        local __url="http://www.jamendo.com/get/album/id/track/archiverestricted/redirect/$1/?are=ogg3"
	if [ ${_print_only} -eq 1 ]
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
    "${jl__download_app}" "http://www.jamendo.com/de/${_url_type}/${1}" > /dev/null 2&>1
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

function parse_options()
{
    if [ ! "$#" -gt "0" ]; then
        help
        exit 0
    fi
    
    #Default settings
    _start_id=$(print_saved_last_valid_id)

    while [ "$#" -gt "0" ]; do
        case ${1} in
            -s|--savedid) #Use saved id in ${jl__save_last_valid_url} (default behavior)
		_start_id="$(cat ${jl__save_last_valid_url})"
		shift
		;;
	    -lvf) #Use another file to store last valid url
		jl__save_last_valid_url="${2}"
		_start_id=$(print_saved_last_valid_id) #Reread last id from given file.
		shift 2
		;;
            -plv|--print-last-valid)
                print_saved_last_valid_id
		read __a #Wait until ...
		exit 0
                ;;
            -i|-id|--id) #Uses this as the _start_id.
                _start_id=${2}
                shift 2
                ;;
	    -purl) #if using url print only, do nothing
	        _print_only=1
		shift
		;;
	    -url|--url) #Anstatt id kann man auch die ganze url verwenden
	    	 	#check whether this is an album id or an track id

		__tmp_inf=$(echo ${2} | egrep -o '(track|album)/[0-9]{1,7}$')  #danach haben wir album/id oder /track/id
		_url_type=$(echo ${__tmp_inf} | cut -d'/' -f1) #can be track or album
	        _start_id=$(echo ${__tmp_inf} | cut -d'/' -f2)
		shift 2
		;;
            -lm |--loadm3uinto ) #Load the album m3u to the given player.
		download_m3u ${_start_id}
                load_m3u_to_player ${2}
                shift 2
                ;;
            -3|--printm3uurl)
                get_m3u_url_from_id ${_start_id}
		exit 0
                ;;
            -sn|--searchnextid) #The new found id will be stored in ~/.lvurl automatically when using this.
                search_next_jid ${_start_id}
		print_saved_last_valid_id
                shift
                ;;
	    -snlm) #Search next ID and load according m3u file to player $2.
                search_next_jid ${_start_id} #Search from given or last valid id.
		download_m3u ${jl__next_id} #Then add the found new valid id to the player.
                load_m3u_to_player ${2}
                shift 2
		;;
            -d|--open-download-page)
#	        __tmp_inf=$(echo ${2} | egrep -o '(track|album)/[0-9]{1,7}$')
#	        _url_type=$(echo ${__tmp_inf} | cut -d'/' -f1) #can be track or album
#		_start_id=$(echo ${__tmp_inf} | cut -d'/' -f2)

                open_download_page "${_start_id}"
                shift 
                ;;
            -o|--open-album-page)
                open_album_page ${_start_id}
                shift
                ;;
            -v|--verbose)
                jl__verbose=1
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
