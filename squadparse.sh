#!/bin/bash
#
# This script parses a set of images extracted from the Game screen
# and performs OCR on them using tesseract-ocr tool.
# 
# It also extracts some nice thumbnails for the characters based on their
# names and saves on the /tmp/heroes/thumbs and /tmp/heroes/shards folders
#
# ALL numbers bellow are magic.

# Global parameters for the OCR tools used
export tess="tesseract stdin stdout -l por -psm 7"

FOLDER="/tmp/swgoh-squad"

# Output directories of thumbs and other output
mkdir -p ${FOLDER}/heroes/{thumbs,shards}

log() {
	if [ x"$DEBUG" != x"" ] ; then
		echo >&2 "[squaddump] $@"
	fi
}

# Print header
echo -e "power\tlevel\tstars\tgear\thealth\tshards1\tshards2\tname"

# Loop over all characters ...
NUMBERS="$(seq 0 74)"
if [ $# -ge 1 ] ; then
	export NUMBERS="$@"
fi
for i in $NUMBERS ; do
	log "Processing character #${i}"
	# Setting up some global constants
	char=`printf "${FOLDER}/character-%02d-char.png" $i`
	stat=`printf "${FOLDER}/character-%02d-stat.png" $i`
	star=`printf "${FOLDER}/character-%02d-star.png" $i`

	if [ ! -f $char ] ; then
		log "Skipping file $char - not found/unreadable ..."
		continue
	fi

	# Parses the character level
	level="$(convert $char -crop 43x39+102+875 - |\
		convert -fuzz 10% -fill red +opaque '#fdfdfd' - png:- | $tess digits)"

	# Parses the character power
	power=$(convert -crop 82x40+1712+173 $char - |\
		convert - -resize 800x600 pnm:- | $tess |\
		sed 's/[^0-9]//g')
	
	# Parses and fixes the character name. This is the hardest part and the parameters
	# bellow produced the best results possible.
	name=$(convert -crop 586x44+348+91 -threshold 60% $stat - |\
			convert - -resize 800x600 pnm:- | $tess)
	name=$( echo "$name" | sed \
			-e 's/Draide/Dróide/g' \
			-e 's/\[IT-/CT-/g' \
			-e 's/IG-I 00/IG-100/g' \
			-e 's/l(on/Kylo/g' \
			-e 's/Fase l/Fase I/g' \
			-e 's/IIS-86/IG-86/g' \
			-e 's/IIS-88/IG-88/g' \
			-e 's/Irã-86/IG-86/g' \
			-e 's/Qui-Bon/Qui-Gon/g' \
			-e 's/Gui-Gun/Qui-Gon/g' \
			-e 's/Motf/Moff/g' \
			-e 's/\[J/D/g' \
			-e 's/ü/Q/g' \
			-e 's/FiStO/Fisto/g' \
			-e 's/Clõnicas/Clônicas/g' \
			-e 's/Suhmundo/Submundo/g' \
			-e 's/Sto rmtrooper/Stormtrooper/g' \
			-e 's/URORR/URoRR/g' )

	# Parses the gear and fixes some weird gear symbols.
	gear="I"
	if [ $level -gt 1 ] ; then
		for color in "#99ff33" "#00bdff" "#9341ff" ; do
			gear="$(convert $char -crop 258x54+675+835 pnm:- |\
					convert -fuzz 10% +opaque "$color" - png:- | $tess)"
			log "Gear OCR result '$gear'"
			gear="$(echo "$gear" | sed -e 's/\\Í/VI/g' -e 's/l/I/g' \
				-e "s/'/ /g" -e 's/[^a-zA-Z]/ /g' | awk '{print $NF}')"
			log "Detected gear: '$gear'"
			gear="$(echo $gear)"
			if [ x"$gear" != x"" ] ; then
				break
			fi
		done	
	else
		gear="I"
	fi
	case $gear in
		I) export gear="1";;
		II) export gear="2";;
		III) export gear="3";;
		IV) export gear="4";;
		V) export gear="5";;
		VI) export gear="6";;
		VII) export gear="7";;
		VIII) export gear="8";;
		IX) export gear="9";;
	esac

	# Fetch star rating. Tricky, but works just fine.
	# 1. We convert the image into black and white, after blurring/sharpenning,
	#	so we have a temp file with white circles.
	convert -crop 218x36+851+209 $char -blur 4x8 pnm:- |\
		convert - -sharpen 0x12 -negate -threshold 15% -negate $star
	# 2. We check the highest pixel that is white,
	#	and identify what is the highest start active.
	starcount=7
	for x in 200 170 140 110 80 50 20 ; do
		pixel=`convert $star -crop 1x1+$x+18 -depth 8 txt:- | tail -n 1 | awk '{print $3}'`
		if [ x"$pixel" = x"#FFFFFF" ] ; then break ; fi
		let starcount--
	done

	# Parses the required and current shard count for the next promotion/activation.
	case $starcount in
		1) export shards=15 ;;
		2) export shards=25 ;;
		3) export shards=30 ;;
		4) export shards=65 ;;
		5) export shards=85 ;;
		6) export shards=100;;
	esac
	_shard_data="$(convert $char -crop  120x45+1700+678 -resize 400x400 - |\
				convert -fill black -fuzz 10% +opaque "#f3f3f5" - png:- |\
				$tess digits)"
	log "_shard_data=${_shard_data}"
	myshards="$(echo $_shard_data | awk '{print $1}')"
	case $starcount in
		0) export shards="$(echo $_shard_data | awk '{print $2}')" ;;
		7) export shards=0 myshards=0 ;;
	esac

	# Parses the character health
	health="$(convert -crop 227x88+626+676 $stat -resize 800x600 - |\
				tesseract stdin stdout -psm 6 | head)"
	health="$(echo "$health" | tr -d '(' | tr -d ')' | bc)"

	# Here we get all stats in CSV format
	printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s (%s)\n" \
		"${power}" "${level}" "${starcount}" "${gear}" "${health}" "${myshards}" "${shards}" "${name}" "${i}"

	# Finally, we crop the character pictures to be able to use them for other pourposes. 
	convert -crop 317x596+802+246 $char "${FOLDER}/heroes/thumbs/${name}.png"
	convert -crop 88x88+1522+742  $char "${FOLDER}/heroes/shards/${name}.png"
done

