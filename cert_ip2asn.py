#!/usr/bin/python
# OWNER: Gilad Finkelstein
# VER:   0.2 20171105
#
# 0.2   20171105
#		Support caching such that any processed ASN is not scarped again
#		If you want to start the process anew delete the .cahe_ip2asn file
#		unicode is a mess when writing to file so replace any none ascii char with ? 
# 0.1   20171104        
#		scrap bgp.he.net for all IL ASN' for each scrap its network IP's 
#		resulting csv table of ASN,Name,Prefix,Description values
#----------------------------------------------------------------------
# installed required python module
#curl "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py"  && python get-pip.py
#pip install beautifulsoup4
#apt-get install qt5-default libqt5webkit5-dev build-essential python-lxml python-pip xvfb
#pip install dryscrape
#pip install netaddr
####################################
import urllib2
import sys,getopt
from bs4 import BeautifulSoup
import dryscrape
import time
import datetime
import os.path
import re,csv
dbRaedy=False # =by default assume no db exist so go scrape it
from netaddr import IPNetwork, IPAddress  #use this to find out if an ip is part of anetwork
#if IPAddress("192.168.0.1") in IPNetwork("192.168.0.0/24"):
print "## Started " + str(datetime.datetime.now())
url = "https://bgp.he.net/"
hdr = {'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.11 (KHTML, like Gecko) Chrome/23.0.1271.64 Safari/537.11',
       'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
       'Accept-Charset': 'ISO-8859-1,utf-8;q=0.7,*;q=0.3',
       'Accept-Encoding': 'none',
       'Accept-Language': 'en-US,en;q=0.8',
       'Connection': 'keep-alive'}

cacheFile='.cache_ip2asn'
asnCacheList=[]
if os.path.isfile(cacheFile):
	print "check cache file"+cacheFile
	f=open(cacheFile, 'r')
	asnCacheList = f.readlines()
	if any('##Finished' in w for w in asnCacheList):
		print "Cache file is up-to-date: " + asnCacheList[-1]
		f.close()
		dbRaedy=True
	else:
		# a cache file contains result data when ASN is done  comment line appears with that ASN to indicated finished 
		asnCacheList=[i.strip() for i in asnCacheList if '## Done' in i]
		#print asnCacheList
		f=open(cacheFile, 'a')
else:
	f=open(cacheFile, 'w')
	f.write('####' + str(datetime.datetime.now())+'\n')
	
#### main code here 
ips = ''
format = ''
def main(argv):
	global ips,format
	try:
		opts, args = getopt.getopt(argv,"hvd:",["ip=","help"])
		#print opts,args
	except getopt.GetoptError:
		print 'test.py [-h] --ip {list op ips}|file '
		sys.exit(2)
	for opt, arg in opts:
		if opt in ('-h','--help'):
			print sys.argv[0]+' --ip {list op ips}|file'
			print 'e.g. '
			print sys.argv[0]+' --ip 132.70.61.50,8.8.8.8'
			sys.exit()
		if opt in ( "--ip"):
			ips = arg
			#if arg is a file read its content each line is an ip
			if os.path.isfile(ips):
				f1=open(ips, 'r')
				ips = f1.readlines()
				#remove any comments
				ips=[i.strip() for i in ips if not i.startswith("#")]
				#list-> comma seprated string
				ips=",".join(str(x) for x in ips)
				f1.close()

if __name__ == "__main__":
   main(sys.argv[1:])
if dbRaedy:
	#keep in memory a list of AS1234, records and get ride of all the rest
	asnCacheList=[i.strip() for i in asnCacheList if re.match('^AS\d*,',i)]
	for ip in ips.split(','):
		#print ip
		found=False
		for row in csv.reader(asnCacheList):
			net=row[2]
			#lookup the ip in net
			if IPAddress(ip) in IPNetwork(net):
				print ip.ljust(15) +"-->," + ",".join(str(x) for x in row)
				found=True
				break
		if not found:
			print ip.ljust(15)  +"-->,Not Found"

	sys.exit(0)
#### handle creating the requires ip2asn db 	
	
try:
	req = urllib2.Request(url+'country/IL', headers=hdr)
	page = urllib2.urlopen(req)
except Exception, e:
	print e
	sys.exit(0)
soup = BeautifulSoup(page, 'html.parser')
table = soup.find("table",id="asns")
rows = table.find_all('tr')
#start X11 server once
dryscrape.start_xvfb()
i=0
printHeader=True  # will print header once which is good for csv output
for tr in rows:
	i+=1
	if i==1:   #first line in a table is the header not record
		cols = tr.find_all('th')
	else:
		cols = tr.find_all('td')

	#print cols
	#get rid of the html tags
	cols = [ele.text.strip() for ele in cols]
	AS = cols[0]
	NAME = cols[1].replace(',',' ') #its vital we do not find any comma as we will be generating csv output
	#if i == 4:
	#	break
	if i == 1:
		H1=AS
		H2=NAME
		continue
	#lets greb the next pages one by one and get the values from them 
	#print AS, NAME
	V4ROUTES=cols[3]
	if V4ROUTES == '0':
		print "Skip "+AS +" It has no v4 address to look after "
		continue
	
	#urllib2 can not scrape JS rendered sites !!!
	#https://bgp.he.net/AS8551#_prefixes
	print "##["+str(i)+"]parsing " + url+AS+'#_prefixes' + '[' + AS + ' ' + NAME + ']'
	#use cach to avoid fathcing records we already have
	#find if any A appears in our sub list 
	if any(AS in w for w in asnCacheList):
		print "Skip "+AS +" Its already in cache"
		printHeader=False  # header is already placed in this file :-)
		continue
	try:
		sess = dryscrape.Session()
		sess.set_attribute('auto_load_images', False)
		print "lets webkit visit " +url+AS+'#_prefixes'
		sess.visit(url+AS+'#_prefixes')
		time.sleep(4)
		source = sess.body()
	except Exception, e:
		print e
		sys.exit(0)
	soupAS = BeautifulSoup(source,'html.parser')
	#print soupAS
	tableAS = soupAS.find("table",id="table_prefixes4")
	#print tableAS
	##################
	rowsAS = tableAS.find_all('tr')
	j=0
	for trAS in rowsAS:
		j+=1
		if j==1:   #first line in a table is the header not record
			colsAS = trAS.find_all('th')
		else:
			colsAS = trAS.find_all('td')
		#print cols
		#get rid of the html tags
		colsAS = [ele.text.strip() for ele in colsAS]
		DESC=colsAS[1].replace(',',' ') #its vital we do not find any comma as we will be generating csv output
		NET=colsAS[0]
		#if j == 3:
		#	break
		if j == 1:
			H3=NET
			H4=DESC
			if printHeader:
				print H1+','+H2+','+H3+','+H4
				f.write(H1+','+H2+','+H3+','+H4+'\n') #does not cover case where first list is not complete, it would be easier to just delete the all cache file 
				printHeader=False
			continue
		print AS +','+ NAME+','+NET+','+ DESC
		#stupid unicode mess forces us to replace any special unicode with ?
		f.write(AS +','+ NAME+','+NET+','+ DESC.encode('ascii','replace').decode()+'\n')
	#put the AS in a cache/log file so we can avoid rerunning it should an eror accure
	f.write('##'+ AS+ '## Done\n')
print "##Finished " + str(datetime.datetime.now())
f.write('##Finished ' + str(datetime.datetime.now())+'\n')
f.close()
