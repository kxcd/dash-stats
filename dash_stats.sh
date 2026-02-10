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

tabs 8

# The current block found
height=$(dash-cli getblockcount)
if (( $? != 0 ));then echo "Problem running dash-cli exiting...";exit 1;fi

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
COINS=12.58
COINS_TIME=1770705478
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
masternode_count=$(jq .detailed.regular.total<<<"$masternode")
#echo -e "$light_blue$masternode_count$none\tCollateralised 1k MNs"



# List of valid DIP3 Masternode TX hashes
enabled=$(jq .detailed.regular.enabled<<<"$masternode")
#echo -e "$light_blue$enabled$none\tENABLED 1k MNs"
echo -e "$light_blue$masternode_count/$enabled$none 1k MNs (Total/Enabled)"

masternode_count_4k=$(jq .detailed.evo.total<<<"$masternode")
#echo -e "$light_blue$masternode_count_4k$none\tCollateralised 4k MNs"

enabled_4k=$(jq .detailed.evo.enabled<<<"$masternode")
#echo -e "$light_blue$enabled_4k$none\tENABLED 4k MNs"
echo -e "$light_blue$masternode_count_4k/$enabled_4k$none\t4k MNs (Total/Enabled)"


# Average age of a masternode in days, similar to coin days destroyed.
MN_AGE=1212.09
MN_AGE_TIME=1770708567
if ((MN_AGE_TIME + 1200 < EPOCHSECONDS));then
	# This RPC call is expensive, so only call it infrequently.
	protx_list=$(dash-cli protx list valid 1)
	MN_AGE=$(jq '.[].state.registeredHeight'<<<"$protx_list"| awk -v height="$height" '{sum+=height-$1}END{print sum/NR*2.625/60/24}')
	sed -i "s/\(^MN_AGE_TIME=\).*/\1$EPOCHSECONDS/" "$0"
	sed -i "s/\(^MN_AGE=\).*/\1$MN_AGE/" "$0"
fi
echo -e "$light_blue$MN_AGE$none\tAverage age of MN (Days)"




# Next subsidy reduction
daysToSubsidyReduction(){
	#local block_time=2.625
	local halving_block=1261441
	local halving_interval=210240
	local blocks_til_reduction
	local days
	local len
	blocks_til_reduction=$((halving_interval-((height-halving_block)%halving_interval)))
	#days=$(bc <<< "scale=1;$blocks_til_reduction*$block_time/60/24")
	# Avoid use of bc by changing the calculation.
	days=$((blocks_til_reduction*1000/54857))
	# Divide by 10 again here.
	len=$((${#days}-1))
	echo "${days:0:$len}.${days:$len}"
	#echo "$days"
}
echo -e "$light_blue$(daysToSubsidyReduction)$none\tDays til subsidy reduction"




#enabled_weight=4170
enabled_weight=$((enabled+enabled_4k*4))

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

calcRoiPreV20(){
	# General idea compute the reward for every n blocks and accumulate it.
	# where n is the number of enabled MNs.
	reward=0
	for((block=current_block; block<last_block_of_the_year; block+=enabled_weight));do

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
}

calcRoiPostV20(){
	reward=0
	block_reward_v20=1.53978154
	FIRST_REWARD_BLOCK=1892161

	for((block=current_block; block<last_block_of_the_year; block+=enabled_weight));do
		# Find which halving period we are on
		blocks_since_halving=$((block-FIRST_REWARD_BLOCK))
		halving_period=$((blocks_since_halving/HALVING_INTERVAL))

		reward=$(echo "scale=8;base_reward=$block_reward_v20 * (1 - $HALVING_REDUCTION_AMOUNT)^$halving_period;$reward+base_reward"|bc -l)
	done
}

calcRoiPostV21(){
	# Re-compute this var to the new rules where the eMN gets paid only once per cycle.
	enabled_weight=$((enabled+enabled_4k))
	calcRoiPostV20
	reward=$(echo "scale=8;$reward * 0.625"|bc -l)
}

# Decide which version to use for the calculation of ROI.
if ((current_block<1987776));then
	calcRoiPreV20
elif ((current_block<2128895));then
	calcRoiPostV20
else
	calcRoiPostV21
fi


roi=$(echo "scale=2;$reward/10"|bc)
echo -e "$light_blue${roi}%$none\tMasternode annualised gross rate of return %"






hardfork(){
	fork="withdrawals"
	blockchaininfo=$(dash-cli getblockchaininfo)
	status=$(jq -r ".softforks.$fork.bip9.status"<<<"$blockchaininfo")
	case $status in
		defined)
			echo -e "$fork hardfork has not yet started."
			;;
		started)
			#windowBlocks=$(jq -r ".softforks.$fork.bip9.tatistics.period"<<<"$blockchaininfo")
			#windowStart=$(jq -r ".softforks.$fork.bip9.windowStart"<<<"$blockchaininfo")
			count=$(jq -r ".softforks.$fork.bip9.statistics.count"<<<"$blockchaininfo")
			elapsed=$(jq -r ".softforks.$fork.bip9.statistics.elapsed"<<<"$blockchaininfo")
			forkPercent=$(echo "scale=4;$count/$elapsed*100"|bc)
			forkPercent=$(printf '%.2f%%' $forkPercent)
			threshold=$(jq -r ".softforks.$fork.bip9.statistics.threshold"<<<"$blockchaininfo")
			period=$(jq -r ".softforks.$fork.bip9.statistics.period"<<<"$blockchaininfo")
			requiredPercent=$(echo "scale=4;$threshold/$period*100"|bc)
			requiredPercent=$(printf '%.2f%%' $requiredPercent)
			progressPercent=$(echo "scale=4;$elapsed/$period*100"|bc)
			progressPercent=$(printf '%.2f%%' $progressPercent)
			echo -e "$light_blue$forkPercent$none\tMiners signalling for $fork HF readiness %"
			echo -e "$light_blue$requiredPercent$none\tTarget required for this window %"
			echo -e "$light_blue$progressPercent$none\tProgress through this window %"
			;;
		locked_in)
			since=$(jq -r ".softforks.$fork.bip9.since"<<<"$blockchaininfo")
			echo "The $fork hardfork is locked in since block $since ($((since+4032-height)))"
			;;
		active)
			echo "Hard fork is active."
			;;
		*)
			echo "Hard fork unhandled status."
			;;
	esac
}
#hardfork

price(){
	dash_data=$(curl -s https://api.coinpaprika.com/v1/tickers/dash-dash?quotes=USD,BTC)
	# Only attempt to print the price when the call returns data and that data is not an error.
	if [[ -n $dash_data && ! $dash_data =~ "503 Service Unavailable" ]];then
		price_usd=$(jq .quotes.USD.price<<<$dash_data)
		# Test for a valid number.
		regex="^[-+]?[0-9]+\.?[0-9]*$"
		[[ $price_usd =~ $regex ]] || return
		price_usd=$(printf '$%.2f' $price_usd)
		percent_change=$(jq .quotes.USD.percent_change_24h<<<$dash_data)
		[[ $percent_change =~ $regex ]] || return
		percent_change=$(printf '%.2f%%' $percent_change)
		grep -q \- <<<"$percent_change"&&percent_change=$red$percent_change$none||percent_change=$green$percent_change$none
		price_btc=$(jq .quotes.BTC.price<<<$dash_data)
		[[ $price_btc =~ $regex ]] || return
		price_btc=$(printf '%.4f'  $price_btc)
		echo -e "$light_blue$price_usd$none ($percent_change 24 hr change)  /  $light_blue$price_btc$none BTC"
	fi
}
price

_convert_time_units()(
	local time_num
	local time_units
	if(($1>1200));then
        time_num=$(bc <<< "scale=3;$1*$BLOCK_TIME/60/24")
        time_units="days"
    elif(($1>120));then
		time_num=$(bc <<< "scale=3;$1*$BLOCK_TIME/60")
		time_units="hours"
	else
		time_num=$(bc <<< "scale=3;$1*$BLOCK_TIME")
		time_units="minutes"
	fi
	time_num=$(printf '%.1f' $time_num)
	echo "$time_num $time_units"
)

superblock(){
	local govinfo
	local superblockmaturitywindow
	local nextsuperblock
	local gap
	govinfo=$(dash-cli getgovernanceinfo)
	superblockmaturitywindow=$(jq '.superblockmaturitywindow' <<< "$govinfo")
	nextsuperblock=$(jq '.nextsuperblock' <<< "$govinfo")
	gap=$((nextsuperblock-height-superblockmaturitywindow))
	if((gap>0));then
		echo "Voting deadline is in $(_convert_time_units $gap) and the next super block will be in $(_convert_time_units $((nextsuperblock-height)))."
	else
		echo "Voting deadline has passed, the next super block will be in $(_convert_time_units $((gap+superblockmaturitywindow)))."
	fi
}
superblock

