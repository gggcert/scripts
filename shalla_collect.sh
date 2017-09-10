#!/bin/bash
#
# shalla_collect.sh
# OWNER: Gilad Finkelstein
# VER:   0.1 20170907
# 
# Collect sbl lists from feed shalla

rootDir=/root/dnsrpz
feedsDir=$rootDir/feeds
feedName=shalla
feedDir=$feedsDir/$feedName/BL
feedLog=$feedsDir/$feedName.log
#subscriber can be any name, it will be used as a container when generating the zone files
#different subscribers may subscribe to different feeds and different actions of the created zone files
subscriber=cert

feedFile=shallalist.tar.gz
feedUrl=http://www.shallalist.de/Downloads/shallalist.tar.gz
#helper tools
tarCmd=/usr/bin/tar
chownCmd=/usr/bin/chown
md5Cmd=/usr/bin/md5sum
httpget=/usr/bin/wget
httpget2=/usr/bin/curl
pid=$$

[ ! -f $tarCmd ] && echo "Could not locate tar." && exit 1
[ ! -f $chownCmd ] && echo "Could not locate chown." && exit 1
#dbhome="/usr/local/squidGuard/db"     # like in squidGuard.conf
#squidGuardowner="squid:root"

##########################################

workdir="/tmp/$feedName"
#some feeds use different directory structure so lets be flexible here 
feedworkingdir=$workdir
[ $feedName == "shalla" ] && feedworkingdir=$workdir/BL

[ ! -d $workdir ] &&  mkdir -p $workdir
cd $workdir  #/tmp/shalla/
#implement caching if file is not older tnen X days avoid the need to retrive it from server 
needNewVersion=1
#by default we download new versions of the list but lets see if there is any change first
$httpget2 -o $workdir/$feedFile.md5 $feedUrl.md5
if [ -e $workdir/$feedFile ]; then
    #compare web hash to local existing file
    $md5Cmd --status -c $feedFile.md5

    #if downloaded md5 matches the local file we do not need an update
    [ $? -eq 0 ] && needNewVersion=0
fi
 #we know we need to update the black list collection file lets get it
if [ $needNewVersion -eq 1 ]; then
	#remove old file if exists
	[ -f  $workdir/$feedFile ] && echo "Old blacklist archive file found in ${workdir}. Deleted!" && rm $workdir/$feedFile
	#clean up old BL directories 
	[ -d $feedworkingdir ] && echo "Old blacklist directory found in $feedworkingdir. Deleted!" && rm -rf $feedworkingdir
	#fetch bl file
	$httpget $feedUrl -a $feedLog -O $workdir/$feedFile || { echo "Unable to download $feedFile." && exit 1 ; }
    #Check the status
    $md5Cmd --status -c $feedFile.md5
	#MD5 match?  Then commit.
	if [ $? -eq 0 ]; then
		echo "Unzippping $feedFile"
		$tarCmd xzf $workdir/$feedFile -C $workdir || { echo "Unable to extract $workdir/$feedFile." && exit 1 ; }
	fi
fi

# Create diff files for all categories
# Note: There is no reason to use all categories unless this is exactly
#       what you intend to block. Make sure that only the categories you
#       are going publish with rpz are used.
CATEGORIES="adv"
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
#keep ofuscation map between our feed names (internal) and subscribers knoweldge of them (external)
declare -A MAP_ZONE_EXT_NAMES=( ["shalla"]="kuku1" ["surbl"]="kuku2")
#we should probably also implement a common categorization between different feeds so everyone understands for a given zone name what it is
declare -A CLASSIFICATION=( ["drugs"]="illegal" ["porn"]="adults" ["remotecontrol"]="backdoors" ["sex/education"]="adults" ["sex/lingerie"]="adults" ["spyware"]="spyware" ["warez"]="illegal" )

#time to process all this files and create an rpz file to be loaded into the dns -rpz
zoneDir=$rootDir/zones/$subscriber #$feedName will be part of the zone name (more likely a map of that name to an internal naming convention )
#this is the default tempolate TBD: different subscribers and/or times will require diffrernt default actions maybe even at the zone level
zoneHeader=rpz_header_template.zone
#make sure the subscriver zone is cretaed and a default template header present
[ ! -d $zoneDir ] && mkdir -p $zoneDir 

#if zone already exist increase its serial and update the triger and actions file resulting a new zone file ready to be consumed
#if zone is new also add a stub entry to both the local dns-rpz master and the various clients 
#there is a limit of 32 rpz zones so we have to combine different classifications together 
TS=$(date)
zoneHeaderUpdated=0  #only update the zone header once per class
for cat in $CATEGORIES ;do
	class=${CLASSIFICATION[$cat]} # none |illegal |adults |backdoors |spyware
	[ -N $class ]  && class=none
	#zone file are created per class if one already exist we will append new data only
	zoneFile=$zoneDir/${MAP_ZONE_EXT_NAMES[$feedName]}_${class}_rpz.db #/root/dnsrpz/zones/cert/kuku1_spyware_rpz.db
	#if file does not exist create it using the template else only update the records and serial 
	serialDate=$(date +%Y%m%d) ##20170910
	if [ ! -f $zoneFile ] ;then 
		serial=${serialDate}000 #20170910000  allow up to 1000 updates a day using last 3 digits
		cat $rootDir/$zoneHeader |sed "s/CERT@.*/CERT@$TS/g"|sed "s/20170910999/$serial/g" > $zoneFile
		zoneHeaderUpdated=1
	else
		#update TS header
		sed -i "s/CERT@.*/CERT@$TS/g" $zoneFile
		#get current serial
		currentSerial=$(head -8 $zoneFile |sed -n 's/.*\(20[0-9]\{6\}[0-9]\{3\}\).*/\1/p') # e.g. 20170910000
		currentSerialDate=${currentSerial::-3} # 20170910
		if [ "$currentSerialDate" -eq "$serialDate" ] ;then #same day update
			currentSerialSerial=${currentSerial: -3}
			newSerial=$((10#$currentSerialSerial + 1)) # force decimal representation, increment
			serial="${currentSerialDate}$(printf '%03d' $newSerial )" # format for 3 digits
		else
			serial=${serialDate}000 #20170910000
		fi
		sed -i "s/$currentSerial/$serial/g" $zoneFile
	fi
	
	#time to populate the zone file with some records derived from our feed
	
	#trancate old values if exist following or start line
	sed -i '/^;;;;################ Auto generated lists/q' $zoneFile
	
	# $feedDir/${cat}/[domains|ips]
	
done
#for each domain file use a template to create required zone file 
#increase the serial number of that zone file by 1 
#place it in the dns-rpz zone directory and reload dnz-rpz (triggering a notification to all subscribers)
# echo "Setting file permisions."
# $chownpath -R $squidGuardowner $dbhome
# chmod 755 $dbhome
# cd $dbhome
# find . -type f -exec chmod 644 {} \;
# find . -type d -exec chmod 755 {} \;

# echo "Updating squid db files with diffs."
# $squidGuardpath -u all

# echo "Reconfiguring squid."
# $squidpath -k reconfigure


exit 0
