# External dependancies
# Run 'bundler install' to download before running
require 'silkroad'
require 'sqlite3'
require 'sequel'
require 'json'

# Internal dependancies/models


# Variable declarations
silkroad = nil
db = nil
highest_block = 1
hash_array = []

def start_up_rpc
  paycoin_uri = URI::HTTP.build(['ligerzero459:k3ep48dl_s', '127.0.0.1', 9001, nil, nil, nil])
  silkroad = Silkroad::Client.new paycoin_uri, {}

  silkroad
end

def start_up_sequel
  db = Sequel.sqlite('../XPYBlockchain.sqlite')

  db.create_table? :blocks do
    primary_key :id
    String :hash, :unique=>true
    Fixnum :height, :unique=>true
    DateTime :blockTime
    Float :mint
    String :previousBlockHash
    String :flags
    index :hash
    index :height
  end

  db.create_table? :raw_blocks do
    primary_key :id
    Fixnum :height
    File :raw
    index :height
  end

  db.create_table? :transactions do
    primary_key :id
    String :txid
    Fixnum :blockId
    String :type
    Float :totalOutput
    Float :fees
    index :txid
    index :blockId
  end

  db.create_table? :raw_transactions do
    primary_key :id
    String :txid
    File :raw
    index :txid
  end

  db.create_table? :inputs do
    primary_key :id
    Fixnum :transactionId
    Fixnum :outputTransactionId
    String :outputTxid
    Float :value
    index :transactionId
    index :outputTransactionId
  end

  db.create_table? :outputs do
    primary_key :id
    Fixnum :transactionId
    Fixnum :n
    String :script
    String :type
    String :address
    Float :value
    index :address
    index [:transactionId, :value]
  end

  # Object models for tables
  require './models/block'
  require './models/raw_block'
  require './models/transaction'
  require './models/raw_transaction'
  require './models/input'
  require './models/output'

  # Put genesis block into db if not exists
  genesis_block = db[:blocks]
  if genesis_block.count == 0
    Block.create(
        :hash => '00000e5695fbec8e36c10064491946ee3b723a9fa640fc0e25d3b8e4737e53e3',
        :height => 0,
        :blockTime => '2014-11-29 00:00:10 UTC',
        :mint => 0.0,
        :previousBlockHash => '',
        :flags => 'proof-of-work stake-modifier'
    )
    puts 'Genesis block saved.'
  end

  db
end

silkroad = start_up_rpc
db = start_up_sequel

# Code for multiple blocks
# Will be updated once single block and transactions are read into DB

block_count =  silkroad.rpc 'getblockcount'
puts 'Total block count: ' << block_count.to_s
highest_block = db[:blocks].count != 0 ? (db[:blocks].max(:height)) + 1 : 1

sleep(3)

(highest_block..block_count).each do |block_num|
  hash = silkroad.rpc 'getblockhash', block_num
  block = silkroad.rpc 'getblock', hash

  db_raw_block = RawBlock.new
  db_raw_block.raw = JSON.pretty_generate(block)

  db_block = Block.new

  height = block.fetch("height").to_i
  time = block.fetch("time")
  mint = block.fetch("mint")
  prev_block_hash = block.fetch("previousblockhash")
  flags = block.fetch("flags")
  db_block.hash = hash
  db_block.height = height
  db_raw_block.height = height
  db_block.blockTime = time
  db_block.mint = mint
  db_block.previousBlockHash = prev_block_hash
  db_block.flags = flags
  db_block.save
  db_raw_block.save

  raw_txs = silkroad.batch do
    block['tx'].each do |tx|
      rpc 'getrawtransaction', tx
    end
  end

  decoded_txs = silkroad.batch do
    raw_txs.each do |raw_tx|
      rpc 'decoderawtransaction', raw_tx['result']
    end
  end

  decoded_txs.each do |decoded_tx|
    # puts decoded_tx.fetch("result")
    result = decoded_tx.fetch("result")
    txid = result.fetch("txid")
    # puts 'txid: ' << txid
    reward_block = false

    RawTransaction.create(:txid => txid, :raw => JSON.pretty_generate(decoded_tx))
    db_transaction = Transaction.create(:txid => txid, :blockId => db_block.id)

    vins = result.fetch("vin")
    total_input = 0

    vins.each_with_index do |vin, i|
      db_input = Input.create(:transactionId => db_transaction.id)

      if vin['coinbase'] != nil
        # puts 'coinbase: ' << "Generation & Fees"
        reward_block = true
      else
        previousOutputTxid = vin['txid']
        # puts 'previous output tx: ' << previousOutputTxid
        output = Output[:transactionId => Transaction[:txid => previousOutputTxid].id]
        db_input.outputTxid = previousOutputTxid
        db_input.outputTransactionId = output.transactionId
        total_input += output.value
        db_input.value = output.value
        db_input.save
      end
    end

    # puts 'total input: ' << total_input.to_s

    vouts = result.fetch("vout")
    total_output = 0
    stake = false

    # Loop through all outputs
    vouts.each do |vout|
      value = vout.fetch("value")
      total_output += value.round(6)
      # puts 'value: ' << value.round(6).to_s
      n = vout.fetch("n")
      # puts 'n: ' << n.to_s
      script = vout.fetch("scriptPubKey")
      asm = script.fetch("asm")
      # puts 'script: ' << asm
      type = script.fetch("type")
      # puts 'type: ' << type
      if type == 'nonstandard'
        if asm == '' || asm == 'OP_MICROPRIME'
          stake = true
        end
      end
      address = ''
      if type == "pubkey" || type == "pubkeyhash"
        address = script.fetch("addresses")[0]
        # puts 'address: ' << address
      end

      # Save output to database
      Output.create(
          :transactionId => db_transaction.id,
          :n => n,
          :script => asm,
          :type => type,
          :address => address,
          :value => value
      )
    end

    db_transaction.totalOutput = total_output.round(6)
    # puts 'total output: ' << total_output.round(6).to_s
    if stake && vouts.length > 1
      #set transaction type to PoS-Reward
      if vouts[1].fetch("scriptPubKey").fetch("addresses")[0] == vouts[2].fetch("scriptPubKey").fetch("addresses")[0]
        # Normal stake with no scrape address
        # puts 'Stake with no scrape'
        stake_amount = total_output - total_input
        db_transaction.fees = stake_amount.rount(6)
        # puts 'stake amount: ' << stake_amount.round(6).to_s
        db_transaction.type = 'PoS-Reward'
      else
        # Assume scrape address
        # puts 'Stake with scrape'
        stake_amount = vouts[2].fetch("value")
        db_transaction.fees = stake_amount.rount(6)
        # puts 'stake amount: ' << stake_amount.round(6).to_s
        db_transaction.type = 'PoS-Reward'
      end
    elsif !stake && reward_block
      # set transaction type to PoW-Reward
      db_transaction.fees = total_output.round(6)
      db_transaction.type ='PoW-Reward'
      # puts 'PoW-Reward'
    else
      # set transaction type to normal
      db_transaction.fees = (total_input - total_output).round(6)
      db_transaction.type = 'normal'
      # puts 'normal'
    end
    db_transaction.save
  end

  puts 'Block saved: #' << db_block.height.to_s
  # Increase highest block read
  highest_block += 1
end
