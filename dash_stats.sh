#!/bin/bash
#set -x

# Create some colours for making the text prettier
none="\e[0m"
red="\e[31m"
green="\e[32m"
yellow="\e[33m"
blue="\e[34m"
magenta="\e[35m"
cyan="\e[36m"
light_gray="\e[37m"
dark_gray="\e[90m"
light_red="\e[91m"
light_green="\e[92m"
light_yellow="\e[93m"
light_blue="\e[94m"
light_magenta="\e[95m"
light_cyan="\e[96m"
white="\e[97m"

# Checks that the required software is installed on this machine.
bc -v >/dev/null 2>&1 || progs+=" bc"
jq -V >/dev/null 2>&1 || progs+=" jq"

if [[ -n $progs ]];then
	text="Missing applications on your system, please run\n\n"
	text+="\tsudo apt install $progs\n\nbefore running this program again."
	echo -e "$text" >&2
	exit 1
fi

# The current block found
height=$(dash-cli getblockcount)
if (( $? != 0 ));then echo "Problem running dash-cli exiting...";exit 1;fi

date +"%t%F %X"

# From now on, hard exit on any further errors.
set -e

block=$(dash-cli getblock $(dash-cli getblockhash $height))

# Returns true or false
chain_lock=$(if [[ $(jq -r '.chainlock' <<<$block) == "true" ]];then echo "$light_green(Chainlocked)$none";else echo "$light_red(***Not Chainlocked***)$none";fi)


# Incremental write since it takes a while to do all the computation first.
echo -e "$light_blue$height$none\tBlock height $chain_lock"



# Determine how many blocks behind the last chainlock is.
bestchainlock=$(dash-cli getbestchainlock 2>/dev/null|jq -r '.height')
if [[ -z $bestchainlock ]];then
	chainlock_lag="???"
else
	chainlock_lag=$((height-bestchainlock))
fi

echo -e "$light_blue$chainlock_lag$none\tBlocks since last Chainlock"


#  Difficulty in Mega
difficulty=$(echo "scale=2; $(dash-cli getblockchaininfo|jq -r '.difficulty')/1000000"|bc)
echo -e "$light_blue$difficulty$none\tDifficulty (M)"

# Outstanding coin supply in millions.  Very expensive query to run!
COINS=10.22
COINS_TIME=1626245044
if ((COINS_TIME + 3600 < EPOCHSECONDS));then
	COINS=$(echo "scale=2; $(dash-cli gettxoutsetinfo|jq -r '.total_amount')/1000000"|bc)
	sed -i "s/\(^COINS_TIME=\).*/\1$EPOCHSECONDS/" "$0"
	sed -i "s/\(^COINS=\).*/\1$COINS/" "$0"
fi
echo -e "$light_blue$COINS$none\tTotal supply (M)"


# Number of TXes in the mempool
mempoolinfo=$(dash-cli getmempoolinfo)
mempool_txes=$(jq -r '.size'<<<"$mempoolinfo")
echo -e "$light_blue$mempool_txes$none\tNumber of TXes in the mempool"

# Mempool size in bytes
mempool_kbytes=$(printf '%0.2f' $(echo "scale=2;$(jq -r '.bytes'<<<"$mempoolinfo")/1024"|bc))
echo -e "$light_blue$mempool_kbytes$none\tMempool size (KBytes)"






current_time=$(jq -r '.time' <<<$block)
num_txes=$(jq -r '.tx | length' <<<$block)

previous_time=$current_time
_height=$height

#  Go back in time for at least 1 hour (3600 seconds) of block time and sum the number of TXes during that time.
until (( previous_time <= current_time-3600 ));do
	((_height--))
	block=$(dash-cli getblock $(dash-cli getblockhash $_height))
	previous_time=$(jq -r '.time' <<<$block)
	((num_txes+=$(jq -r '.tx | length' <<<$block)))
done
diff_time=$((current_time - previous_time))
avg_tx_sec=$(printf '%0.4f' $(bc<<<"scale=6;$num_txes / $diff_time"))
echo -e "$light_blue$avg_tx_sec$none\tAverage number of TXes/second"







# Collaterised Masternode count
masternode=$(dash-cli masternode count)
masternode_count=$(jq .total<<<"$masternode")
echo -e "$light_blue$masternode_count$none\tCollateralised MNs"



# List of valid DIP3 Masternode TX hashes
enabled=$(jq .enabled<<<"$masternode")
echo -e "$light_blue$enabled$none\tENABLED MNs"


# Average age of a masternode in days, similar to coin days destroyed.
MN_AGE=561.865
MN_AGE_TIME=1626247591
if ((MN_AGE_TIME + 1200 < EPOCHSECONDS));then
	# This RPC call is expensive, so only call it infrequently.
	protx_list=$(dash-cli protx list valid 1)
	MN_AGE=$(jq '.[].state.registeredHeight'<<<"$protx_list"| awk -v height="$height" '{sum+=height-$1}END{print sum/NR*2.625/60/24}')
	sed -i "s/\(^MN_AGE_TIME=\).*/\1$EPOCHSECONDS/" "$0"
	sed -i "s/\(^MN_AGE=\).*/\1$MN_AGE/" "$0"
fi
echo -e "$light_blue$MN_AGE$none\tAverage age of MN (Days)"


#enabled=4440


# Variables for calculating the yearly ROI
FIRST_REALLOC=1379128
BLOCK_TIME=2.625
SUPER_BLOCK_CYCLE=16616
HALVING_INTERVAL=210240
FIRST_REWARD_BLOCK=1261441
HALVING_REDUCTION_AMOUNT="1/14"
STARTING_BLOCK_REWARD=1.44236248
REALLOC_AMOUNT=(513 526 533 540 546 552 557 562 567 572 577 582 585 588 591 594 597 599 600)

current_block=$height
# For what if calculations.
#current_block=$(bc <<<"1433297 +(60/2.625*24*120)")

blocks_per_year=$(printf '%.0f' $(bc<<<"scale=4;60/$BLOCK_TIME*24*365.25"))
last_block_of_the_year=$((current_block+blocks_per_year))


# General idea compute the reward for every n blocks and accumulate it.
# where n is the number of enabled MNs.
reward=0
for((block=current_block; block<last_block_of_the_year; block+=enabled));do

	# Find which halving period we are on
	blocks_since_halving=$((block-FIRST_REWARD_BLOCK))
	halving_period=$((blocks_since_halving/HALVING_INTERVAL))

	# Find which realloc period we are on.
	blocks_since_realloc=$((block-FIRST_REALLOC))
	# We start counting our periods from zero, each realloc period lasts for 3 super blocks.
	period=$((blocks_since_realloc/(SUPER_BLOCK_CYCLE*3)))
	if ((period>18));then
		period=18
	fi

	# Combined bc statement.
	reward=$(echo "scale=8;base_reward=$STARTING_BLOCK_REWARD * (1 - $HALVING_REDUCTION_AMOUNT)^$halving_period;new_reward=base_reward / 500 * ${REALLOC_AMOUNT[$period]};$reward+new_reward"|bc -l)
done

roi=$(echo "scale=2;$reward/10"|bc)
echo -e "$light_blue${roi}%$none\tMasternode annualised gross rate of return %"









dash_data=$(curl -s https://api.coinpaprika.com/v1/tickers/dash-dash?quotes=USD,BTC)
# Only attempt to print the price when the call returns data and that data is not an error.
if [[ -n $dash_data && ! $dash_data =~ "503 Service Unavailable" ]];then
	price_usd=$(printf '$%.2f' $(jq .quotes.USD.price<<<$dash_data))
	percent_change=$(printf '%.2f%%' $(jq .quotes.USD.percent_change_24h<<<$dash_data))
	grep -q \- <<<"$percent_change"&&percent_change=$red$percent_change$none||percent_change=$green$percent_change$none
	price_btc=$(printf '%.4f'  $(jq .quotes.BTC.price<<<$dash_data))
	echo -e "$light_blue$price_usd$none ($percent_change 24 hr change)  /  $light_blue$price_btc$none BTC"
fi


blockchaininfo=$(dash-cli getblockchaininfo)
status=$(jq -r '.bip9_softforks.dip0020.status'<<<"$blockchaininfo")
case $status in
	defined)
		echo -e "dip0020 hardfork has not yet started."
		;;
	started)
		windowBlocks=$(jq -r '.bip9_softforks.dip0020.windowBlocks'<<<"$blockchaininfo")
		windowStart=$(jq -r '.bip9_softforks.dip0020.windowStart'<<<"$blockchaininfo")
		count=$(jq -r '.bip9_softforks.dip0020.statistics.count'<<<"$blockchaininfo")
		elapsed=$(jq -r '.bip9_softforks.dip0020.statistics.elapsed'<<<"$blockchaininfo")
		forkPercent=$(echo "scale=4;$count/$elapsed*100"|bc)
		forkPercent=$(printf '%.2f%%' $forkPercent)
		threshold=$(jq -r '.bip9_softforks.dip0020.statistics.threshold'<<<"$blockchaininfo")
		period=$(jq -r '.bip9_softforks.dip0020.statistics.period'<<<"$blockchaininfo")
		requiredPercent=$(echo "scale=4;$threshold/$period*100"|bc)
		requiredPercent=$(printf '%.2f%%' $requiredPercent)
		progressPercent=$(echo "scale=4;$elapsed/$period*100"|bc)
		progressPercent=$(printf '%.2f%%' $progressPercent)
		echo -e "$light_blue$forkPercent$none\tMiners signalling for dip0020 HF readiness %"
		echo -e "$light_blue$requiredPercent$none\tTarget required for this window %"
		echo -e "$light_blue$progressPercent$none\tProgress through this window %"
		;;
	locked_in)
		since=$(jq -r '.bip9_softforks.dip0020.since'<<<"$blockchaininfo")
		echo "The dip0020 hardfork is locked in since block $since"
		;;
	active)
		echo "Hard fork is active."
		;;
	*)
		echo "Hard fork unhandled status."
		;;
esac




# First arg is the time in minutes.
# Second arg is V for vote time, and S for super block time
_convert_time_units(){
	if (( $# != 2 ));then return 1;fi
	if (( $(echo "$1>2880"|bc -l) ));then
		_TIME=$(echo "scale=2;$1/60/24"|bc)
		_UNITS="days"
	elif (( $(echo "scale=2;$1>300"|bc -l) ));then
		_TIME=$(echo "$1/60"|bc)
		_UNITS="hours"
	else
		# Nothing to convert, just return
		return 0
	fi
	case $2 in
		S)
			S_TIME="$_TIME";S_UNITS="$_UNITS"
			;;
		V)
			V_TIME="$_TIME";V_UNITS="$_UNITS"
			;;
		*)
			return 2
			;;
	esac
}

superblock(){
	# A super block occurs every 16616 blocks
	SUPER_BLOCK_INTERVAL=16616
	# The voting deadline occurs 1662 blocks before the super block.
	VOTING_DEADLINE=1662
	# A Super block from the past.
	SUPER_BLOCK=880648
	# The time taken to create a new block
	BLOCK_TIME=2.625
	S_UNITS="minutes";V_UNITS="minutes"

	CURRENT_BLOCK=$height
	if [[ -z "$CURRENT_BLOCK" || "$CURRENT_BLOCK" -lt 1 ]];then
		echo "Cannot determine current block, exiting..."
		return 1;
	fi

	while : ;do
		if ((SUPER_BLOCK-VOTING_DEADLINE-CURRENT_BLOCK < 0));then
			if ((SUPER_BLOCK-CURRENT_BLOCK < 0));then
				((SUPER_BLOCK+=SUPER_BLOCK_INTERVAL))
			else
				S_TIME=$(echo "$((SUPER_BLOCK-CURRENT_BLOCK))* $BLOCK_TIME"|bc)
				_convert_time_units "$S_TIME" S
				echo "Voting deadline has passed, the next super block will be in $S_TIME $S_UNITS."
				break
			fi
		else
			S_TIME=$(echo "$((SUPER_BLOCK-CURRENT_BLOCK))* $BLOCK_TIME"|bc)
			_convert_time_units "$S_TIME" S
			V_TIME=$(echo "$((SUPER_BLOCK-VOTING_DEADLINE-CURRENT_BLOCK))* $BLOCK_TIME"|bc)
			_convert_time_units "$V_TIME" V
			echo "Voting deadline is in $V_TIME $V_UNITS and the next super block will be in $S_TIME $S_UNITS."
			break
		fi
	done
	unset SUPER_BLOCK SUPER_BLOCK_INTERVAL CURRENT_BLOCK S_TIME S_UNITS BLOCK_TIME VOTING_DEADLINE V_TIME V_UNITS _TIME _UNITS
}
superblock


