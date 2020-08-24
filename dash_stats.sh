#!/bin/bash
#set -x

# The current block found
height=$(dash-cli getblockcount)
if (( $? != 0 ));then echo "Problem running dash-cli exiting...";exit 1;fi



block=$(dash-cli getblock $(dash-cli getblockhash $height))

# Returns true or false
chain_lock=$(if [ $(jq -r '.chainlock' <<<$block) = "true" ];then echo "(Chainlocked)";else echo "(***Not Chainlocked***)";fi)


# Incremental write since it takes a while to do all the computation first.
echo -e "$height\tBlock height $chain_lock"



# Determine how many blocks behind the last chainlock is.
chainlock_lag=$(($height-$(dash-cli getbestchainlock|jq -r '.height')))

echo -e "$chainlock_lag\tBlocks since last Chainlock"


#  Difficulty in Mega
difficulty=$(echo "scale=2; $(dash-cli getinfo|jq -r '.difficulty')/1000000"|bc)
echo -e "$difficulty\tDifficulty (M)"

# Outstanding coin supply in millions.  Very expensive query to run!
coins=$(echo "scale=2; $(dash-cli gettxoutsetinfo|jq -r '.total_amount')/1000000"|bc)
echo -e "$coins\tTotal supply (M)"

# Number of TXes in the mempool
mempool_txes=$(dash-cli getmempoolinfo|jq -r '.size')
echo -e "$mempool_txes\tNumber of TXes in the mempool"

# Mempool size in bytes
mempool_kbytes=$(echo "scale=2;$(dash-cli getmempoolinfo|jq -r '.bytes')/1024"|bc)
echo -e "$mempool_kbytes\tMempool size (KBytes)"






current_time=$(jq -r '.time' <<<$block)
num_txes=$(jq -r '.tx | length' <<<$block)

previous_time=$current_time

	#  Go back in time for at least 1 hour (3600 seconds) of block time and sum the number of TXes during that time.
	until (( $previous_time <= $((current_time-3600)) ));do
		((height--))
		block=$(dash-cli getblock $(dash-cli getblockhash $height))
		previous_time=$(jq -r '.time' <<<$block)
		((num_txes+=$(jq -r '.tx | length' <<<$block)))
	done
diff_time=$((current_time - previous_time))
avg_tx_sec=$(echo "scale=6;$num_txes / $diff_time"|bc|awk '{printf "%0.4f", $0}')
echo -e "$avg_tx_sec\tAverage number of TXes/second."







# Collaterised Masternode count
masternode_count=$(dash-cli masternode count|jq .total)
echo -e "$masternode_count\tCollateralised MNs"



# List of valid DIP3 Masternode TX hashes
list_valid=$(dash-cli protx list valid|grep -v [][]|wc -l)
echo -e "$list_valid\tENABLED MNs"


# Variables for calculating the yearly ROI
reward_reduction_rate="1/14"
reward_reduction_interval=210240
previous_reward_reduction=840960
initial_reward_in_dash=1.67279909
block_interval=2.625
blocks_in_a_year="365.25*24*60/$block_interval"

roi=$(echo "scale=10;$initial_reward_in_dash*e(($height-$previous_reward_reduction)/$reward_reduction_interval*l(1-$reward_reduction_rate))*$blocks_in_a_year/$list_valid/10"|bc -l|sed 's/\([1234567890]*\.[1234567890][1234567890]\).*/\1%/')
echo -e "$roi\tMasternode annualised gross rate of return %"




dash_data=$(curl -s https://api.coinpaprika.com/v1/tickers/dash-dash?quotes=USD,BTC)
price=$(printf '$%.2f (%.2f%% 24 hr change)  /  %.4f BTC' $(jq .quotes.USD.price<<<$dash_data) $(jq .quotes.USD.percent_change_24h<<<$dash_data) $(jq .quotes.BTC.price<<<$dash_data))
echo "$price"





## Progress of DIP0008 hardfork in %
#windowBlocks=$(dash-cli getblockchaininfo | jq -r '.bip9_softforks.dip0008.windowBlocks')
#windowStart=$(dash-cli getblockchaininfo | jq -r '.bip9_softforks.dip0008.windowStart')
#dip0008Percent="$(echo "scale=4;$windowBlocks/($height-$windowStart)*100"|bc)"
#dip0008Percent=${dip0008Percent:0:5}"%"

#echo -e "$height\tBlock height\n$difficulty\tDifficulty (M)\n$mempool_txes\tNumber of TXes in the mempool\n$mempool_kbytes\tMempool size (KBytes)\n$masternode_count\tCollateralised MNs\n$list_valid\tDIP3 Registered DMNs\n$roi\tMasternode annualised gross rate of return %\n$dip0008Percent\tMiners signalling for DIP8 readiness %"

#echo -e "$height\tBlock height $chain_lock\n$chainlock_lag\tBlocks since last Chainlock\n$difficulty\tDifficulty (M)\n$coins\tTotal supply (M)\n$mempool_txes\tNumber of TXes in the mempool\n$mempool_kbytes\tMempool size (KBytes)\n$masternode_count\tCollateralised MNs\n$list_valid\tENABLED MNs\n$roi\tMasternode annualised gross rate of return %"


