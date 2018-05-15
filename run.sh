#!/bin/bash

# https://github.com/deepwn/GitPageHijack
# code by evil7@deepwn at 2018-5-13
#
# usage:
# run into local > `git clone https://github.com/deepwn/GitPageHijack && cd GitPageHijack.git && bash run.sh`
# run from remote > `curl -sL 'https://raw.githubusercontent.com/deepwn/GitPageHijack/run.sh' | bash`
#
# This POC will searching commits about 'Create CNAME' info since last some day to now.
# And checked if CNMAE file exist.
# And checking if DNS has some bad subdomain setting
# So get the domains and check it with DNS who's point all subdomain to github page servers. Then walaa~!
# The vulnerables found will output to file like `./gitpage_hijack_2018-5-13/report.txt`
# Have fun ~ :)

function start() {
	search="Create CNAME" # Searching words
	lmt_day=1             # Limit from some days befor
	retry=10              # How many times can retry
	init_th=10            # Nmbers of threads
	init_ck=""            # use 1 to input cookie after run (not support in remote)
	day=$(date +%Y-%m-%d) # Get date (default, no need change)

	# ^ Setting stopped here ^
	banner
	if [[ $init_ck == 1 ]]; then
		echo
		echo "# Please input your github's cookie:"
		read init_ck
	fi
	if [[ -e "gitpage_hijack_$day/report.txt" ]]; then
		echo
		echo "# Report already got ..."
		echo "# $(pwd)/gitpage_hijack_$day/report.txt"
		echo
	else
		mkdir gitpage_hijack_$day 2>/dev/null
		rm -rf /tmp/gitPage.*.txt 2>/dev/null
		rm -rf /tmp/hijack.temp.swp 2>/dev/null
		th_fix
		getPage
		getDomain
		getHijack
		cleanup
	fi
}

function th_fix() { # temp changed to pid_max fix threads error. Others VPS Linux not MacOS
	fix_sys=$(uname)
	if [[ $fix_sys != "Darwin" ]]; then
		echo "# Checking and fix system problem ..."
		f_swp=$(free -g | grep '^Swap' | awk -F ' ' '{print $4}' 2>/dev/null)
		h_swp=$(free -h | grep '^Swap' | awk -F ' ' '{print $4}' 2>/dev/null)
		f_hd=$(df -h | grep '\/$' | awk -F ' ' '{print $4 $6}' | sed 's/G.*//g' 2>/dev/null)
		fix_type=$(uname -a | grep 'x86_64')
		if [[ -e "/proc/sys/kernel/pid_max" ]] && [[ $(cat /tmp/pid_max.bak 2>/dev/null) == "" ]]; then
			cat /proc/sys/kernel/pid_max >/tmp/pid_max.bak
			if [[ $fix_type != "" ]] && [[ $(cat /proc/sys/kernel/pid_max) != "4194304" ]]; then
				echo '4194304' >/proc/sys/kernel/pid_max
			elif [[ $fix_type == "" ]] && [[ $(cat /proc/sys/kernel/pid_max) != "32768" ]]; then
				echo '32768' >/proc/sys/kernel/pid_max
			fi
			echo
			echo "# Fixing $(/proc/sys/kernel/pid_max) from $(cat /tmp/pid_max.bak) to $(cat /proc/sys/kernel/pid_max)."
		fi

		if [[ $(($f_mem + $f_swp)) < 6 ]] && [[ $f_hd > 6 ]] || [[ $f_swp == 0 ]]; then
			echo 1 >/proc/sys/vm/drop_caches
			echo
			echo "# Create a new Swap ..."
			dd if=/dev/zero of=/tmp/hijack.temp.swp bs=1024MB count=6 >/dev/null
			mkswap /tmp/hijack.temp.swp
			swapon /tmp/hijack.temp.swp
			c_swp=$(free -h | grep '^Swap' | awk -F ' ' '{print $4}')
			echo
			echo "# Fixing Swap from $h_swp to $c_swp with '/tmp/hijack.temp.swp'"
		fi
	fi
}

function randVar() { # random var to bypass
	init_ua="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_4) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/11.1 Safari/605.1.15\n"
	init_ua+="Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/535.11 (KHTML, like Gecko) Chrome/17.0.963.84 Safari/535.11 LBBROWSER\n"
	init_ua+="Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.1; WOW64; Trident/5.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E)\n"
	init_ua+="Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1; SV1; QQDownload 732; .NET4.0C; .NET4.0E)\n"
	init_ua+="Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.1; WOW64; FireEyes/5.0; SLCC2; .NET CLR 2.0.$RANDOM; .NET CLR 3.5.$RANDOM; .NET CLR 3.0.$RANDOM; Media Center PC 6.0; .NET4.0C; .NET4.0E)\n"
	init_ua+="Mozilla/5.0 (Windows NT 5.1) AppleWebKit/535.11 (KHTML, like Gecko) Chrome/17.0.963.84 Safari/535.11 SE 2.X MetaSr 1.0\n"
	init_ua+="Mozilla/5.0 (X11; U; Linux x86_64; zh-CN; rv:1.9.2.10) Gecko/20100922 Ubuntu/10.10 (maverick) Firefox/3.6.10\n"
	init_rf="https://github.com\n"
	init_rf+="https://github.com/search\n"
	init_rf+="https://github.com/search?utf8=✓&q=$RANDOM&ref=simplesearch\n"
	init_rf+="https://github.com/dashboard/discover\n"
	init_rf+="https://blog.github.com/2018-05-01-github-pages-custom-domains-https/"
	init_rf+="https://github.com/marketplace/free-trials"
	init_rf+="https://developer.github.com/v4/guides/intro-to-graphql/"
	r_tmp=$(($RANDOM % 7 + 1))
	export r_ua=$(echo -e "$init_ua" | sed -n "$r_tmp"p)
	export r_rf=$(echo -e "$init_rf" | sed -n "$r_tmp"p)
	export r_ip=$(($RANDOM % 255)).$(($RANDOM % 255)).$(($RANDOM % 255)).$(($RANDOM % 255))
}

function threadWorker() { # threads used fifofile
	thread_num=$1
	job_num=$2
	todo=$3
	tmp_fifofile="/tmp/$$.fifo"
	mkfifo $tmp_fifofile
	exec 6<>$tmp_fifofile
	rm $tmp_fifofile

	for ((i = 0; i < $thread_num; i++)); do
		echo
	done >&6
	for ((i = 0; i < $job_num; i++)); do
		read -u6
		{
			$todo $(($i + 1))
		} &
		echo >&6
	done
	wait
	exec 6>&-
}

function getPage() { # get links list of search. But Github limit 10link / 1min GET for un-login user so it's slowly get here.
	echo
	echo "# Start hunting the gitPage..."
	echo
	search_url=$(echo -e "$search" | sed 's/ /+/g')
	after_date=$(date -d "-$lmt_day day" +%Y-%m-%d 2>/dev/null)
	if [[ $after_date == "" ]]; then
		after_date=$(date -j -f %s $(($(date +%s) - 86400 * $lmt_day)) +%Y-%m-%d) # MacOS
	fi
	echo "[*] Keywords: $search , after_date: $after_date ."
	echo
	randVar
	init=$(curl -sL "https://github.com/search?utf8=%E2%9C%93&p=1&o=asc&q=$search_url+committer-date%3A%3E$after_date&s=committer-date&type=Commits" -H "Cookie: $init_ck" -H "User-Agent: $r_ua" -H "Referer: $r_rf") # -H "X-Forwarded-For: $r_ip")
	ppp=$(echo -e "$init" | grep "[0-9\,]* commit results" | sed -e 's/<[a-z0-9\/]*>//g' -e 's/[^0-9]//g')
	if [[ $ppp != "" ]]; then
		echo "[*] Get search seccuss. $ppp results found."
		echo
		if [[ $(($ppp % 10)) == 0 ]]; then
			ppp=$(($ppp / 10))
		else
			ppp=$(($ppp / 10 + 1))
		fi
	else
		echo "[!] Can't get page and results. Default set 100 pages."
		echo
		ppp=100
	fi
	echo "* Sending after every 3s for 'un-login' to bypass WAF ..."
	echo "* $ppp pages in list. Will take $(($ppp / 10)) min(s) maybe ..." # take a time guess $(((($ppp * 3) + ($ppp / 10 * 30)) / 60))
	echo
	try=$retry
	for ((i = 1; i <= $ppp; i++)); do
		randVar
		get=$(curl -sL "https://github.com/search?utf8=%E2%9C%93&p=$i&o=asc&q=$search_url+committer-date%3A%3E$after_date&s=committer-date&type=Commits" -H "Cookie: $init_ck" -H "User-Agent: $r_ua" -H "Referer: $r_rf") # -H "X-Forwarded-For: $r_ip")
		done=$(echo -e "$get" | grep '<div id="commit_search_results">')
		page=$(echo -e "$get" | grep -ne "title=\"$search\"" | sed -e 's/.*href=\"/https:\/\/github.com/g' -e 's/\"><em>.*/\/CNAME/g')
		if [[ $page != "" ]] && [[ $done != "" ]]; then
			try=$retry
			echo "[*] Searching on page $i/$ppp ..."
			echo -e "$page" >>/tmp/gitPage.link.txt
		elif [[ $page == "" ]] && [[ $done == "" ]]; then
			if [[ $try > 0 ]]; then
				try=$(($try - 1))
				echo "[!] WAF banned at page $i. Waiting retry-$(($retry - $try)) after 30s ..."
				i=$(($i - 1))
				sleep 27
			else
				echo
				echo "# Retry $retry times all faults. you are be banned."
				exit
			fi
		else
			echo "[*] All done at page $i."
			break
		fi
		sleep 3
	done
}

function getDomain() { # get domain in CNAME file
	th=$init_th
	ln=$(cat /tmp/gitPage.link.txt | wc -l | sed 's/[[:space:]]//g')
	function doGet() {
		d=$(sed -n "$1"p /tmp/gitPage.link.txt 2>/dev/null)
		if [[ $d != "" ]]; then
			dd=$(echo -e "$d" | sed -e 's/https:\/\/github.com\//https:\/\/raw.githubusercontent.com\//g' -e 's/\/commit\//\//g')
			tmp=$(curl -sL -A "$r_ua" -e "$r_rf" "$dd")
			res=$(echo -e "$tmp" | grep '[a-z0-9\-\.]*\.[a-z]*' | sed -e 's/.*:\/\///g' -e 's/\/.*//g' | grep '^[a-z0-9\-\.]*\.[a-z]*$')
			if [[ $tmp != "404: Not Found" ]] && [[ $res != "" ]]; then
				echo -e "$res" >>/tmp/gitPage.domain.txt
				echo -e "[*] Get domain $1/$ln done."
			else
				echo -e "[!] Get domain $1/$ln fault."
			fi
		fi
	}
	threadWorker $th $ln doGet
	done=$(cat /tmp/gitPage.domain.txt | sort | uniq)
	echo -e "$done" >/tmp/gitPage.domain.txt
}

function getHijack() { # check DNS if point to Github Pages servers
	all=$(cat /tmp/gitPage.domain.txt | wc -l | sed 's/\ //g')
	echo
	echo "# In $all domains this is vulnerable ..."
	echo
	function doGet() {
		h=$(sed -n "$1"p /tmp/gitPage.domain.txt 2>/dev/null)
		if [[ $h != "" ]] && [[ $(echo -e "$h" | sed 's/.*\.github\.io$//g') != "" ]]; then
			res=$(dig +short hijack_test.$h)
			if [[ $(echo -e "$res" | grep -E '192.30.252.15(3|4)') != "" ]] || [[ $(echo -e "$res" | grep -E '207.97.227.245|204.232.175.78') != "" ]] || [[ $(echo -e "$res" | grep -E '185.199.(10[89]|11[01]).153') != "" ]]; then
				echo "[*] $h - vulnerable"
				echo -e "$h" >>/tmp/gitPage.hijack.txt
				echo
			fi
		fi
	}
	threadWorker $th $all doGet
	done=$(cat /tmp/gitPage.hijack.txt | sort | uniq)
	echo -e "$done" >/tmp/gitPage.hijack.txt
	vuln=$(cat /tmp/gitPage.hijack.txt | wc -l | sed 's/\ //g')
	cat /tmp/gitPage.domain.txt >gitpage_hijack_$day/all_domain.txt
	cat /tmp/gitPage.hijack.txt >gitpage_hijack_$day/report.txt
	echo "# Found $vuln vulnerables. Hunting all done."
	echo
	echo "# Report saved at: $(pwd)/gitpage_hijack_$day/report.txt"
	echo
}

function banner() { # banner it for fun :)
	bnr="ICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgIG1tbW0gICAgICAjIyAgICAgICAgICAgICAgIG1tbW1tbSAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAjIyIiIiIjICAgICAiIiAgICAgICAjIyAgICAgICMjIiIiIiNtICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICMjICAgICAgICAgIyMjIyAgICAgIyMjIyMjIyAgICMjICAgICMjICAgbSMjIyMjbSAgIG0jIyNtIyMgICBtIyMjI20gICAgICAgICAgICAKICMjICBtbW1tICAgICAjIyAgICAgICAjIyAgICAgICMjIyMjIyIgICAgIiBtbW0jIyAgIyMiICAiIyMgICMjbW1tbSMjICAgICAgICAgICAKICMjICAiIiMjICAgICAjIyAgICAgICAjIyAgICAgICMjICAgICAgICBtIyMiIiIjIyAgIyMgICAgIyMgICMjIiIiIiIiICAgICAgICAgICAKICAjI21tbSMjICBtbW0jI21tbSAgICAjI21tbSAgICMjICAgICAgICAjI21tbSMjIyAgIiMjbW0jIyMgICIjI21tbW0jICAgICAgICAgICAKICAgICIiIiIgICAiIiIiIiIiIiAgICAgIiIiIiAgICIiICAgICAgICAgIiIiIiAiIiAgIG0iIiIgIyMgICAgIiIiIiIgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICIjIyMjIiIgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKIG1tICAgIG1tICAgICAjIyAgICAgICAgbW1tbW0gICAgICAgICAgICAgICAgICAgICAgbW0gICAgICAgICAgICAgICAgICAgbW0gICAgICAKICMjICAgICMjICAgICAiIiAgICAgICAgIiIiIyMgICAgICAgICAgICAgICAgICAgICAgIyMgICAgICAgICAgICAgICAgICAgICMjICAgICAKICMjICAgICMjICAgIyMjIyAgICAgICAgICAgIyMgICBtIyMjIyNtICAgbSMjIyMjbSAgIyMgbSMjIiAgICAgIG1tICAgICAgICIjbSAgICAKICMjIyMjIyMjICAgICAjIyAgICAgICAgICAgIyMgICAiIG1tbSMjICAjIyIgICAgIiAgIyNtIyMgICAgICAgICMjICAgICAgICAjIyAgICAKICMjICAgICMjICAgICAjIyAgICAgICAgICAgIyMgIG0jIyIiIiMjICAjIyAgICAgICAgIyMiIyNtICAgICAgICAgICAgICAgICAjIyAgICAKICMjICAgICMjICBtbW0jI21tbSAgI21tbW1tIyMgICMjbW1tIyMjICAiIyNtbW1tIyAgIyMgICIjbSAgICAgICMjICAgICAgIG0jIiAgICAKICIiICAgICIiICAiIiIiIiIiIiAgICIiIiIiICAgICAiIiIiICIiICAgICIiIiIiICAgIiIgICAiIiIgICAgICIiICAgICAgICMjICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIiIgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAK"
	echo $bnr | base64 -d 2>/dev/null
	echo $bnr | base64 -D 2>/dev/null # MacOS
}

function cleanup() {
	unset r_ua
	unset r_rf
	unset r_ip
	if [[ $(uname) != "Darwin" ]]; then
		if [[ $(cat /tmp/pid_max.bak 2>/dev/null) != "" ]]; then
			cat /tmp/pid_max.bak >/proc/sys/kernel/pid_max
			rm -rf /tmp/pid_max.bak
		fi
		if [[ -e '/tmp/hijack.temp.swp' ]]; then
			swapoff /tmp/hijack.temp.swp
			rm -rf /tmp/hijack.temp.swp
		fi
	fi
}

start
