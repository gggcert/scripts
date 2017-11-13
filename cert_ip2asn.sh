#!/bin/bash
#
# cert_ip2asn.sh
# OWNER: Gilad Finkelstein
# VER:   0.6 20171031
#
# 0.2   20171113        
#		support differents services to get simillar as2ip info
# 0.1   20171031        
#		use ip2asn service to generate a csv output list 
#----------------------------------------------------------------------
# retrive file only:
# git clone  https://github.com/gggcert/scripts.git .
#-------------------------------------------------------------------------
json2csv=$(which json2csv 2>/dev/null)
if [ -z "$json2csv" ] ; then 
	#get required json2csv code 
	gitFile=https://github.com/jehiah/json2csv/releases/download/v.1.2.0/json2csv-1.2.0.linux-amd64.go1.8.tar.gz
	curl -L $gitFile  |tar xvz --strip=1 && mv json2csv /usr/local/bin/
	json2csv=/usr/local/bin/json2csv
fi 
#ip=132.70.196.53
 
#lets have some color in life
RESET=`tput sgr0`                         # normal text $'\e[0m'
BOLD=$(tput bold)                         # make colors bold/bright
RED="$BOLD$(tput setaf 1)"                # bright red text
GREEN=$(tput setaf 2)                     # dim green text
fawn=$(tput setaf 3); beige="$fawn"       # dark yellow text
YELLOW="$BOLD$fawn"                       # bright yellow text
DARKBLUE=$(tput setaf 4)                  # dim blue text
BLUE="$BOLD$DARKBLUE"                     # bright blue text
purple=$(tput setaf 5); MAGENTA="$purple" # magenta text
pink="$BOLD$purple"                       # bright magenta text
darkcyan=$(tput setaf 6)                  # dim cyan text
CYAN="$BOLD$darkcyan"                     # bright cyan text
GRAY=$(tput setaf 7)                      # dim white text
DARKGRAY="$BOLD"$(tput setaf 0)           # bold black = dark gray text
WHITE="$BOLD$GRAY"                        # bright white text
BLACK=`tput setaf 0`

csvFields=announced,as_country_code,as_description,as_number,ip
defService=as2ip #default serverice as2ip (other options are cymru using dig and he using scraping of IL only db )
ipList=''
ipArg=''
# Call getopt to validate the provided input.
options=$(getopt -o hvk:s: --longoptions  help,ip:,service:,version -- "$@")
[ $? -eq 0 ] || {
	echo "Incorrect options provided [$options]"
	exit 1
}
eval set -- "$options"
while true; do
	case "$1" in
	-h|--help)
		echo -e ${WHITE}"Usage: $0  [OPTIONS] "${RESET}
		echo -e ${WHITE}"OPTIONS"${RESET}
		echo -e ${WHITE}"	--ip	comma seperated list of ip's or a file that contains lines of ips" ${RESET}
		echo -e ${WHITE}"	-k	csv fields output{default:$csvFields}" ${RESET}
		echo -e ${WHITE}"	--service	as2ip|cymru|he {default:$defService}" ${RESET}
		echo -e ${WHITE}"	--help			show this help" ${RESET}
		echo -e ${WHITE}"	--version		show version" ${RESET}
		echo -e ${WHITE}"EXAMPLE"${RESET}
		echo -e ${WHITE}" $0 --ip 132.70.196.53,8.8.8.8  "${RESET}
		exit 0
		;;
	--ip)
		shift; # The arg is next in position args
		ipArg=$1
		if [ -f "$ipArg" ] ;then
			ipList=$(cat "$ipArg"|tr -d '\r' |xargs)
		else
			ipList=${ipArg//,/ } #convert list of comma seperated ips to a space delimited list 
		fi
		;;
	--service | -s )
		shift; # The arg is next in position args
		if [[ "$1" =~ ^(as2ip|cymru|he)$ ]]; then
			defService=$1
		else
			echo "Sorry we do not have such service avilable [$1], try again"
			$0 --help
		fi
		;;
	-k)
		shift; # The arg is next in position args
		csvFields=$1
		;;
	-v|--version)
        echo -e "$0 \nVersion: "${YELLOW}$(grep '^# VER:' $0|awk '{print $3,$4}')${RESET}
		exit 0
		;;
	--)
		shift
		break
		;;
	esac
	shift
done
#[ -z "$ipList" ] && echo -e ${WHITE}"--ip must be provided "${RESET} && exit 1
# TODO use the same service tsv file data set that contains all records and find if a given ip is within a range of a line
#https://iptoasn.com/data/ip2asn-combined.tsv.gz
if [ $defService == "as2ip" ] ; then 
	serviceUrl=https://api.iptoasn.com/v1/as/ip  
	for ip in $ipList ;do
		curl -Ls $serviceUrl/$ip | $json2csv -k $csvFields
	done
elif [ $defService == "he" ] ; then 
	#execute the python code if exists
	$(dirname $0)/cert_ip2asn.py --ip $ipArg
elif [ $defService == "cymru" ] ; then 
	#try using the 
	serviceUrl=origin.asn.cymru.com
	#see if .cache_ip2asn file exist it contains some AS to name mapping we can use 
	cacheFile=$(dirname $0)/.cache_ip2asn
	[ -f $cacheFile ] && echo "grep AS in the file "
	for ip in $ipList ;do
		rIp=$(echo "$ip"|tr '.' '\n'|tac|tr '\n' '.')
		dig +short $rIp$serviceUrl TXT | sed "s/^\"/\"$ip\| /g"   #add the ip to the begining of each replay line
	done
	#set +x
fi
#echo ${RESET}
