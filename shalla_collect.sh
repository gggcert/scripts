#!/bin/bash
#
# shalla_collect.sh
# OWNER: Gilad Finkelstein
# VER:   0.5 20170928
# 
# 0.5 	create helper stub for the named.conf on both dns and rpz servers with new zones
#		cp the ready zone files into production
# Collect sbl lists from feed shalla
#----------------------------------------------------------------------
# retrive file only:
# curl -L --retry 20 --retry-delay 2 -O https://raw.githubusercontent.com/gggcert/scripts/master/shalla_collect.sh
# or clone all script repository 
# git clone  https://github.com/gggcert/scripts.git .
#-------------------------------------------------------------------------

rootDir=$HOME/dnsrpz
feedsDir=$rootDir/feeds
feedName=shalla
feedDir=$feedsDir/$feedName/BL
feedLog=$feedsDir/$feedName.log
#subscriber can be any name, it will be used as a container when generating the zone files
#different subscribers may subscribe to different feeds and different actions of the created zone files
subscriber=cert
#where rpz zone files will be stored
zoneDir=$rootDir/zones/$subscriber #$feedName will be part of the zone name (more likely a map of that name to an internal naming convention )
bindRootDir=/var/named # this is the default bind9 root location,run: grep directory /etc/named.conf to find if in other location
#keep ofuscation map between our feed names (internal) and subscribers knoweldge of them (external)
declare -A MAP_ZONE_EXT_NAMES=( ["shalla"]="kuku1" ["surbl"]="kuku2")
#some minimal varibale interactions
if [ $# -eq 1 ] && [ $1 == "--version" ] ;then 
	echo -e "$0 \nVersion: "$(grep '^# VER:' $0|awk '{print $3,$4}')
	exit 0
fi
if [ $# -eq 1 ] && [ $1 == "--help" ] ;then 
	echo -e "$0 [--help][--version]"
	echo -e " Collect $feedName[aka ${MAP_ZONE_EXT_NAMES[$feedName]}] for subscriber $subscriber resulting zone files in $zoneDir"
	exit 0
fi


feedFile=shallalist.tar.gz
feedUrl=http://www.shallalist.de/Downloads/shallalist.tar.gz
#helper tools
tarCmd=$(which tar) || tarCmd=/usr/bin/tar
chownCmd=$(which chown) || chownCmd=/usr/bin/chown
md5Cmd=$(which md5) || md5Cmd=/usr/bin/md5sum
httpget=$(which wget) || httpget=/usr/bin/wget
httpget2=$(which curl) || httpget2=/usr/bin/curl
pid=$$

[ ! -f $tarCmd ] && echo "Could not locate tar." && exit 1
[ ! -f $chownCmd ] && echo "Could not locate chown." && exit 1

########################################## FUNCTIONS

#deploy template if one does not exist yet
function genFile () {
local file=$1
#/home/gilad/dnsrpz/rpz_header_template
cat > $file <<'_EOF'
; zone file generated by CERT@Sun Sep 10 14:55:21 IDT 2017
$TTL 2h ; default TTL 2h
$ORIGIN cert.nodomain.none. ;
; email address is never used
@        SOA nonexistent.nodomain.none. dummy.nodomain.none. 2017091099 12h 15m 3w 2h
; name server is never accessed but out-of-zone
         NS  nonexistant.nodomain.none.

;vACTIONS  NXDOMAIN | NODATA | PASSTHRU | DROP | TCP-Only | Local Data latest darft in https://tools.ietf.org/html/draft-vixie-dns-rpz-04
; *.example.com                 CNAME   .  ; return NXDOMAIN
; example.com                           CNAME   *.  ; return NODATA
; ok.example.com                CNAME   rpz-passthru.
; example.com                           CNAME   rpz-drop.
; example.com                   CNAME   rpz-tcp-only.
; bad1.example.com            CNAME   garden.example.net.
; bad2.example.com            A       garden-web.example.net.
; bad2.example.com            MX      garden-mail.example.net.
; 32.3.2.0.192.rpz-client-ip  A       quarantine.example.net.

;;;;################ Auto generated lists ###############;;;

!!!! ERROR LINE LEFT ON PERPOSE, IF YOU SEE THIS IN A ZONE FILE SOMETHING IS WRONG !!!!
_EOF
}


############################################
workdir="/tmp/$feedName"
#some feeds use different directory structure so lets be flexible here 
feedworkingdir=$workdir
[ $feedName == "shalla" ] && feedworkingdir=$workdir/BL

[ ! -d $workdir ] &&  mkdir -p $workdir
[ ! -d $feedsDir ] && mkdir -p $feedsDir
cd $workdir  #/tmp/shalla/
#implement caching if file is not older tnen X days avoid the need to retrive it from server 
needNewVersion=1
#by default we download new versions of the list but lets see if there is any change first
$httpget2 -o $workdir/$feedFile.md5 $feedUrl.md5
if [ -e $workdir/$feedFile ]; then
    #compare web hash to local existing file
    $md5Cmd --status -c $feedFile.md5

    #if downloaded md5 matches the local file we do not need an update
    [ $? -eq 0 ] && needNewVersion=0 && echo "Nothing to do $feedFile is up to date" #&& exit 2 
fi
 #we know we need to update the black list collection file lets get it
if [ $needNewVersion -eq 1 ]; then
	#remove old file if exists
	[ -f  $workdir/$feedFile ] && echo "Old blacklist archive file found in ${workdir}. Deleted!" && rm $workdir/$feedFile
	#clean up old BL directories 
	[ -d $feedworkingdir ] && echo "Old blacklist directory found in $feedworkingdir. Deleted!" && rm -rf $feedworkingdir
	#fetch bl file
	echo "Fetch fresh BL file from $feedName,stand by"
	$httpget $feedUrl -a $feedLog -O $workdir/$feedFile || { echo "Unable to download $feedFile." && exit 1 ; }
    #Check the status
    $md5Cmd --status -c $feedFile.md5
	#MD5 match?  Then commit.
	if [ $? -eq 0 ]; then
		echo "Unzippping $feedFile"
		$tarCmd xzf $workdir/$feedFile -C $workdir || { echo "Unable to extract $workdir/$feedFile." && exit 1 ; }
	fi
fi
#implement md5 based caching so that we do not reprocess feed files that did not change from last time
# Create diff files for all categories
# Note: There is no reason to use all categories unless this is exactly
#       what you intend to block. Make sure that only the categories you
#       are going publish with rpz are used.
CATEGORIES="adv aggressive spyware"
#CATEGORIES="adv aggressive automobile/cars automobile/bikes automobile/planes automobile/boats chat dating downloads drugs dynamic finance/banking finance/insurance finance/other finance/moneylending finance/realestate forum gamble hacking hobby/cooking hobby/games hobby/pets hospitals imagehosting isp jobsearch models movies music news podcasts politcs porn recreation/humor recreation/sports recreation/travel recreation/wellness redirector religion ringtones science/astronomy science/chemistry searchengines sex/lingerie shopping socialnet spyware tracker updatesites violence warez weapons webmail webphone webradio webtv" 

echo "Creating diff files.while updating the lists with the fresh lists"
# we are doing:
# 1. greb the diff of current vs new domains
# 2. seperate domains into domain only and ips file
for cat in $CATEGORIES ;do
	[ ! -d $feedDir/${cat} ] && mkdir -p $feedDir/${cat}
	if [ -f $feedworkingdir/${cat}/domains ] ;then 
		#filter out ips they will beused in reverse lookup zones
		grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' $feedworkingdir/${cat}/domains >> $feedworkingdir/${cat}/ips
		#now remove them from original domain file
		sed -i  /'[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'/d $feedworkingdir/${cat}/domains 
		
		if [ -f $feedDir/${cat}/domains ]; then
			diff -U 0 $feedDir/${cat}/domains $feedworkingdir/${cat}/domains |grep -v "^---"|grep -v "^+++"|grep -v "^@@" > $feedDir/${cat}/domains.diff
			diff -U 0 $feedDir/${cat}/ips $feedworkingdir/${cat}/ips |grep -v "^---"|grep -v "^+++"|grep -v "^@@" > $feedDir/${cat}/ips.diff
		fi
		cp $feedworkingdir/${cat}/domains $feedworkingdir/${cat}/ips $feedDir/${cat}
	fi
	#this is only relevant for web proxy filters not DNS
	#if [ -f $workdir/BL/${cat}/urls ] ;then 
	#	if  [ -f $feedDir/${cat}/urls ] ; then
	#		diff -ur $feedDir/${cat}/urls $workdir/BL/${cat}/urls > $feedDir/${cat}/urls.diff
	#	fi
	#	cp $workdir/BL/${cat}/urls $feedDir/${cat}
	#fi
done
#we should probably also implement a common categorization between different feeds so everyone understands for a given zone name what it is
declare -A CLASSIFICATION=( ["drugs"]="illegal" ["porn"]="adults" ["remotecontrol"]="backdoors" ["sex/education"]="adults" ["sex/lingerie"]="adults" ["spyware"]="spyware" ["warez"]="illegal" )
#keep track of the zone state build 0-initiate 1-header created ....
declare -A CLASSTYPESTATE=( ["illegal"]=0 ["adults"]=0 ["backdoors"]=0 ["spyware"]=0 ["other"]=0 )
#this is the default tempolate TBD: different subscribers and/or times will require diffrernt default actions maybe even at the zone level
zoneHeader=rpz_header_template
#time to process all this files and create an rpz file to be loaded into the dns -rpz

#make sure the subscriver zone is cretaed and a default template header present
[ ! -d $zoneDir ] && mkdir -p $zoneDir 

#if zone already exist increase its serial and update the triger and actions file resulting a new zone file ready to be consumed
#if zone is new also add a stub entry to both the local dns-rpz master and the various clients 
#there is a limit of 32 rpz zones so we have to combine different classifications together 
TS=$(date)
#set -x
for cat in $CATEGORIES ;do
	class=${CLASSIFICATION[$cat]} # other |illegal |adults |backdoors |spyware
	[ -N $class ]  && class=other
	#only create header once per category class , a class = zone file 
	if [ ${CLASSTYPESTATE[$class]} -eq 0 ] ;then 
		#zone file are created per class if one already exist we will append new data only
		zoneFile=$zoneDir/${MAP_ZONE_EXT_NAMES[$feedName]}_${class}_rpz.db #/root/dnsrpz/zones/cert/kuku1_spyware_rpz.db
		#if file does not exist create it using the template else only update the records and serial 
		serialDate=$(date +%Y%m%d) ##20170910
		if [ ! -f $zoneFile ] ;then 
			serial=${serialDate}00 #2017091000 'allow up to 100 updates a day using last 2 digits
			if [ ! -f $rootDir/$zoneHeader ] ;then 
				echo "missing template file, deploying default"
				genFile $rootDir/$zoneHeader
			#stub regenerate the file from slef using generateFile function
			fi
			cat $rootDir/$zoneHeader |sed "s/CERT@.*/CERT@$TS/g"|sed "s/2017091099/$serial/g" > $zoneFile
			# make sure the ORIGIN matches the zone file name convention which will be used all around
			sed -i 's/^$ORIGIN.*/$ORIGIN'" $subscriber.${MAP_ZONE_EXT_NAMES[$feedName]}.${class}. ;/g" $zoneFile
			#$ORIGIN $subscriber.${MAP_ZONE_EXT_NAMES[$feedName]}.${class}. ;
			
		else
			#update TS header
			sed -i "s/CERT@.*/CERT@$TS/g" $zoneFile
			#get current serial
			currentSerial=$(head -8 $zoneFile |sed -n 's/.*\(20[0-9]\{6\}[0-9]\{2\}\).*/\1/p') # e.g. 2017091000
			currentSerialDate=${currentSerial::-2} # 20170910
			if [ "$currentSerialDate" -eq "$serialDate" ] ;then #same day update
				currentSerialSerial=${currentSerial: -2}
				newSerial=$((10#$currentSerialSerial + 1)) # force decimal representation, increment
				serial="${currentSerialDate}$(printf '%02d' $newSerial )" # format for 2 digits
			else
				serial=${serialDate}00 #2017091000
			fi
			sed -i "s/$currentSerial/$serial/g" $zoneFile
		fi
		CLASSTYPESTATE[$class]=1  #finsihed handling creation/update of the zone header
		#trancate old values if exist following or start line
		sed -i '/^;;;;################ Auto generated lists/q' $zoneFile
	else
		echo "Header for this class[$class] was already created "
	fi
	#time to populate the zone file with some records derived from our feed
	#for the POC we will use for each domain (trigger) an action of CNAME   garden.example.net.
	defaultAction="	CNAME   garden.example.net."
 	echo ";${class}/${cat} generated" >>  $zoneFile
	sed  "s/$/$defaultAction/g" $feedDir/${cat}/domains >>  $zoneFile
	
done
#set -x
validZoneNames=''
for zf in $(ls $zoneDir|grep -v '.conf$') ;do
	echo "checking zone $zoneDir/$zf"
	#go over all created zone files and validate zone file integrity 
	zn=$(grep '^$ORIGIN' $zoneDir/$zf|awk '{print $2}')
	named-checkzone $zn $zoneDir/$zf
	# if check fails move it aside and do not attempt to load it in the next step 
	if [ $? -ne 0 ]  ;then 
		echo "something is bad with the zone please check it manually,file moved to $zoneDir/$zf.bad"  
		mv $zoneDir/$zf $zoneDir/$zf.bad
	else
		validZoneNames+=" $zn"
	fi
done
echo "Processing the feed had finished all valid zone files can be found in $zoneDir/$zf"


#helper code to generate stubs for the dns and rpz named.conf changes
#The dns servers map is only required for helping creat the correct required stub named.conf file for bind users to use. This is Optional only 
declare -A DNS_SERVERS=([cert]=172.17.1.122 [certDev]=172.17.1.122)

myIp=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'|head -1)
#helper conf files to help with configuring both the rpz and the dns itself 
bindConf=$zoneDir/stub_bindConf.conf && rm -rf $bindConf
rpzConf=$zoneDir/stub_rpzConf.conf && rm -rf $rpzConf
#filetr out invalid zone files
for zf in $(ls $zoneDir|grep -v '.bad$'| grep -v '.conf$') ;do
	if [ ! -e $rpzConf ] ;then
		#create the stub headers of the conf files
		echo '//zone name convention is "subscriber_internalFeedName_category" e.g. cert.kuku1.other => cert subscriber for kuku1 feed for unspcificed category (other)' |tee -a $bindConf $rpzConf >/dev/null
		echo 'options {'|tee -a $bindConf $rpzConf >/dev/null		
		echo '...' |tee -a $bindConf $rpzConf >/dev/null
		#e.g. response-policy {zone kuku1_other_rpz.db; zone kuku1_spyware_rpz.db; zone kuku1_spyware_rpz.db.bad2; };
		echo '    response-policy {'$(echo $validZoneNames|tr ' ' '\n'|sed 's/^/zone /g'|sed 's/$/;/g'|xargs)'};' |tee -a $bindConf $rpzConf >/dev/null
		echo '...' |tee -a $bindConf $rpzConf >/dev/null
		echo '}' |tee -a $bindConf $rpzConf >/dev/null
	fi
	#create the stub example for help ${DNS_SERVERS[$subscriber]} for bind server
	zn=$(grep '^$ORIGIN' $zoneDir/$zf|awk '{print $2}')
	echo	'zone "'$zn'"{' |tee -a $bindConf $rpzConf >/dev/null
	#generate the stub for the dns server 
	echo	'    type slave;' >> $bindConf
	echo	'    masters {' $myIp '; };' >> $bindConf
	echo	'    file "slaves/'${subscriber}_${zf}'";' >> $bindConf
	echo	'    allow-query { localhost; };' >> $bindConf
	echo	'    allow-transfer { none; };' >> $bindConf
	echo	'};' >> $bindConf
	#generate the stub for the rpz server 
	echo	'    type master; '>> $rpzConf
	echo	'    file "data/'${subscriber}_${zf}'";' >> $rpzConf
	echo	'    also-notify { '${DNS_SERVERS[$subscriber]}';};' >> $rpzConf
	echo	'    notify yes; '>> $rpzConf
	echo	'    allow-transfer { '${DNS_SERVERS[$subscriber]}';};' >> $rpzConf
	echo	'}; '>> $rpzConf
	
	echo 	''|tee -a $bindConf $rpzConf >/dev/null
	#cp the zone file in place
	echo "Coping new created valid zone file [ $zf] into production [$bindRootDir/data/]"
	#set -x
	cp -rf $zoneDir/$zf $bindRootDir/data/${subscriber}_${zf}
	#set +x
done
echo "stub named.conf changes can be found in $bindConf $rpzConf"
# while we can run the collection and parsing on different server it would make sense to run it directly on the rpz dns, make sure we have it running
[ ! -d $bindRootDir ] && echo "Are you sure we are running on the rpz named(bind) dns server? I failed to find $bindRootDir" && exit 1
# check if new zone exists in /etc/named.conf if not add it to the stub (so someone can manually add it after a review)
# if it does exists cpy the zone to /var/named/data/ 

echo "Zone files updated and should be already synced with DNS server [ check the log in /var/named/data/named.log]"
tail  /var/named/data/named.log



exit 0
