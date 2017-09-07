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

feedFile=shallalist.tar.gz
feedUrl=http://www.shallalist.de/Downloads/shallalist.tar.gz
#helper tools
tarCmd=/usr/bin/tar
chownCmd=/usr/bin/chown
md5Cmd=/usr/bin/md5sum
httpget=/usr/bin/wget
httpget2=/usr/bin/curl

[ ! -f $tarCmd ] && echo "Could not locate tar." && exit 1
[ ! -f $chownCmd ] && echo "Could not locate chown." && exit 1
#dbhome="/usr/local/squidGuard/db"     # like in squidGuard.conf
#squidGuardowner="squid:root"

##########################################

workdir="/tmp/$feedName"
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
	[ -f  $workdir/$feedFile ] && echo "Old blacklist file found in ${workdir}. Deleted!" && rm $workdir/$feedFile
	#clean up old BL directories 
	[ -d $workdir/BL ] && echo "Old blacklist directory found in ${workdir}. Deleted!" && rm -rf $workdir/BL
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
# The "cp" after the "diff" ensures that we keep up to date with our 
# domains and urls files.
for cat in $CATEGORIES ;do
	[ ! -d $feedDir/${cat} ] && mkdir -p $feedDir/${cat}
	if [ -f $workdir/BL/${cat}/domains ] ;then 
		if [ -f $feedDir/${cat}/domains ]; then
			diff -U 0 $feedDir/${cat}/domains $workdir/BL/${cat}/domains |grep -v "^---"|grep -v "^+++"|grep -v "^@@" > $feedDir/${cat}/domains.diff
		fi
		cp $workdir/BL/${cat}/domains $feedDir/${cat}
	fi

	if [ -f $workdir/BL/${cat}/urls ] ;then 
		if  [ -f $feedDir/${cat}/urls ] ; then
			diff -ur $feedDir/${cat}/urls $workdir/BL/${cat}/urls > $feedDir/${cat}/urls.diff
		fi
		cp $workdir/BL/${cat}/urls $feedDir/${cat}
	fi
done

#time to process all this files and create an rpz file to be loaded into the dns -rpz
zoneDir=$rootDir/zones
zoneDir=$zoneDir/$feedName
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
